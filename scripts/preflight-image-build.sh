#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
# shellcheck source=../config/image.env
source "${repo_root}/config/image.env"

[[ $# -eq 0 ]] || { printf 'usage: %s\n' "$0" >&2; exit 2; }

fail() {
	printf 'preflight: %s\n' "$*" >&2
	exit 2
}

board_file="${repo_root}/userpatches/config/boards/${ARMBIAN_BOARD}.csc"
[[ -f ${board_file} ]] || fail 'EAIDK610 board definition is missing'
# shellcheck disable=SC1090
source "${board_file}"
[[ ${BOOTCONFIG:-} == eaidk-610-rk3399_defconfig ]] || fail 'unexpected U-Boot config'
[[ ${BOOT_FDT_FILE:-} == rockchip/rk3399-eaidk-610.dtb ]] || fail 'unexpected board DTB'
[[ ${BOOTBRANCH_BOARD:-} == "tag:${ARMBIAN_UBOOT_TAG}" ]] || fail 'unexpected U-Boot source'
[[ ${BOOTPATCHDIR:-} == "eaidk610-${ARMBIAN_UBOOT_TAG}" ]] || fail 'unexpected U-Boot patch directory'
[[ ${BL31_BLOB:-} == rk33/rk3399_bl31_v1.36.elf ]] || fail 'unexpected BL31 firmware'
[[ ${BOOT_SCENARIO:-} == binman ]] || fail 'unexpected U-Boot image format'

common_inc="${repo_root}/armbian/config/sources/families/include/rockchip64_common.inc"
edge_config=$(sed -n '/^[[:space:]]*edge)/,/;;/p' "${common_inc}")
grep -Fq "KERNEL_MAJOR_MINOR=\"${ARMBIAN_KERNEL_SERIES}\"" <<< "${edge_config}"
kernel_config="${repo_root}/armbian/config/kernel/linux-rockchip64-edge.config"
for symbol in \
	CONFIG_TYPEC_TCPM=y \
	CONFIG_TYPEC_FUSB302=y \
	CONFIG_TYPEC_EXTCON=m \
	CONFIG_SND_SOC_RT5651=m \
	CONFIG_SND_SOC_SIMPLE_AMPLIFIER=m; do
	grep -Fqx "${symbol}" "${kernel_config}" || fail "missing ${symbol}"
done

patch_path="${repo_root}/${KERNEL_PATCH}"
overlay_source="${repo_root}/${TYPEC_OVERLAY_SOURCE}"
[[ -s ${patch_path} ]] || fail 'kernel patch is missing'
[[ -s ${overlay_source} ]] || fail 'board overlay is missing'
[[ -d ${repo_root}/userpatches/u-boot/${BOOTPATCHDIR} ]] || fail 'U-Boot patch directory is missing'

for tool in dpkg-deb dtc fdtoverlay fdtget jq sfdisk strings xz; do
	command -v "${tool}" >/dev/null || fail "required validation tool is unavailable: ${tool}"
done
preflight_tmp=$(mktemp -d /tmp/eaidk610-preflight.XXXXXX)
trap 'rm -rf -- "${preflight_tmp}"' EXIT
overlay_package="${repo_root}/userpatches/overlay/eaidk610-board-overlays.deb"
"${repo_root}/scripts/build-board-overlay-package.sh" "${overlay_package}" >/dev/null
[[ $(dpkg-deb --field "${overlay_package}" Package) == eaidk610-board-overlays ]]

customizer_root="${preflight_tmp}/root"
install -D -m 0644 "${overlay_package}" \
	"${customizer_root}/tmp/overlay/eaidk610-board-overlays.deb"
install -D -m 0644 /dev/null "${customizer_root}/boot/armbianEnv.txt"
printf 'fdtfile=rockchip/rk3399-eaidk-610.dtb\nuser_overlays=obsolete\n' \
	> "${customizer_root}/boot/armbianEnv.txt"
EAIDK610_ROOT_PREFIX=${customizer_root} "${repo_root}/userpatches/customize-image.sh" \
	"${ARMBIAN_RELEASE}" rockchip64 "${ARMBIAN_BOARD}" no arm64
configured_overlays=$(sed -n 's/^user_overlays=//p' \
	"${customizer_root}/boot/armbianEnv.txt")
[[ " ${configured_overlays} " == *" ${TYPEC_OVERLAY_NAME} "* ]]
[[ -s ${customizer_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo ]]

printf 'EAIDK610_IMAGE_PREFLIGHT_OK\n'
