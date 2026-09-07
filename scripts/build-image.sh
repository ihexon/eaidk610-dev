#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
# shellcheck source=../config/image.env
source "${repo_root}/config/image.env"

[[ $(uname -m) == aarch64 ]] || { printf 'ARM64 runner required\n' >&2; exit 2; }
[[ ${GITHUB_ACTIONS:-} == true ]] || { printf 'Full image builds are restricted to GitHub Actions\n' >&2; exit 2; }

"${script_dir}/preflight-image-build.sh"
read -r edge_linux_commit _ < <(git ls-remote \
	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
	"refs/heads/linux-${ARMBIAN_KERNEL_SERIES}.y")
[[ ${edge_linux_commit} =~ ^[0-9a-f]{40}$ ]]

armbian_dir="${repo_root}/armbian"
overlay_source="${repo_root}/${TYPEC_OVERLAY_SOURCE}"
overlay_binary="${overlay_source%.dts}.dtbo"
dtc -q -@ -I dts -O dtb -o "${overlay_binary}" "${overlay_source}"
install -d "${armbian_dir}/userpatches"
cp -a "${repo_root}/userpatches/." "${armbian_dir}/userpatches/"

install -d "${repo_root}/artifacts/release"
build_log="${repo_root}/artifacts/build.log"

(
	cd "${armbian_dir}"
	./compile.sh build \
		BOARD="${ARMBIAN_BOARD}" \
		BRANCH="${ARMBIAN_BRANCH}" \
		RELEASE="${ARMBIAN_RELEASE}" \
		BUILD_MINIMAL="${ARMBIAN_BUILD_MINIMAL}" \
		BUILD_DESKTOP=no \
		KERNEL_CONFIGURE=no \
		KERNELBRANCH="commit:${edge_linux_commit}" \
		EXTRAWIFI=no \
		COMPRESS_OUTPUTIMAGE=img \
		SHARE_LOG=no
) 2>&1 | tee "${build_log}"

image_path=$(find "${armbian_dir}/output/images" -maxdepth 1 -type f -name '*.img' -print -quit)
[[ -n ${image_path} ]] || { printf 'Armbian image was not produced\n' >&2; exit 3; }

"${script_dir}/validate-image.sh" "${image_path}"

release_dir="${repo_root}/artifacts/release"
compressed_image="${release_dir}/eaidk610-armbian-edge.img.xz"
compressed_tmp="${compressed_image}.tmp"
xz -T0 -6 --stdout "${image_path}" > "${compressed_tmp}"
mv "${compressed_tmp}" "${compressed_image}"

{
	printf 'repository_commit=%s\n' "${GITHUB_SHA:-$(git -C "${repo_root}" rev-parse HEAD)}"
	printf 'armbian_build_commit=%s\n' "$(git -C "${armbian_dir}" rev-parse HEAD)"
	printf 'linux_edge_commit=%s\n' "${edge_linux_commit}"
	printf 'u_boot_tag=%s\n' "${ARMBIAN_UBOOT_TAG}"
	printf 'board=%s\nbranch=%s\nrelease=%s\n' "${ARMBIAN_BOARD}" "${ARMBIAN_BRANCH}" "${ARMBIAN_RELEASE}"
	printf 'kernel_patch_sha256=%s\n' \
		"$(sha256sum "${repo_root}/${KERNEL_PATCH}" | awk '{print $1}')"
	printf 'typec_overlay_source_sha256=%s\n' \
		"$(sha256sum "${repo_root}/${TYPEC_OVERLAY_SOURCE}" | awk '{print $1}')"
	printf 'image=%s\n' "$(basename "${compressed_image}")"
} > "${release_dir}/BUILD-MANIFEST.txt"

{
	printf '# EAIDK610 Armbian Edge image\n\n'
	printf 'Directly bootable Armbian Trixie Minimal image for OPEN AI LAB EAIDK-610.\n\n'
	printf -- '- Linux: Armbian edge %s with the EAIDK610 FUSB302 patch\n' "${ARMBIAN_KERNEL_SERIES}"
	printf -- '- U-Boot: upstream %s binman image at LBA 64; U-Boot FIT at LBA 16384\n' "${ARMBIAN_UBOOT_TAG}"
	printf -- '- Device tree: rockchip/rk3399-eaidk-610.dtb\n'
	printf -- '- Board overlay: Type-C extcon/role switching, USB3 PHY orientation, headphone detection, and speaker amplifier GPIO\n\n'
	printf 'Verify the download with `sha256sum -c SHA256SUMS`, decompress it, then write the entire image to eMMC or removable media. This is a pre-release until the complete hardware regression matrix is finished.\n'
} > "${release_dir}/RELEASE-NOTES.md"

(
	cd "${release_dir}"
	sha256sum -- eaidk610-armbian-edge.img.xz BUILD-MANIFEST.txt > SHA256SUMS
)

printf 'EAIDK610_ARMBIAN_IMAGE_OK\n'
