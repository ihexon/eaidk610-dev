#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/../.." && pwd)
# shellcheck source=image.env
source "${script_dir}/image.env"

[[ $# -eq 0 ]] || { printf 'usage: %s\n' "$0" >&2; exit 2; }

fail() {
	printf 'preflight: %s\n' "$*" >&2
	exit 2
}

board_file="${repo_root}/config/boards/${ARMBIAN_BOARD}.csc"
[[ -f ${board_file} ]] || fail 'EAIDK610 board definition is missing'
# shellcheck disable=SC1090
source "${board_file}"
[[ ${BOOTCONFIG:-} == eaidk-610-rk3399_defconfig ]] || fail 'unexpected U-Boot config'
[[ ${BOOT_FDT_FILE:-} == rockchip/rk3399-eaidk-610.dtb ]] || fail 'unexpected board DTB'
[[ ${BOOTBRANCH_BOARD:-} == "tag:${ARMBIAN_UBOOT_TAG}" ]] || fail 'unexpected U-Boot source'
[[ ${BOOTPATCHDIR:-} == "eaidk610-${ARMBIAN_UBOOT_TAG}" ]] || fail 'unexpected U-Boot patch directory'
[[ ${BL31_BLOB:-} == rk33/rk3399_bl31_v1.36.elf ]] || fail 'unexpected BL31 firmware'
[[ ${BOOT_SCENARIO:-} == binman ]] || fail 'unexpected U-Boot image format'
[[ ${SRC_EXTLINUX:-} == yes ]] || fail 'native extlinux boot is not enabled'

common_inc="${repo_root}/config/sources/families/include/rockchip64_common.inc"
edge_config=$(sed -n '/^[[:space:]]*edge)/,/;;/p' "${common_inc}")
grep -Fq "KERNEL_MAJOR_MINOR=\"${ARMBIAN_KERNEL_SERIES}\"" <<< "${edge_config}"
kernel_config="${repo_root}/config/kernel/linux-rockchip64-edge.config"
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
[[ -s ${repo_root}/${RT5651_PATCH} ]] || fail 'RT5651 patch is missing'
[[ -s ${overlay_source} ]] || fail 'board overlay is missing'
[[ -d ${repo_root}/patch/u-boot/${BOOTPATCHDIR} ]] || fail 'U-Boot patch directory is missing'

for tool in dpkg-deb dtc fdtoverlay fdtget jq sfdisk strings xz; do
	command -v "${tool}" >/dev/null || fail "required validation tool is unavailable: ${tool}"
done
preflight_tmp=$(mktemp -d /tmp/eaidk610-preflight.XXXXXX)
trap 'rm -rf -- "${preflight_tmp}"' EXIT
customizer_root="${preflight_tmp}/root"
mkdir -p "${customizer_root}"
cp -a "${repo_root}/config/optional/boards/eaidk610/_packages/bsp-cli/." "${customizer_root}/"
destination=${customizer_root} post_family_tweaks_bsp__eaidk610_overlay
[[ -x ${customizer_root}/usr/bin/eaidk610-typec ]] || fail 'Type-C userspace tool is missing or not executable'
"${customizer_root}/usr/bin/eaidk610-typec" --help >/dev/null
[[ $(readlink "${customizer_root}/usr/lib/firmware/brcm/BCM4345C0.openailab,eaidk-610.hcd") == ../BCM4345C0.hcd ]]
extlinux="${customizer_root}/boot/extlinux/extlinux.conf"
install -D -m 0644 /dev/null "${extlinux}"
printf 'label Armbian\n  kernel /boot/Image\n  initrd /boot/uInitrd\n  fdt /boot/dtb/%s\n' \
	"${BOOT_FDT_FILE}" > "${extlinux}"
SDCARD=${customizer_root} post_customize_image__eaidk610_extlinux_overlay
SDCARD=${customizer_root} post_customize_image__eaidk610_audio_defaults
cmp "${customizer_root}/usr/share/eaidk610/asound.state" "${customizer_root}/var/lib/alsa/asound.state"
grep -Fqx "  fdtoverlays /boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo" "${extlinux}"
[[ -s ${customizer_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo ]]
# RT5651 DAPM widget names are case-sensitive; MICBIAS1 prevents card registration.
audio_routing=$(fdtget -t s \
	"${customizer_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo" \
	/fragment@8/__overlay__ simple-audio-card,routing)
[[ ${audio_routing} == *"Mic Jack micbias1"* ]] || fail 'incorrect RT5651 micbias route'
for route in 'IN3P Mic Jack' 'Internal Mic micbias1' 'IN2P Internal Mic' 'IN2N Internal Mic'; do
	[[ ${audio_routing} == *"${route}"* ]] || fail "missing microphone route: ${route}"
done
fdtget "${customizer_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo" \
	/fragment@11/__overlay__ realtek,in2-differential >/dev/null

# Exercise the board hook against the framework's actual common defaults.
eval "$(sed -n '/^declare -g MAIN_CMDLINE=/p' "${repo_root}/config/sources/common.conf")"
post_family_config__eaidk610_boot_logging
cmdline="${SRC_CMDLINE} ${MAIN_CMDLINE}"
for setting in rootwait console=tty1 console=ttyS2,1500000n8 earlycon loglevel=8 systemd.show_status=yes; do
	[[ " ${cmdline} " == *" ${setting} "* ]] || fail "missing ${setting}"
done
for setting in quiet splash plymouth.ignore-serial-consoles; do
	[[ " ${cmdline} " != *" ${setting} "* ]] || fail "unwanted ${setting}"
done
# Partitioning supplies root= after customization; a repeated customization must preserve it.
printf '  append root=UUID=preflight-root %s\n' "${cmdline}" >> "${extlinux}"
cp "${extlinux}" "${preflight_tmp}/configured-extlinux.conf"
SDCARD=${customizer_root} post_customize_image__eaidk610_extlinux_overlay
# Compare directives without depending on whether append or fdtoverlays comes last.
diff <(sort "${preflight_tmp}/configured-extlinux.conf") <(sort "${extlinux}") || \
	fail 'image customization is not idempotent'

printf 'EAIDK610_IMAGE_PREFLIGHT_OK\n'
