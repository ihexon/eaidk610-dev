# OPEN AI LAB EAIDK-610, Rockchip RK3399, 4 GiB RAM and eMMC.
# shellcheck disable=SC2034 # Variables are consumed by the Armbian framework.
BOARD_NAME="EAIDK-610"
BOARD_VENDOR="openailab"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="ihexon"
INTRODUCED="2018"

# Both Linux and U-Boot contain upstream EAIDK-610 device trees.
BOOTCONFIG="eaidk-610-rk3399_defconfig"
BOOT_FDT_FILE="rockchip/rk3399-eaidk-610.dtb"
SRC_EXTLINUX="yes"
# cgroup v2 has no RT bandwidth allocator; allow RTKit-managed audio threads.
SRC_CMDLINE="rootwait console=tty1 console=ttyS2,1500000n8 earlycon loglevel=8 systemd.show_status=yes rt_group_sched=0"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

# This exact upstream U-Boot binman image already booted this board from eMMC.
# Armbian writes u-boot-rockchip.bin at LBA 64; its FIT remains at LBA 16384.
BOOTBRANCH_BOARD="tag:v2026.10-rc3"
BOOTPATCHDIR="eaidk610-v2026.10-rc3"
BL31_BLOB="rk33/rk3399_bl31_v1.36.elf"
BOOT_SCENARIO="binman"

SERIALCON="ttyS2"
CONSOLE_AUTOLOGIN="no"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
HAS_VIDEO_OUTPUT="yes"
PACKAGE_LIST_BOARD="device-tree-compiler alsa-ucm-conf pipewire pipewire-pulse wireplumber rtkit"
EXTRA_BSPDEPS="armbian-firmware, alsa-ucm-conf"
# The BSP supplies board-specific defaults, installed by the image hook below.
ASOUND_STATE=""

# Common architecture defaults are loaded after the board definition.
function post_family_config__eaidk610_boot_logging() {
	MAIN_CMDLINE="${MAIN_CMDLINE// splash/}"
	MAIN_CMDLINE="${MAIN_CMDLINE// plymouth.ignore-serial-consoles/}"
}

# Board assets are copied and hashed by Armbian's native BSP packaging flow.
function post_family_tweaks_bsp__eaidk610_overlay() {
	: "${destination:?BSP destination is not set}"
	install -d -m 0755 "${destination}/boot/overlay-user" "${destination}/usr/lib/firmware/brcm"
	dtc -q -@ -I dts -O dtb \
		-o "${destination}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo" \
		"${destination}/usr/share/eaidk610/rk3399-eaidk-610-typec-fix.dts"
	chmod 0644 "${destination}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo"
	ln -sfn ../BCM4345C0.hcd \
		"${destination}/usr/lib/firmware/brcm/BCM4345C0.openailab,eaidk-610.hcd"
}

function post_customize_image__eaidk610_extlinux_overlay() {
	: "${SDCARD:?image root is not set}"
	local extlinux="${SDCARD}/boot/extlinux/extlinux.conf"
	local kernel_path
	kernel_path=$(awk 'tolower($1) == "kernel" {print $2; exit}' "${extlinux}")
	# Armbian supplies the single entry and root UUID; only add the board overlay.
	sed -i '/^[[:space:]]*fdtoverlays[[:space:]]/Id' "${extlinux}"
	printf '  fdtoverlays %soverlay-user/rk3399-eaidk-610-typec-fix.dtbo\n' \
		"${kernel_path%/*}/" >> "${extlinux}"
}

function post_customize_image__eaidk610_audio_defaults() {
	install -D -m 0644 "${SDCARD}/usr/share/eaidk610/asound.state" \
		"${SDCARD}/var/lib/alsa/asound.state"
}
