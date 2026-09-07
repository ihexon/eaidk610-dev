#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
	printf 'image validation: %s\n' "$*" >&2
	exit 4
}

[[ $# -eq 1 ]] || { printf 'usage: %s IMAGE\n' "$0" >&2; exit 2; }
image_path=$1
[[ -f ${image_path} ]] || fail "image does not exist: ${image_path}"

validate_tmp=$(mktemp -d /tmp/eaidk610-validate.XXXXXX)
mount_dir="${validate_tmp}/root"
loop_device=
cleanup() {
	if mountpoint -q "${mount_dir}"; then sudo umount "${mount_dir}"; fi
	if [[ -n ${loop_device} ]]; then sudo losetup --detach "${loop_device}" 2>/dev/null || true; fi
	rm -rf -- "${validate_tmp}"
}
trap cleanup EXIT

first16m="${validate_tmp}/first16m.bin"
dd if="${image_path}" of="${first16m}" bs=1M count=16 status=none
first16m_strings="${validate_tmp}/first16m-strings.txt"
strings "${first16m}" > "${first16m_strings}"
grep -Fq 'U-Boot 2026.10-rc3' "${first16m_strings}" || \
	fail 'expected U-Boot version was not found in the first 16 MiB'

partition_start=$(sfdisk --json "${image_path}" | jq -r '.partitiontable.partitions[0].start')
[[ ${partition_start} =~ ^[0-9]+$ ]] || fail 'first partition start is not numeric'
(( partition_start >= 32768 )) || fail 'first partition overlaps the bootloader area'

loop_device=$(sudo losetup --find --show --partscan --read-only "${image_path}")
mkdir "${mount_dir}"

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
kernel_image=$(find "${mount_dir}/boot" -maxdepth 1 -type f \
	-name 'vmlinuz-*edge-rockchip64' -print -quit)
module_dir=$(find "${mount_dir}/lib/modules" -mindepth 1 -maxdepth 1 -type d \
	-name '*edge-rockchip64' -print -quit)
[[ -s ${kernel_image} ]] || fail 'edge rockchip64 kernel image is missing'
[[ -d ${module_dir} ]] || fail 'edge rockchip64 module directory is missing'

dtb_path=$(find "${mount_dir}/boot" -type f \
	-path '*/rockchip/rk3399-eaidk-610.dtb' -print -quit)
[[ -s ${dtb_path} ]] || fail 'EAIDK610 base DTB is missing'
merged_dtb="${validate_tmp}/merged.dtb"
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
tcphy0_path=$(fdtget -t s "${merged_dtb}" /__symbols__ tcphy0)
tcphy0_extcon=$(fdtget -t x "${merged_dtb}" "${tcphy0_path}" extcon)
bridge_phandle=$(fdtget -t x "${merged_dtb}" /typec-extcon phandle)
[[ ${tcphy0_extcon} == "${bridge_phandle}" ]] || \
	fail 'overlay did not connect the RK3399 Type-C PHY to the extcon bridge'

read -r hp_detect_gpio hp_detect_pin hp_detect_flags < <(
	fdtget -t i "${merged_dtb}" /rt5651-sound simple-audio-card,hp-det-gpios
)
gpio4_path=$(fdtget -t s "${merged_dtb}" /__symbols__ gpio4)
gpio4_phandle=$(fdtget -t i "${merged_dtb}" "${gpio4_path}" phandle)
[[ ${hp_detect_gpio} == "${gpio4_phandle}" && ${hp_detect_pin} == 28 && ${hp_detect_flags} == 0 ]] || \
	fail 'overlay did not describe active-high GPIO4_D4 headphone detection'
speaker_amp_phandle=$(fdtget -t x "${merged_dtb}" /audio-amplifier phandle)
sound_aux_phandle=$(fdtget -t x "${merged_dtb}" /rt5651-sound simple-audio-card,aux-devs)
[[ ${sound_aux_phandle} == "${speaker_amp_phandle}" ]] || \
	fail 'overlay did not attach the speaker amplifier to simple-audio-card'
[[ $(fdtget -t s "${merged_dtb}" /audio-amplifier compatible) == simple-audio-amplifier ]] || \
	fail 'overlay did not create a supported speaker amplifier'
read -r speaker_enable_gpio speaker_enable_pin speaker_enable_flags < <(
	fdtget -t i "${merged_dtb}" /audio-amplifier enable-gpios
)
gpio0_path=$(fdtget -t s "${merged_dtb}" /__symbols__ gpio0)
gpio0_phandle=$(fdtget -t i "${merged_dtb}" "${gpio0_path}" phandle)
[[ ${speaker_enable_gpio} == "${gpio0_phandle}" && ${speaker_enable_pin} == 11 && ${speaker_enable_flags} == 0 ]] || \
	fail 'overlay did not describe active-high GPIO0_B3 speaker enable'
speaker_supply=$(fdtget -t x "${merged_dtb}" /audio-amplifier VCC-supply)
vcc5v0_sys_path=$(fdtget -t s "${merged_dtb}" /__symbols__ vcc5v0_sys)
vcc5v0_sys_phandle=$(fdtget -t x "${merged_dtb}" "${vcc5v0_sys_path}" phandle)
[[ ${speaker_supply} == "${vcc5v0_sys_phandle}" ]] || \
	fail 'overlay speaker amplifier is not supplied by VCC5V0_SYS'

cleanup
trap - EXIT
printf 'EAIDK610_IMAGE_CONTENTS_OK\n'
