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
extlinux="${mount_dir}/boot/extlinux/extlinux.conf"
[[ -s ${extlinux} ]] || fail 'extlinux.conf is missing'
for directive in kernel initrd fdt; do
	boot_path=$(awk -v key="${directive}" 'tolower($1) == key {print $2; exit}' "${extlinux}")
	[[ ${boot_path} == /* && -s ${mount_dir}${boot_path} ]] || \
		fail "extlinux ${directive} does not reference an installed file"
done
dtb_path="${mount_dir}${boot_path}"
[[ ${boot_path} == /boot/dtb/rockchip/rk3399-eaidk-610.dtb ]] || \
	fail 'extlinux does not select the EAIDK610 DTB'
grep -Eiq '^[[:space:]]*fdtoverlays[[:space:]]+/boot/overlay-user/rk3399-eaidk-610-typec-fix\.dtbo([[:space:]]|$)' "${extlinux}" || \
	fail 'extlinux does not enable the board overlay'
root_uuid=$(sudo blkid -s UUID -o value "${root_partition}")
append=$(awk 'tolower($1) == "append" {$1=""; print; exit}' "${extlinux}")
[[ " ${append} " == *" root=UUID=${root_uuid} "* ]] || \
	fail 'extlinux root UUID does not match the image root partition'
test -s "${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo" || \
	fail 'compiled Type-C overlay is missing from the image'
overlay_owner=$(dpkg-query --admindir="${mount_dir}/var/lib/dpkg" -S \
	/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo | cut -d: -f1)
[[ ${overlay_owner} == armbian-bsp-cli-eaidk610-edge ]] || \
	fail 'Type-C overlay is not owned by the native EAIDK610 BSP package'
[[ -x ${mount_dir}/usr/bin/eaidk610-typec ]] || fail 'Type-C userspace tool is missing or not executable'
[[ -x ${mount_dir}/usr/sbin/eaidk610-boot-setup && -s ${mount_dir}/usr/share/eaidk610/boot-defaults ]] || \
	fail 'BSP boot configuration support is missing'
[[ -f ${mount_dir}/etc/eaidk610/boot-managed ]] || fail 'image boot entry is not managed by the BSP'
[[ -s ${mount_dir}/usr/share/eaidk610/cpu-overclock.dts ]] || fail 'optional CPU overlay source is missing'
kernel_image=$(find "${mount_dir}/boot" -maxdepth 1 -type f \
	-name 'vmlinuz-*edge-rockchip64' -print -quit)
module_dir=$(find "${mount_dir}/lib/modules" -mindepth 1 -maxdepth 1 -type d \
	-name '*edge-rockchip64' -print -quit)
[[ -s ${kernel_image} ]] || fail 'edge rockchip64 kernel image is missing'
[[ -d ${module_dir} ]] || fail 'edge rockchip64 module directory is missing'
[[ -n $(find "${module_dir}" -type f -name 'rtw88_8812au.ko*' -print -quit) ]] || \
	fail 'RTL8812AU kernel module is missing'
[[ -s ${mount_dir}/lib/firmware/rtw88/rtw8812a_fw.bin ]] || \
	fail 'RTL8812AU firmware is missing'

[[ -s ${dtb_path} ]] || fail 'EAIDK610 base DTB is missing'
merged_dtb="${validate_tmp}/merged.dtb"
fdtoverlay -i "${dtb_path}" -o "${merged_dtb}" \
	"${mount_dir}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo" || \
	fail 'Type-C overlay cannot be applied to the final EAIDK610 DTB'
if fdtget "${merged_dtb}" /opp-table-1/opp-2208000000 opp-hz >/dev/null 2>&1; then
	fail 'experimental CPU overclock must be disabled in the default image'
fi
[[ $(fdtget -t s "${merged_dtb}" /regulator-vcc5v0-typec status) == disabled ]] || \
	fail 'overlay did not disable the always-on Type-C regulator'
[[ $(fdtget -t s "${merged_dtb}" /regulator-vcc5v0-typec-managed status) == okay ]] || \
	fail 'overlay did not enable the managed Type-C regulator'
connector=/i2c@ff3d0000/typec-portc@22/connector
[[ $(fdtget -t s "${merged_dtb}" "${connector}" try-power-role) == sink ]] || \
	fail 'overlay did not set the connector Sink preference'
if fdtget "${merged_dtb}" "${connector}" pd-disable >/dev/null 2>&1; then
	fail 'overlay left USB PD disabled'
fi
[[ $(fdtget -t x "${merged_dtb}" "${connector}" source-pdos) == 2e0190b4 ]] || \
	fail 'expected a single fixed 5V / 1.8A Source PDO'
[[ $(fdtget -t x "${merged_dtb}" "${connector}" sink-pdos) == 2e01900a ]] || \
	fail 'expected a single fixed 5V / 100mA Sink PDO'
[[ $(fdtget -t u "${merged_dtb}" "${connector}" op-sink-microwatt) == 500000 ]] || \
	fail 'incorrect Type-C interface power budget'
tcphy0_path=$(fdtget -t s "${merged_dtb}" /__symbols__ tcphy0)
tcphy0_extcon=$(fdtget -t x "${merged_dtb}" "${tcphy0_path}" extcon)
bridge_phandle=$(fdtget -t x "${merged_dtb}" /typec-extcon phandle)
[[ ${tcphy0_extcon} == "${bridge_phandle}" ]] || \
	fail 'overlay did not connect the RK3399 Type-C PHY to the extcon bridge'
# Both graph links must be reciprocal; TCPM must not look up the PHY as a switch.
for link in 'usbc_ss 0' 'tcphy0_typec_ss 1'; do
	read -r endpoint_symbol bridge_port <<< "${link}"
	endpoint_path=$(fdtget -t s "${merged_dtb}" /__symbols__ "${endpoint_symbol}")
	bridge_endpoint=/typec-extcon/ports/port@${bridge_port}/endpoint
	[[ $(fdtget -t x "${merged_dtb}" "${endpoint_path}" remote-endpoint) == \
		"$(fdtget -t x "${merged_dtb}" "${bridge_endpoint}" phandle)" && \
		$(fdtget -t x "${merged_dtb}" "${bridge_endpoint}" remote-endpoint) == \
		"$(fdtget -t x "${merged_dtb}" "${endpoint_path}" phandle)" ]] || \
		fail 'Type-C graph must connect connector and PHY through the extcon bridge'
done

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

# Check the resolved supplies, not only whether the overlay contains properties.
while read -r consumer property supply; do
	[[ $(fdtget -t x "${merged_dtb}" "${consumer}" "${property}") == \
		$(fdtget -t x "${merged_dtb}" "${supply}" phandle) ]] || \
		fail "incorrect ${consumer} ${property}"
done <<'SUPPLIES'
/hdmi@ff940000 avdd-0v9-supply /regulator-vcca0v9-s3
/hdmi@ff940000 avdd-1v8-supply /regulator-vcca1v8-s3
/saradc@ff100000 vref-supply /regulator-vcca1v8-s3
/mmc@fe320000 vmmc-supply /regulator-vcc3v0-sd
/mmc@fe320000 vqmmc-supply /i2c@ff3c0000/pmic@1b/regulators/LDO_REG4
SUPPLIES
[[ $(fdtget -t s "${merged_dtb}" /hdmi-sound status) == okay ]] || \
	fail 'HDMI sound card is disabled'

cleanup
trap - EXIT
printf 'EAIDK610_IMAGE_CONTENTS_OK\n'
