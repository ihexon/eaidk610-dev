# OPEN AI LAB EAIDK-610, Rockchip RK3399, 4 GiB RAM and eMMC.
BOARD_NAME="EAIDK-610"
BOARD_VENDOR="openailab"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="ihexon"
INTRODUCED="2018"

# Both Linux and U-Boot contain upstream EAIDK-610 device trees.
BOOTCONFIG="eaidk-610-rk3399_defconfig"
BOOT_FDT_FILE="rockchip/rk3399-eaidk-610.dtb"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"

# This exact upstream U-Boot already booted this board from eMMC.  Armbian's
# rockchip64 writer embeds idbloader at LBA 64 and U-Boot FIT at LBA 16384.
BOOTBRANCH_BOARD="tag:v2026.10-rc3"
BOOTPATCHDIR="eaidk610-v2026.10-rc3"
BL31_BLOB="rk33/rk3399_bl31_v1.36.elf"
BOOT_SCENARIO="tpl-spl-blob"

SERIALCON="ttyS2"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
HAS_VIDEO_OUTPUT="yes"
PACKAGE_LIST_BOARD="device-tree-compiler"
