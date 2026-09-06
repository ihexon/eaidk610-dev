#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
	printf 'image validation: %s\n' "$*" >&2
	exit 4
}

[[ $# -eq 1 ]] || { printf 'usage: %s IMAGE\n' "$0" >&2; exit 2; }
image_path=$1
[[ -f ${image_path} ]] || fail "image does not exist: ${image_path}"

first16m=$(mktemp /tmp/eaidk610-first16m.XXXXXX.bin)
dd if="${image_path}" of="${first16m}" bs=1M count=16 status=none
first16m_strings=$(mktemp /tmp/eaidk610-first16m-strings.XXXXXX.txt)
strings "${first16m}" > "${first16m_strings}"
grep -Fq 'U-Boot 2026.10-rc3' "${first16m_strings}" || \
	fail 'expected U-Boot version was not found in the first 16 MiB'

partition_start=$(sfdisk --json "${image_path}" | jq -r '.partitiontable.partitions[0].start')
[[ ${partition_start} =~ ^[0-9]+$ ]] || fail 'first partition start is not numeric'
(( partition_start >= 32768 )) || fail 'first partition overlaps the bootloader area'

loop_device=$(sudo losetup --find --show --partscan --read-only "${image_path}")
mount_dir=$(mktemp -d /tmp/eaidk610-image.XXXXXX)
cleanup() {
	if mountpoint -q "${mount_dir}"; then sudo umount "${mount_dir}"; fi
	sudo losetup --detach "${loop_device}" 2>/dev/null || true
}
trap cleanup EXIT

root_partition=$(lsblk -nrpo NAME,TYPE "${loop_device}" | \
	awk '$2 == "part" && first == "" {first=$1} END {print first}')
[[ -b ${root_partition} ]] || fail 'image has no mountable root partition'
sudo mount -o ro "${root_partition}" "${mount_dir}"

grep -Fqx 'BOARD=eaidk610' "${mount_dir}/etc/armbian-release" || \
	fail 'armbian-release does not identify the EAIDK610 board'
grep -Fqx 'fdtfile=rockchip/rk3399-eaidk-610.dtb' "${mount_dir}/boot/armbianEnv.txt" || \
	fail 'armbianEnv.txt does not select the EAIDK610 DTB'
grep -Fqx 'user_overlays=rk3399-eaidk-610-typec-fix' "${mount_dir}/boot/armbianEnv.txt" || \
	fail 'armbianEnv.txt does not enable the Type-C overlay'
test -s "${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo" || \
	fail 'compiled Type-C overlay is missing from the image'
test -s "${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dts" || \
	fail 'Type-C overlay source is missing from the image'
kernel_image=$(find "${mount_dir}/boot" -maxdepth 1 -type f \
	-name 'vmlinuz-*edge-rockchip64' -print -quit)
module_dir=$(find "${mount_dir}/lib/modules" -mindepth 1 -maxdepth 1 -type d \
	-name '*edge-rockchip64' -print -quit)
[[ -s ${kernel_image} ]] || fail 'edge rockchip64 kernel image is missing'
[[ -d ${module_dir} ]] || fail 'edge rockchip64 module directory is missing'

dtb_path=$(find "${mount_dir}/boot" -type f \
	-path '*/rockchip/rk3399-eaidk-610.dtb' -print -quit)
[[ -s ${dtb_path} ]] || fail 'EAIDK610 base DTB is missing'
merged_dtb=$(mktemp /tmp/eaidk610-merged.XXXXXX.dtb)
fdtoverlay -i "${dtb_path}" -o "${merged_dtb}" \
	"${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo" || \
	fail 'Type-C overlay cannot be applied to the final EAIDK610 DTB'
[[ $(fdtget -t s "${merged_dtb}" /regulator-vcc5v0-typec status) == disabled ]] || \
	fail 'overlay did not disable the always-on Type-C regulator'
[[ $(fdtget -t s "${merged_dtb}" /regulator-vcc5v0-typec-managed status) == okay ]] || \
	fail 'overlay did not enable the managed Type-C regulator'
connector=/i2c@ff3d0000/typec-portc@22/connector
[[ $(fdtget -t s "${merged_dtb}" "${connector}" try-power-role) == source ]] || \
	fail 'overlay did not set the connector Source preference'
[[ $(fdtget -t s "${merged_dtb}" "${connector}" typec-power-opmode) == 1.5A ]] || \
	fail 'overlay did not set the connector current advertisement to 1.5A'

cleanup
trap - EXIT
printf 'EAIDK610_IMAGE_CONTENTS_OK\n'
