#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/../.." && pwd)
# shellcheck source=image.env
source "${script_dir}/image.env"

[[ $(uname -m) == aarch64 ]] || { printf 'ARM64 runner required\n' >&2; exit 2; }
[[ ${GITHUB_ACTIONS:-} == true ]] || { printf 'Full image builds are restricted to GitHub Actions\n' >&2; exit 2; }

"${script_dir}/preflight-image-build.sh"
read -r edge_linux_commit _ < <(git ls-remote \
	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
	"refs/heads/linux-${ARMBIAN_KERNEL_SERIES}.y")
[[ ${edge_linux_commit} =~ ^[0-9a-f]{40}$ ]]

install -d "${repo_root}/artifacts/release"
build_log="${repo_root}/artifacts/build.log"

(
	cd "${repo_root}"
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

image_path=$(find "${repo_root}/output/images" -maxdepth 1 -type f -name '*.img' -print -quit)
[[ -n ${image_path} ]] || { printf 'Armbian image was not produced\n' >&2; exit 3; }

"${script_dir}/validate-image.sh" "${image_path}"

release_dir="${repo_root}/artifacts/release"
compressed_image="${release_dir}/eaidk610-armbian-edge.img.xz"
bsp_package="${release_dir}/armbian-bsp-eaidk610-edge.deb"

copy_package() {
	local package_name=$1
	local output_name=$2
	local candidate

	while IFS= read -r -d '' candidate; do
		if [[ $(dpkg-deb --field "${candidate}" Package) == "${package_name}" ]]; then
			cp "${candidate}" "${release_dir}/${output_name}"
			return 0
		fi
	done < <(find "${repo_root}/output/debs" -type f -name '*.deb' -print0)

	printf 'Armbian package was not produced: %s\n' "${package_name}" >&2
	return 3
}

copy_package linux-image-edge-rockchip64 linux-image-eaidk610-edge.deb
copy_package linux-dtb-edge-rockchip64 linux-dtb-eaidk610-edge.deb
copy_package linux-headers-edge-rockchip64 linux-headers-eaidk610-edge.deb
copy_package linux-libc-dev-edge-rockchip64 linux-libc-dev-eaidk610-edge.deb
copy_package armbian-bsp-cli-eaidk610-edge armbian-bsp-eaidk610-edge.deb

compressed_tmp="${compressed_image}.tmp"
xz -T0 -6 --stdout "${image_path}" > "${compressed_tmp}"
mv "${compressed_tmp}" "${compressed_image}"

{
	printf 'repository_commit=%s\n' "${GITHUB_SHA:-$(git -C "${repo_root}" rev-parse HEAD)}"
	printf 'armbian_upstream_base=%s\n' 66dbc7af2a77d52ccd3fe2156a55687622848ea3
	printf 'linux_edge_commit=%s\n' "${edge_linux_commit}"
	printf 'u_boot_tag=%s\n' "${ARMBIAN_UBOOT_TAG}"
	printf 'board=%s\nbranch=%s\nrelease=%s\n' "${ARMBIAN_BOARD}" "${ARMBIAN_BRANCH}" "${ARMBIAN_RELEASE}"
	printf 'boot_method=extlinux\n'
	printf 'kernel_patch_sha256=%s\n' \
		"$(sha256sum "${repo_root}/${KERNEL_PATCH}" | awk '{print $1}')"
	printf 'rt5651_patch_sha256=%s\n' \
		"$(sha256sum "${repo_root}/${RT5651_PATCH}" | awk '{print $1}')"
	printf 'typec_overlay_source_sha256=%s\n' \
		"$(sha256sum "${repo_root}/${TYPEC_OVERLAY_SOURCE}" | awk '{print $1}')"
	printf 'board_package_sha256=%s\n' "$(sha256sum "${bsp_package}" | awk '{print $1}')"
	printf 'kernel_package_version=%s\n' \
		"$(dpkg-deb --field "${release_dir}/linux-image-eaidk610-edge.deb" Version)"
	printf 'image=%s\n' "$(basename "${compressed_image}")"
} > "${release_dir}/BUILD-MANIFEST.txt"

{
	printf '# EAIDK610 Armbian Edge image\n\n'
	printf 'Directly bootable Armbian Trixie Minimal image for OPEN AI LAB EAIDK-610.\n\n'
	printf -- '- Linux: Armbian edge %s with the EAIDK610 FUSB302 patch\n' "${ARMBIAN_KERNEL_SERIES}"
	printf -- '- Audio: corrected RT5651 routes and MCLK, 40 dB onboard microphone boost, UCM input/output selection, and independent speaker mute; PipeWire/WirePlumber included\n'
	printf -- '- U-Boot: upstream %s binman image at LBA 64; U-Boot FIT at LBA 16384\n' "${ARMBIAN_UBOOT_TAG}"
	printf -- '- Device tree: rockchip/rk3399-eaidk-610.dtb\n'
	printf -- '- Type-C: Sink-preferred dual role; fixed 5V PD only (Source 1.8A, Sink 100mA interface budget); non-PD advertisement remains 1.5A\n'
	printf -- '- Power qualification: independent 12V board supply required; one 5V PD contract and partner-initiated power-role swap tested; sustained 1.8A output and broader interoperability remain unqualified\n'
	printf -- '- Kernel packages: image, DTB, headers, and libc development files\n'
	printf -- '- Board package: armbian-bsp-eaidk610-edge.deb, includes the default board overlay and eaidk610-typec userspace control tool\n'
	printf -- '- Boot: native extlinux, one entry, serial and display kernel logs\n'
	printf -- '- Boot fixes: serial stdout-path and EAIDK610 Bluetooth firmware alias\n'
	printf -- '- Board overlay: Type-C extcon/role switching, USB3 PHY orientation, headphone detection, and speaker amplifier GPIO\n\n'
	printf 'Verify the download with `sha256sum -c SHA256SUMS`, decompress it, then write the entire image to eMMC or removable media. This is a pre-release until the complete hardware regression matrix is finished.\n'
} > "${release_dir}/RELEASE-NOTES.md"

(
	cd "${release_dir}"
	sha256sum -- \
		eaidk610-armbian-edge.img.xz \
		linux-image-eaidk610-edge.deb \
		linux-dtb-eaidk610-edge.deb \
		linux-headers-eaidk610-edge.deb \
		linux-libc-dev-eaidk610-edge.deb \
		armbian-bsp-eaidk610-edge.deb \
		BUILD-MANIFEST.txt > SHA256SUMS
)

printf 'EAIDK610_ARMBIAN_IMAGE_OK\n'
