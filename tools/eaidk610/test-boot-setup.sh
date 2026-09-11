#!/bin/bash
# Tests operate on fixtures only: no root, board, mount, or block-device writes.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tool=${repo}/config/optional/boards/eaidk610/_packages/bsp-cli/usr/sbin/eaidk610-boot-setup
# shellcheck source=/dev/null
source "${tool}"
test_tmp=$(mktemp -d /tmp/eaidk610-boot-test.XXXXXX)
trap 'rm -r -- "${test_tmp}"' EXIT
fixture=${test_tmp}/root

require_root() { :; }
dpkg-query() { printf '%s' "${mock_arch:-arm64}"; }
findmnt() {
	case ${*: -1} in
		FSTYPE)
			if [[ " $* " == *" -M ${fixture}/boot "* ]]; then
				printf '%s\n' "${mock_boot_fs:-ext4}"
			else
				printf '%s\n' "${mock_fs:-ext4}"
			fi ;;
		UUID) printf '%s\n' 11111111-2222-3333-4444-555555555555 ;;
		SOURCE) printf '%s\n' /dev/fixturep1 ;;
	esac
}
lsblk() { printf '%s\n' "${mock_device_type:-part}"; }
mountpoint() { [[ ${mock_separate_boot:-no} == yes ]]; }
sync() { :; }
dd() { printf '%s\n' "$*" >> "${test_tmp}/disk-writes"; }

expect_failure() {
	local status
	set +e
	(set -e; "$@") > "${test_tmp}/error" 2>&1
	status=$?
	set -e
	if (( status == 0 )); then
		printf 'Expected failure: %s\n' "$*" >&2
		exit 1
	fi
}
setup_fixture() {
	mkdir -p "${fixture}/boot/dtb/rockchip" "${fixture}/boot/overlay-user" \
		"${fixture}/etc/default" "${fixture}/usr/share/eaidk610" "${fixture}/var/lib/dpkg"
	printf 'BOARD=eaidk610\n' > "${fixture}/etc/armbian-release"
	printf '# root mount\n' > "${fixture}/etc/fstab"
	printf 'MIN_SPEED=408000\nMAX_SPEED=2016000\nGOVERNOR=ondemand\n' > "${fixture}/etc/default/cpufrequtils"
	printf 'BOARD_CMDLINE=%q\nBOOT_DTB=%q\nCPU_MAX_DEFAULT=%q\n' \
		'rootwait console=tty1 console=ttyS2,1500000n8 earlycon loglevel=8 systemd.show_status=yes rt_group_sched=0 rw' \
		'rockchip/rk3399-eaidk-610.dtb' 2016000 > "${fixture}/usr/share/eaidk610/boot-defaults"
	local path
	for path in Image uInitrd dtb/rockchip/rk3399-eaidk-610.dtb overlay-user/rk3399-eaidk-610-typec-fix.dtbo; do
		printf 'fixture\n' > "${fixture}/boot/${path}"
	done
}

(main --help) >/dev/null
expect_failure main --unknown
expect_failure main --root
expect_failure main --cpu-overclock
expect_failure main --cpu-overclock invalid
setup_fixture
# Ordinary package installation must not take over an unmanaged system.
(main --root "${fixture}" --refresh)
[[ ! -e ${fixture}/boot/extlinux/extlinux.conf ]]
expect_failure main --root "${fixture}" --refresh --install-uboot /dev/null

# Legacy conversion, with explicit user extras and no recovery kernel.
printf 'extraargs=quiet splash console=old loglevel=1 custom=value\n' > "${fixture}/boot/armbianEnv.txt"
touch "${fixture}/boot/boot.cmd" "${fixture}/boot/boot.scr"
(main --root "${fixture}") >/dev/null
config=${fixture}/boot/extlinux/extlinux.conf
grep -Fq 'kernel /boot/Image' "${config}"
grep -Fq 'fdtoverlays /boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo' "${config}"
grep -Fq 'root=UUID=11111111-2222-3333-4444-555555555555' "${config}"
grep -Fq 'custom=value' "${config}"
! grep -Eq 'quiet|splash|console=old|loglevel=1' "${config}"
[[ -e ${fixture}/etc/eaidk610/boot-managed && ! -e ${fixture}/boot/boot.scr ]]
[[ ! -e ${fixture}/boot/armbianEnv.txt && ! -e ${fixture}/boot/boot.cmd ]]
[[ $(find "${fixture}/boot" -name 'eaidk610-previous-boot*' | wc -l) == 0 ]]
[[ ! -e ${test_tmp}/disk-writes ]]
[[ ! -e ${fixture}/etc/eaidk610/cpu-overclock ]]
grep -Fxq MAX_SPEED=2016000 "${fixture}/etc/default/cpufrequtils"

# Idempotent upgrades retain root/user arguments, including in a chroot where
# findmnt would report the host. They do not require a mounted root device.
cp "${config}" "${test_tmp}/before"
(findmnt() { return 1; }; main --root "${fixture}" --refresh) >/dev/null
cmp "${config}" "${test_tmp}/before"

# Update managed defaults without dropping user extras.
printf 'BOARD_CMDLINE=%q\nBOOT_DTB=%q\nCPU_MAX_DEFAULT=%q\n' \
	'rootwait console=tty1 console=ttyS2,1500000n8 earlycon loglevel=8 systemd.show_status=yes rt_group_sched=0 rw new_board_option=1' \
	'rockchip/rk3399-eaidk-610.dtb' 2016000 > "${fixture}/usr/share/eaidk610/boot-defaults"
(main --root "${fixture}" --refresh) >/dev/null
grep -Fq 'new_board_option=1' "${config}"
grep -Fq 'custom=value' "${config}"

# Explicit overrides and a separate boot filesystem.
(mock_separate_boot=yes; main --root "${fixture}" --root-uuid aaaa-bbbb --extra-args 'test=2') >/dev/null
grep -Fxq '  kernel /Image' "${config}"
grep -Fxq '  initrd /uInitrd' "${config}"
grep -Fq 'root=UUID=aaaa-bbbb' "${config}"
! grep -q custom=value "${config}"
cp "${config}" "${test_tmp}/before"

# Fail before touching boot configuration or disk on incomplete installations.
mock_arch=amd64 expect_failure main --root "${fixture}"
mock_fs=btrfs expect_failure main --root "${fixture}"
mock_device_type=lvm expect_failure main --root "${fixture}"
expect_failure main --root "${fixture}" --root-uuid invalid
expect_failure main --root "${fixture}" --extra-args $'a\nb'
printf 'UUID=123 /boot ext4 defaults 0 2\n' > "${fixture}/etc/fstab"
expect_failure main --root "${fixture}"
printf '# mounted root only\n' > "${fixture}/etc/fstab"
mv "${fixture}/boot/uInitrd" "${test_tmp}/initrd"
expect_failure main --root "${fixture}"
mv "${test_tmp}/initrd" "${fixture}/boot/uInitrd"
cmp "${config}" "${test_tmp}/before"

# A directory at the destination must fail, not receive the staged file and
# incorrectly report a usable extlinux.conf.
mv "${config}" "${test_tmp}/entry"
mkdir "${config}"
expect_failure main --root "${fixture}"
[[ -z $(find "${config}" -mindepth 1 -print -quit) ]]
rmdir "${config}"
mv "${test_tmp}/entry" "${config}"

# Flash bounds tested with regular files, never a block device.
firmware=${test_tmp}/u-boot-rockchip.bin
truncate -s 9000000 "${firmware}"
check_uboot_layout "${firmware}" '{"partitiontable":{"label":"dos","partitions":[{"start":32768}]}}'
check_uboot_layout "${firmware}" '{"partitiontable":{"label":"gpt","firstlba":34,"partitions":[{"start":32768}]}}'
expect_failure check_uboot_layout "${firmware}" '{"partitiontable":{"label":"dos","partitions":[{"start":2048}]}}'
expect_failure check_uboot_layout "${firmware}" '{"partitiontable":{"label":"gpt","firstlba":128,"partitions":[{"start":32768}]}}'
expect_failure check_uboot_layout "${firmware}" '{"partitiontable":{"label":"dos","partitions":[]}}'
expect_failure check_uboot /dev/null "${firmware}"

# The explicit flash option is the only route to dd; interception is test-only.
(check_uboot() { :; }; main --root "${fixture}" --install-uboot "${firmware}") >/dev/null
[[ $(wc -l < "${test_tmp}/disk-writes") == 1 ]]
grep -Fq 'bs=32K seek=1 conv=notrunc,fsync' "${test_tmp}/disk-writes"

# A failed write must not be reported as a completed conversion.
failed_flash() {
	check_uboot() { :; }
	dd() { return 1; }
	main --root "${fixture}" --install-uboot "${firmware}"
}
expect_failure failed_flash
! grep -q 'No reboot performed' "${test_tmp}/error"

# Real dtc/fdtoverlay tests: opt-in CPU OPPs with a minimal board-fix fixture.
assets=${fixture}/usr/share/eaidk610
dtc -q -I dts -O dtb -o "${fixture}/boot/dtb/rockchip/rk3399-eaidk-610.dtb" <<'DTS'
/dts-v1/;
/ {
 opp-table-0 { opp-1416000000 { opp-hz = /bits/ 64 <1416000000>; opp-microvolt = <1125000>; }; };
 opp-table-1 { opp-1800000000 { opp-hz = /bits/ 64 <1800000000>; opp-microvolt = <1200000>; }; };
};
DTS
printf '%s\n' '/dts-v1/; /plugin/; / { fragment@0 { target-path = "/"; __overlay__ { board-fix = "retained"; }; }; };' \
	> "${assets}/rk3399-eaidk-610-typec-fix.dts"
cp "${repo}/config/optional/boards/eaidk610/_packages/bsp-cli/usr/share/eaidk610/cpu-overclock.dts" "${assets}/"
(main --root "${fixture}" --cpu-overclock on) >/dev/null
grep -Fxq on "${fixture}/etc/eaidk610/cpu-overclock"
grep -Fxq MAX_SPEED=2208000 "${fixture}/etc/default/cpufrequtils"
grep -Fxq GOVERNOR=ondemand "${fixture}/etc/default/cpufrequtils"
overlay=${fixture}/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo
fdtoverlay -i "${fixture}/boot/dtb/rockchip/rk3399-eaidk-610.dtb" -o "${test_tmp}/merged.dtb" "${overlay}"
[[ $(fdtget -t u "${test_tmp}/merged.dtb" /opp-table-0/opp-1800000000 opp-microvolt) == 1287500 ]]
[[ $(fdtget -t u "${test_tmp}/merged.dtb" /opp-table-1/opp-2208000000 opp-microvolt) == 1325000 ]]
[[ $(fdtget -t s "${test_tmp}/merged.dtb" / board-fix) == retained ]]
cp "${overlay}" "${test_tmp}/overclock.dtbo"

# A BSP upgrade replaces the packaged DTBO; refresh must restore the user's
# choice while preserving a subsequently customized CPU limit.
printf 'BSP replaced overlay\n' > "${overlay}"
sed -i s/MAX_SPEED=2208000/MAX_SPEED=2016000/ "${fixture}/etc/default/cpufrequtils"
(findmnt() { return 1; }; main --root "${fixture}" --refresh) >/dev/null
cmp "${overlay}" "${test_tmp}/overclock.dtbo"
grep -Fxq MAX_SPEED=2016000 "${fixture}/etc/default/cpufrequtils"
expect_failure main --root "${fixture}" --refresh --cpu-overclock off

# A failed compile must not replace the overlay, boot entry, CPU limit or state.
cp "${config}" "${test_tmp}/before-cpu-failure"
failed_cpu_compile() { dtc() { return 1; }; main --root "${fixture}" --cpu-overclock off; }
expect_failure failed_cpu_compile
cmp "${overlay}" "${test_tmp}/overclock.dtbo"
cmp "${config}" "${test_tmp}/before-cpu-failure"
grep -Fxq on "${fixture}/etc/eaidk610/cpu-overclock"
grep -Fxq MAX_SPEED=2016000 "${fixture}/etc/default/cpufrequtils"
[[ -z $(find "${fixture}/boot/overlay-user" -name '.eaidk610-cpu.*' -print -quit) ]]

# Off also works with a separate FAT boot partition and retains non-CPU fixes.
(mock_separate_boot=yes; mock_boot_fs=vfat; main --root "${fixture}" --cpu-overclock off) >/dev/null
grep -Fxq '  kernel /Image' "${config}"
grep -Fxq off "${fixture}/etc/eaidk610/cpu-overclock"
grep -Fxq MAX_SPEED=2016000 "${fixture}/etc/default/cpufrequtils"
fdtoverlay -i "${fixture}/boot/dtb/rockchip/rk3399-eaidk-610.dtb" -o "${test_tmp}/merged.dtb" "${overlay}"
! fdtget "${test_tmp}/merged.dtb" /opp-table-1/opp-2208000000 opp-hz >/dev/null 2>&1
[[ $(fdtget -t s "${test_tmp}/merged.dtb" / board-fix) == retained ]]
cp "${overlay}" "${test_tmp}/default.dtbo"
(mock_separate_boot=yes; main --root "${fixture}" --refresh) >/dev/null
cmp "${overlay}" "${test_tmp}/default.dtbo"
[[ $(wc -l < "${test_tmp}/disk-writes") == 1 ]]

# Native BSP/U-Boot hook integration and real Debian control serialization,
# without running the Armbian configuration or compiler.
(
	# shellcheck source=/dev/null
	source "${repo}/config/boards/eaidk610.csc"
	# shellcheck source=/dev/null
	source "${repo}/lib/functions/bsp/armbian-bsp-cli-deb.sh"
	display_alert() { :; }
	artifact_deb_reversion_unpack_data_deb() { :; }
	artifact_deb_reversion_repack_data_deb() { :; }
	# Framework globals consumed by the sourced packaging functions.
	# shellcheck disable=SC2034
	BOARD=eaidk610 BRANCH=edge EXTRA_BSP_NAME='' REVISION=26.11.0-trunk
	# shellcheck disable=SC2034
	KEEP_ORIGINAL_OS_RELEASE=no SHOW_DEBUG=no
	data_dir=${test_tmp}/package
	mkdir -p "${data_dir}/DEBIAN" "${data_dir}/etc"
	control_file_new=${data_dir}/DEBIAN/control
	printf 'Package: armbian-bsp-cli-eaidk610-edge\nVersion: 26.11.0-trunk\nArchitecture: arm64\nMaintainer: Test <test@example.invalid>\nDescription: BSP control fixture\n' > "${control_file_new}"
	reversion_armbian-bsp-cli_deb_contents armbian-bsp-cli
	dpkg-deb --build --root-owner-group "${data_dir}" "${test_tmp}/bsp.deb" >/dev/null
	deps=$(dpkg-deb -f "${test_tmp}/bsp.deb" Depends)
	[[ ${deps} == *', base-files,'* && ${deps} != *'base-files ('* ]]
	[[ ${deps} == *linux-image-edge-rockchip64* && ${deps} == *linux-dtb-edge-rockchip64* ]]
	[[ ${deps} == *device-tree-compiler* ]]
	[[ $(dpkg-deb -f "${test_tmp}/bsp.deb" Conflicts) == *armbian-bsp-cli* ]]
	# Other boards keep their existing version constraint.
	unset BSP_BASE_FILES_DEPENDENCY
	control_file_new=${test_tmp}/other-control
	reversion_armbian-bsp-cli_deb_contents armbian-bsp-cli
	grep -Fq 'base-files (>= 26.11.0-trunk)' "${control_file_new}"
	uboot_postinst_base() { fail 'unexpected automatic firmware write'; }
	pre_package_uboot_image__eaidk610_explicit_flash
	FORCE_UBOOT_UPDATE=yes uboot_postinst_base >/dev/null
)
printf 'EAIDK610_BOOT_SETUP_TEST_OK\n'
