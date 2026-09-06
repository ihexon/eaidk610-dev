#!/usr/bin/env bash

set -Eeuo pipefail

[[ $# -eq 2 ]] || { printf 'usage: %s IMAGE BUILD_LOG\n' "$0" >&2; exit 2; }
image_path=$1
build_log=$2
[[ -f ${image_path} && -f ${build_log} ]]

grep -Fq '0001-usb-typec-fusb302-detect-unattached-source-connectio.patch' "${build_log}"
grep -Fq 'Building image' "${build_log}"

first16m=$(mktemp /tmp/eaidk610-first16m.XXXXXX.bin)
dd if="${image_path}" of="${first16m}" bs=1M count=16 status=none
first16m_strings=$(mktemp /tmp/eaidk610-first16m-strings.XXXXXX.txt)
strings "${first16m}" > "${first16m_strings}"
grep -Fq 'U-Boot 2026.10-rc3' "${first16m_strings}"

partition_start=$(sfdisk --json "${image_path}" | jq -r '.partitiontable.partitions[0].start')
[[ ${partition_start} =~ ^[0-9]+$ ]]
(( partition_start >= 32768 ))

loop_device=$(sudo losetup --find --show --partscan --read-only "${image_path}")
mount_dir=$(mktemp -d /tmp/eaidk610-image.XXXXXX)
cleanup() {
	if mountpoint -q "${mount_dir}"; then sudo umount "${mount_dir}"; fi
	sudo losetup --detach "${loop_device}" 2>/dev/null || true
}
trap cleanup EXIT

root_partition=$(lsblk -nrpo NAME,TYPE "${loop_device}" | \
	awk '$2 == "part" && first == "" {first=$1} END {print first}')
[[ -b ${root_partition} ]]
sudo mount -o ro "${root_partition}" "${mount_dir}"

grep -Fqx 'BOARD=eaidk610' "${mount_dir}/etc/armbian-release"
grep -Fqx 'fdtfile=rockchip/rk3399-eaidk-610.dtb' "${mount_dir}/boot/armbianEnv.txt"
grep -Fqx 'user_overlays=rk3399-eaidk-610-typec-fix' "${mount_dir}/boot/armbianEnv.txt"
test -s "${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo"
test -s "${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dts"
kernel_image=$(find "${mount_dir}/boot" -maxdepth 1 -type f \
	-name 'vmlinuz-*edge-rockchip64' -print -quit)
module_dir=$(find "${mount_dir}/lib/modules" -mindepth 1 -maxdepth 1 -type d \
	-name '*edge-rockchip64' -print -quit)
[[ -s ${kernel_image} ]]
[[ -d ${module_dir} ]]

dtb_path=$(find "${mount_dir}/boot" -type f \
	-path '*/rockchip/rk3399-eaidk-610.dtb' -print -quit)
[[ -s ${dtb_path} ]]
merged_dtb=$(mktemp /tmp/eaidk610-merged.XXXXXX.dtb)
fdtoverlay -i "${dtb_path}" -o "${merged_dtb}" \
	"${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo"
[[ $(fdtget -t s "${merged_dtb}" /regulator-vcc5v0-typec status) == disabled ]]
[[ $(fdtget -t s "${merged_dtb}" /regulator-vcc5v0-typec-managed status) == okay ]]
connector=/i2c@ff3d0000/typec-portc@22/connector
[[ $(fdtget -t s "${merged_dtb}" "${connector}" try-power-role) == source ]]
[[ $(fdtget -t s "${merged_dtb}" "${connector}" typec-power-opmode) == 1.5A ]]

cleanup
trap - EXIT
printf 'EAIDK610_IMAGE_CONTENTS_OK\n'
