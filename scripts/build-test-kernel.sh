#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

# shellcheck source=../kernel/build.env
source "${repo_root}/kernel/build.env"
"${script_dir}/preflight-test-kernel-build.sh"

if [[ $(uname -m) != aarch64 ]] || [[ $(dpkg --print-architecture) != arm64 ]]; then
    printf 'The kernel build requires a native ARM64 runner\n' >&2
    exit 2
fi
[[ ${GITHUB_ACTIONS:-} == true ]] || {
    printf 'Full kernel compilation is restricted to GitHub Actions\n' >&2
    exit 2
}
[[ -n ${RUNNER_TEMP:-} ]] || {
    printf 'RUNNER_TEMP is required\n' >&2
    exit 2
}

readonly work_root="${RUNNER_TEMP}/eaidk610-typec-build"
readonly armbian_dir="${work_root}/armbian-build"
readonly artifacts_dir="${repo_root}/artifacts"
readonly debs_dir="${artifacts_dir}/debs"
readonly config_path="${repo_root}/${KERNEL_CONFIG}"
readonly patch_path="${repo_root}/${KERNEL_PATCH}"
readonly family_path="${repo_root}/kernel/armbian/rockchip64-family.conf"

[[ ! -e ${armbian_dir} ]] || {
    printf 'Refusing to reuse build directory: %s\n' "${armbian_dir}" >&2
    exit 2
}
install -d "${work_root}" "${artifacts_dir}" "${debs_dir}"

# Pin the framework itself, then use only its supported userpatches interface.
git init --quiet "${armbian_dir}"
git -C "${armbian_dir}" remote add origin "${ARMBIAN_BUILD_REPOSITORY}"
git -C "${armbian_dir}" fetch --depth=1 --filter=blob:none \
    origin "${ARMBIAN_BUILD_COMMIT}"
git -C "${armbian_dir}" checkout --quiet --detach FETCH_HEAD
[[ $(git -C "${armbian_dir}" rev-parse HEAD) == "${ARMBIAN_BUILD_COMMIT}" ]]

[[ -x ${armbian_dir}/compile.sh ]]
[[ -f ${armbian_dir}/config/sources/families/rockchip64.conf ]]
[[ -d ${armbian_dir}/patch/kernel/${ARMBIAN_KERNEL_PATCH_DIR} ]]

install -D -m 0644 "${config_path}" \
    "${armbian_dir}/userpatches/config/kernel/${ARMBIAN_LINUXCONFIG}.config"
install -D -m 0644 "${patch_path}" \
    "${armbian_dir}/userpatches/kernel/${ARMBIAN_KERNEL_PATCH_DIR}/$(basename "${patch_path}")"
install -D -m 0644 "${family_path}" \
    "${armbian_dir}/userpatches/config/sources/families/rockchip64.conf"

printf 'Building %s with the standard Armbian kernel command\n' \
    "${EXPECTED_KERNELRELEASE}"
printf 'Armbian=%s Linux=%s\n' "${ARMBIAN_BUILD_COMMIT}" "${LINUX_COMMIT}"

# This is the modern Armbian kernel-only CLI. Armbian owns source preparation,
# patch ordering, Kbuild, modules/DTBs installation, and Debian packaging.
(
    cd "${armbian_dir}"
    ./compile.sh kernel \
        BOARD="${ARMBIAN_BOARD}" \
        BRANCH="${ARMBIAN_BRANCH}" \
        RELEASE=bookworm \
        BUILD_MINIMAL=yes \
        BUILD_DESKTOP=no \
        KERNEL_CONFIGURE=no \
        KERNELSOURCE="${LINUX_REPOSITORY}" \
        KERNELBRANCH="commit:${LINUX_COMMIT}" \
        EXTRAWIFI=no \
        KERNEL_BTF=yes \
        ARTIFACT_IGNORE_CACHE=yes \
        SHARE_LOG=no
)

# Record framework success immediately. Nothing below recompiles or repackages
# the kernel; it only copies and validates Armbian's canonical .deb outputs.
{
    printf 'armbian_compile_sh_kernel=success\n'
    printf 'expected_kernelrelease=%s\n' "${EXPECTED_KERNELRELEASE}"
    printf 'armbian_commit=%s\n' "${ARMBIAN_BUILD_COMMIT}"
    printf 'linux_commit=%s\n' "${LINUX_COMMIT}"
} >"${artifacts_dir}/KERNEL-BUILD-SUCCEEDED.txt"

# Armbian may run build phases through sudo or its container.
sudo chown -R "$(id -u):$(id -g)" "${armbian_dir}/output"

mapfile -d '' built_debs < <(
    find "${armbian_dir}/output/debs" -maxdepth 1 -type f \
        -name '*.deb' -print0 | sort -z
)
(( ${#built_debs[@]} > 0 )) || {
    printf 'Armbian returned success but output/debs contains no packages\n' >&2
    exit 3
}
for deb in "${built_debs[@]}"; do
    cp -a "${deb}" "${debs_dir}/"
done

mapfile -d '' image_debs < <(
    find "${debs_dir}" -maxdepth 1 -type f \
        -name "linux-image-${ARMBIAN_BRANCH}-${ARMBIAN_LINUXFAMILY}_*.deb" \
        -print0 | sort -z
)
mapfile -d '' dtb_debs < <(
    find "${debs_dir}" -maxdepth 1 -type f \
        -name "linux-dtb-${ARMBIAN_BRANCH}-${ARMBIAN_LINUXFAMILY}_*.deb" \
        -print0 | sort -z
)
[[ ${#image_debs[@]} -eq 1 ]] || {
    printf 'Expected exactly one Armbian image package, found %s\n' \
        "${#image_debs[@]}" >&2
    exit 3
}
[[ ${#dtb_debs[@]} -eq 1 ]] || {
    printf 'Expected exactly one Armbian DTB package, found %s\n' \
        "${#dtb_debs[@]}" >&2
    exit 3
}

readonly image_deb="${image_debs[0]}"
readonly dtb_deb="${dtb_debs[0]}"
[[ $(dpkg-deb -f "${image_deb}" Package) == \
   "linux-image-${ARMBIAN_BRANCH}-${ARMBIAN_LINUXFAMILY}" ]]
[[ $(dpkg-deb -f "${dtb_deb}" Package) == \
   "linux-dtb-${ARMBIAN_BRANCH}-${ARMBIAN_LINUXFAMILY}" ]]
[[ $(dpkg-deb -f "${image_deb}" Architecture) == arm64 ]]
[[ $(dpkg-deb -f "${dtb_deb}" Architecture) == arm64 ]]

image_contents=$(mktemp)
dtb_contents=$(mktemp)
trap 'rm -f "${image_contents}" "${dtb_contents}"' EXIT
dpkg-deb --fsys-tarfile "${image_deb}" | tar -tf - >"${image_contents}"
dpkg-deb --fsys-tarfile "${dtb_deb}" | tar -tf - >"${dtb_contents}"
grep -Fqx "./boot/vmlinuz-${EXPECTED_KERNELRELEASE}" "${image_contents}"
grep -Fq "./lib/modules/${EXPECTED_KERNELRELEASE}/" "${image_contents}"
grep -Fqx \
    "./boot/dtb-${EXPECTED_KERNELRELEASE}/rockchip/rk3399-eaidk-610.dtb" \
    "${dtb_contents}"
rm -f "${image_contents}" "${dtb_contents}"
trap - EXIT

{
    printf 'repository_commit=%s\n' \
        "${GITHUB_SHA:-$(git -C "${repo_root}" rev-parse HEAD)}"
    printf 'github_run_id=%s\n' "${GITHUB_RUN_ID:-local}"
    printf 'runner_arch=%s\n' "$(uname -m)"
    printf 'armbian_commit=%s\n' "${ARMBIAN_BUILD_COMMIT}"
    printf 'linux_commit=%s\n' "${LINUX_COMMIT}"
    printf 'kernelrelease=%s\n' "${EXPECTED_KERNELRELEASE}"
    printf 'config_sha256=%s\n' "${KERNEL_CONFIG_SHA256}"
    printf 'patch_sha256=%s\n' "${KERNEL_PATCH_SHA256}"
    printf 'family_sha256=%s\n' "${ARMBIAN_FAMILY_SHA256}"
    printf 'image_package=%s\n' "$(basename "${image_deb}")"
    printf 'image_package_version=%s\n' "$(dpkg-deb -f "${image_deb}" Version)"
    printf 'dtb_package=%s\n' "$(basename "${dtb_deb}")"
    printf 'dtb_package_version=%s\n' "$(dpkg-deb -f "${dtb_deb}" Version)"
} >"${artifacts_dir}/BUILD-MANIFEST.txt"

printf 'ARMBIAN_KERNEL_PACKAGES_OK\n' \
    >"${artifacts_dir}/ARMBIAN-KERNEL-PACKAGES-SUCCEEDED.txt"
printf 'Armbian kernel build and package validation succeeded: %s\n' \
    "${EXPECTED_KERNELRELEASE}"
find "${artifacts_dir}" -maxdepth 2 -type f -printf '%P\n' | sort
