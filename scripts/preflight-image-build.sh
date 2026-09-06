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

[[ ${ARMBIAN_BUILD_COMMIT} =~ ^[0-9a-f]{40}$ ]] || fail 'invalid Armbian commit'
[[ ${ARMBIAN_UBOOT_COMMIT} =~ ^[0-9a-f]{40}$ ]] || fail 'invalid U-Boot commit'
[[ ${ARMBIAN_KERNEL_SERIES} == 7.2 ]] || fail 'unexpected edge series'

actual_submodule=$(git -C "${repo_root}/armbian" rev-parse HEAD)
[[ ${actual_submodule} == "${ARMBIAN_BUILD_COMMIT}" ]] || fail 'Armbian submodule is not pinned to image.env'
[[ -z $(git -C "${repo_root}/armbian" status --short) ]] || fail 'Armbian submodule is dirty'
grep -Fq 'url = https://github.com/armbian/build.git' "${repo_root}/.gitmodules"

board_file="${repo_root}/userpatches/config/boards/${ARMBIAN_BOARD}.csc"
[[ -f ${board_file} ]] || fail 'EAIDK610 board definition is missing'
grep -Fqx 'BOOTCONFIG="eaidk-610-rk3399_defconfig"' "${board_file}"
grep -Fqx 'BOOT_FDT_FILE="rockchip/rk3399-eaidk-610.dtb"' "${board_file}"
grep -Fqx "BOOTBRANCH_BOARD=\"tag:${ARMBIAN_UBOOT_TAG}\"" "${board_file}"
grep -Fqx 'BL31_BLOB="rk33/rk3399_bl31_v1.36.elf"' "${board_file}"
grep -Fqx 'BOOT_SCENARIO="binman"' "${board_file}"

common_inc="${repo_root}/armbian/config/sources/families/include/rockchip64_common.inc"
edge_config=$(sed -n '/^[[:space:]]*edge)/,/;;/p' "${common_inc}")
grep -Fq "KERNEL_MAJOR_MINOR=\"${ARMBIAN_KERNEL_SERIES}\"" <<< "${edge_config}"
grep -Fq 'UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"' \
	"${common_inc}"
grep -Fq 'dd if=$1/u-boot-rockchip.bin of=$2 bs=32k seek=1 conv=notrunc status=none' \
	"${common_inc}"
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
printf '%s  %s\n' "${KERNEL_PATCH_SHA256}" "${patch_path}" | sha256sum --check --status
printf '%s  %s\n' "${TYPEC_OVERLAY_SOURCE_SHA256}" "${overlay_source}" | sha256sum --check --status
git apply --numstat "${patch_path}" | grep -Fq $'drivers/usb/typec/tcpm/fusb302.c'
[[ -d ${repo_root}/userpatches/u-boot/eaidk610-v2026.10-rc3 ]]

for tool in dtc fdtoverlay fdtget jq sfdisk strings xz; do
	command -v "${tool}" >/dev/null || fail "required validation tool is unavailable: ${tool}"
done
overlay_check=$(mktemp /tmp/eaidk610-overlay.XXXXXX.dtbo)
dtc -q -@ -I dts -O dtb -o "${overlay_check}" "${overlay_source}"
dtc -q -I dtb -O dts -o /dev/null "${overlay_check}"

customizer_root=$(mktemp -d /tmp/eaidk610-customizer.XXXXXX)
install -D -m 0644 "${overlay_source}" \
	"${customizer_root}/tmp/overlay/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dts"
install -D -m 0644 "${overlay_check}" \
	"${customizer_root}/tmp/overlay/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo"
install -D -m 0644 /dev/null "${customizer_root}/boot/armbianEnv.txt"
printf 'fdtfile=rockchip/rk3399-eaidk-610.dtb\nuser_overlays=obsolete\n' \
	> "${customizer_root}/boot/armbianEnv.txt"
EAIDK610_ROOT_PREFIX=${customizer_root} "${repo_root}/userpatches/customize-image.sh" \
	"${ARMBIAN_RELEASE}" rockchip64 "${ARMBIAN_BOARD}" no arm64
grep -Fqx "user_overlays=${TYPEC_OVERLAY_NAME}" \
	"${customizer_root}/boot/armbianEnv.txt"
[[ -s ${customizer_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo ]]

bash -n "${repo_root}/scripts/build-image.sh" \
	"${repo_root}/scripts/preflight-image-build.sh" \
	"${repo_root}/scripts/validate-image.sh" \
	"${repo_root}/userpatches/customize-image.sh"

printf 'EAIDK610_IMAGE_PREFLIGHT_OK\n'
