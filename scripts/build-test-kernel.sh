#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

# shellcheck source=../kernel/build.env
source "${repo_root}/kernel/build.env"

# Keep all deterministic input/parser failures ahead of the expensive build.
"${script_dir}/preflight-test-kernel-build.sh"

require_value() {
	local name="$1"
	if [[ -z "${!name:-}" ]]; then
		echo "Required build input ${name} is empty" >&2
		exit 2
	fi
}

for name in \
	ARMBIAN_BUILD_REPOSITORY ARMBIAN_BUILD_COMMIT ARMBIAN_BOARD \
	ARMBIAN_BRANCH ARMBIAN_KERNEL_SERIES ARMBIAN_LINUXFAMILY \
	ARMBIAN_LINUXCONFIG ARMBIAN_KERNEL_PATCH_DIR LINUX_REPOSITORY \
	LINUX_COMMIT KERNEL_CONFIG KERNEL_PATCH EXPECTED_KERNELRELEASE; do
	require_value "${name}"
done

if [[ "$(uname -m)" != "aarch64" ]] || [[ "$(dpkg --print-architecture)" != "arm64" ]]; then
	echo "This kernel must be built natively on an ARM64 runner" >&2
	exit 2
fi
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
	echo "Full kernel compilation is restricted to GitHub Actions" >&2
	exit 2
fi
if [[ -z "${RUNNER_TEMP:-}" ]]; then
	echo "RUNNER_TEMP is required" >&2
	exit 2
fi

if [[ ! "${ARMBIAN_BUILD_COMMIT}" =~ ^[0-9a-f]{40}$ ]] ||
	[[ ! "${LINUX_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
	echo "Armbian and Linux inputs must be full 40-character commits" >&2
	exit 2
fi

config_path="${repo_root}/${KERNEL_CONFIG}"
patch_path="${repo_root}/${KERNEL_PATCH}"
family_override_path="${repo_root}/kernel/armbian/rockchip64-family.conf"

for input_path in "${config_path}" "${patch_path}" "${family_override_path}"; do
	if [[ ! -f "${input_path}" ]]; then
		echo "Missing build input: ${input_path}" >&2
		exit 2
	fi
done

grep -Fqx "declare -g LINUXFAMILY=\"${ARMBIAN_LINUXFAMILY}\"" \
	"${family_override_path}" || {
	echo "Armbian family override disagrees with ARMBIAN_LINUXFAMILY" >&2
	exit 2
}
grep -Fqx "declare -g LINUXCONFIG=\"${ARMBIAN_LINUXCONFIG}\"" \
	"${family_override_path}" || {
	echo "Armbian family override disagrees with ARMBIAN_LINUXCONFIG" >&2
	exit 2
}
grep -Fqx "declare -g KERNELPATCHDIR=\"${ARMBIAN_KERNEL_PATCH_DIR}\"" \
	"${family_override_path}" || {
	echo "Armbian family override disagrees with ARMBIAN_KERNEL_PATCH_DIR" >&2
	exit 2
}

runner_temp="${RUNNER_TEMP}"
work_root="${runner_temp}/eaidk610-typec-build"
armbian_dir="${work_root}/armbian-build"
artifacts_dir="${repo_root}/artifacts"
package_dir="${artifacts_dir}/package"
debs_dir="${artifacts_dir}/debs"

mkdir -p "${work_root}" "${artifacts_dir}" "${package_dir}" "${debs_dir}"

if [[ -e "${armbian_dir}" ]]; then
	echo "Refusing to reuse existing build directory: ${armbian_dir}" >&2
	exit 2
fi

git init "${armbian_dir}"
git -C "${armbian_dir}" remote add origin "${ARMBIAN_BUILD_REPOSITORY}"
git -C "${armbian_dir}" fetch --depth=1 --filter=blob:none origin "${ARMBIAN_BUILD_COMMIT}"
git -C "${armbian_dir}" checkout --detach FETCH_HEAD

actual_armbian_commit="$(git -C "${armbian_dir}" rev-parse HEAD)"
if [[ "${actual_armbian_commit}" != "${ARMBIAN_BUILD_COMMIT}" ]]; then
	echo "Armbian commit mismatch: ${actual_armbian_commit}" >&2
	exit 2
fi

install -D -m 0644 "${config_path}" \
	"${armbian_dir}/userpatches/config/kernel/${ARMBIAN_LINUXCONFIG}.config"
install -D -m 0644 "${patch_path}" \
	"${armbian_dir}/userpatches/kernel/${ARMBIAN_KERNEL_PATCH_DIR}/$(basename "${patch_path}")"
install -D -m 0644 "${family_override_path}" \
	"${armbian_dir}/userpatches/config/sources/families/rockchip64.conf"

config_sha256="$(sha256sum "${config_path}" | awk '{print $1}')"
patch_sha256="$(sha256sum "${patch_path}" | awk '{print $1}')"

echo "Building ${EXPECTED_KERNELRELEASE} on $(uname -m)"
echo "Armbian ${ARMBIAN_BUILD_COMMIT}; Linux ${LINUX_COMMIT}"
echo "Config SHA256 ${config_sha256}; patch SHA256 ${patch_sha256}"

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

{
	printf 'kernel_compile_and_package=success\n'
	printf 'expected_kernelrelease=%s\n' "${EXPECTED_KERNELRELEASE}"
	printf 'armbian_commit=%s\n' "${actual_armbian_commit}"
	printf 'linux_commit=%s\n' "${LINUX_COMMIT}"
} > "${artifacts_dir}/KERNEL-BUILD-SUCCEEDED.txt"

# Armbian relaunches privileged build phases through sudo.
sudo chown -R "$(id -u):$(id -g)" "${armbian_dir}/output"

# Preserve every Armbian-produced package before optional source/metadata
# inspection. A later verifier failure must not hide an already-built kernel.
mapfile -d '' built_debs < <(
	find "${armbian_dir}/output/debs" -maxdepth 1 -type f -name '*.deb' -print0 | sort -z
)
if (( ${#built_debs[@]} == 0 )); then
	echo "Armbian did not produce any kernel packages" >&2
	exit 3
fi

for deb in "${built_debs[@]}"; do
	cp -a "${deb}" "${debs_dir}/"
done

kernel_source="${armbian_dir}/cache/sources/linux-kernel-worktree/${ARMBIAN_KERNEL_SERIES}__${ARMBIAN_LINUXFAMILY}__arm64"
if [[ ! -d "${kernel_source}" ]]; then
	echo "Expected patched kernel source is missing: ${kernel_source}" >&2
	exit 3
fi

actual_linux_commit="$(git -C "${kernel_source}" rev-parse HEAD)"
if [[ "${actual_linux_commit}" != "${LINUX_COMMIT}" ]]; then
	echo "Linux commit mismatch: ${actual_linux_commit}" >&2
	exit 3
fi

# The worktree also contains the fixed Armbian patch set.  Some unrelated DTS
# patches carry pre-existing whitespace warnings, so validate only our target.
git -C "${kernel_source}" diff --check -- \
	drivers/usb/typec/tcpm/fusb302.c
grep -Fq "start unattached SRC toggling" \
	"${kernel_source}/drivers/usb/typec/tcpm/fusb302.c"
grep -Fq "extcon,ignore-usb" \
	"${kernel_source}/drivers/phy/rockchip/phy-rockchip-inno-usb2.c"

mapfile -d '' image_debs < <(
	find "${debs_dir}" -maxdepth 1 -type f \
		-name "linux-image-${ARMBIAN_BRANCH}-${ARMBIAN_LINUXFAMILY}_*.deb" -print0 | sort -z
)
mapfile -d '' dtb_debs < <(
	find "${debs_dir}" -maxdepth 1 -type f \
		-name "linux-dtb-${ARMBIAN_BRANCH}-${ARMBIAN_LINUXFAMILY}_*.deb" -print0 | sort -z
)
if (( ${#image_debs[@]} != 1 )) || (( ${#dtb_debs[@]} != 1 )); then
	echo "Expected exactly one image package and one DTB package" >&2
	printf 'Image packages: %s\n' "${image_debs[*]:-none}" >&2
	printf 'DTB packages: %s\n' "${dtb_debs[*]:-none}" >&2
	exit 3
fi

image_root="${work_root}/image-package"
dtb_root="${work_root}/dtb-package"
mkdir -p "${image_root}" "${dtb_root}"
dpkg-deb -x "${image_debs[0]}" "${image_root}"
dpkg-deb -x "${dtb_debs[0]}" "${dtb_root}"

mapfile -d '' module_dirs < <(
	find "${image_root}/lib/modules" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z
)
if (( ${#module_dirs[@]} != 1 )); then
	echo "Expected exactly one module release directory" >&2
	exit 3
fi

kernelrelease="$(basename "${module_dirs[0]}")"
if [[ "${kernelrelease}" != "${EXPECTED_KERNELRELEASE}" ]]; then
	echo "Unexpected kernelrelease: ${kernelrelease}" >&2
	exit 3
fi

compile_header="${kernel_source}/include/generated/compile.h"
kernel_compiler=unavailable
if [[ -f "${compile_header}" ]]; then
	kernel_compiler="$("${script_dir}/read-kernel-compiler.sh" "${compile_header}" || true)"
fi
if [[ -z "${kernel_compiler}" || "${kernel_compiler}" == unavailable ]]; then
	echo "Warning: compiler metadata unavailable; retaining deployable kernel artifacts" >&2
	kernel_compiler=unavailable
fi

image_file="${image_root}/boot/vmlinuz-${kernelrelease}"
config_file="${image_root}/boot/config-${kernelrelease}"
system_map_file="${image_root}/boot/System.map-${kernelrelease}"
dtb_tree="${dtb_root}/boot/dtb-${kernelrelease}"

for output_path in "${image_file}" "${config_file}" "${system_map_file}"; do
	if [[ ! -f "${output_path}" ]]; then
		echo "Expected package file is missing: ${output_path}" >&2
		exit 3
	fi
done
if [[ ! -d "${dtb_tree}" ]]; then
	echo "Expected DTB tree is missing: ${dtb_tree}" >&2
	exit 3
fi

install -m 0644 "${image_file}" "${package_dir}/Image-${kernelrelease}"
install -m 0644 "${config_file}" "${package_dir}/config-${kernelrelease}"
install -m 0644 "${system_map_file}" "${package_dir}/System.map-${kernelrelease}"
install -m 0644 "${patch_path}" "${package_dir}/$(basename "${patch_path}")"

tar --zstd -cf "${package_dir}/modules-${kernelrelease}.tar.zst" \
	-C "${image_root}" "lib/modules/${kernelrelease}"
tar --zstd -cf "${package_dir}/dtbs-${kernelrelease}.tar.zst" \
	-C "${dtb_root}" "boot/dtb-${kernelrelease}"

{
	printf 'repository_commit=%s\n' "${GITHUB_SHA:-$(git -C "${repo_root}" rev-parse HEAD)}"
	printf 'github_run_id=%s\n' "${GITHUB_RUN_ID:-local}"
	printf 'github_run_attempt=%s\n' "${GITHUB_RUN_ATTEMPT:-local}"
	printf 'runner_arch=%s\n' "$(uname -m)"
	printf 'debian_arch=%s\n' "$(dpkg --print-architecture)"
	printf 'armbian_repository=%s\n' "${ARMBIAN_BUILD_REPOSITORY}"
	printf 'armbian_commit=%s\n' "${actual_armbian_commit}"
	printf 'armbian_linuxfamily=%s\n' "${ARMBIAN_LINUXFAMILY}"
	printf 'armbian_linuxconfig=%s\n' "${ARMBIAN_LINUXCONFIG}"
	printf 'armbian_kernel_patch_dir=%s\n' "${ARMBIAN_KERNEL_PATCH_DIR}"
	printf 'linux_repository=%s\n' "${LINUX_REPOSITORY}"
	printf 'linux_commit=%s\n' "${actual_linux_commit}"
	printf 'kernelrelease=%s\n' "${kernelrelease}"
	printf 'config_sha256=%s\n' "${config_sha256}"
	printf 'patch_sha256=%s\n' "${patch_sha256}"
	printf 'kernel_compiler=%s\n' "${kernel_compiler}"
	printf 'source_tree_diff_stat_begin\n'
	git -C "${kernel_source}" diff --stat
	printf 'source_tree_diff_stat_end\n'
} > "${package_dir}/BUILD-MANIFEST.txt"

echo "Built and packaged ${kernelrelease}"
find "${artifacts_dir}" -maxdepth 2 -type f -printf '%P\n' | sort
