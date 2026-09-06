#!/usr/bin/env bash

set -Eeuo pipefail

readonly expected_release="7.1.8-edge-rockchip64-eaidk610-typec-r1"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || die "run this script as root"
[[ $(uname -r) == "${expected_release}" ]] || die "unexpected running kernel: $(uname -r)"

boot_id=$(cat /proc/sys/kernel/random/boot_id)
readonly report_dir="/home/ihexon/typec-test-log-${boot_id}"
install -d -m 0750 -o ihexon -g ihexon "${report_dir}"

{
    uname -a
    printf 'boot_id=%s\n' "${boot_id}"
    uptime
    printf 'Image -> %s\nuInitrd -> %s\ndtb -> %s\n' \
        "$(readlink /boot/Image)" "$(readlink /boot/uInitrd)" "$(readlink /boot/dtb)"
    dpkg-query -W \
        linux-image-edge-rockchip64-eaidk610-typec-r1 \
        linux-dtb-edge-rockchip64-eaidk610-typec-r1
    dpkg --audit
} >"${report_dir}/system.txt"

{
    for name in port_type preferred_role power_role data_role orientation power_operation_mode; do
        [[ -r /sys/class/typec/port0/${name} ]] || continue
        printf '%s=' "${name}"
        cat "/sys/class/typec/port0/${name}"
    done
    if [[ -e /sys/class/typec/port0-partner ]]; then
        printf 'partner=present\n'
    else
        printf 'partner=absent\n'
    fi
} >"${report_dir}/typec-status.txt"

lsusb >"${report_dir}/lsusb.txt"
lsusb -t >"${report_dir}/lsusb-tree.txt"
dmesg >"${report_dir}/dmesg.log"
journalctl -k -b --no-pager >"${report_dir}/kernel-journal.log"
journalctl -k -b -p warning --no-pager >"${report_dir}/kernel-warnings.log"

for debug_log in \
    /sys/kernel/debug/usb/tcpm-4-0022/log \
    /sys/kernel/debug/usb/fusb302-4-0022/log; do
    output="${report_dir}/$(basename "$(dirname "${debug_log}")").log"
    if [[ -r ${debug_log} ]]; then
        cat "${debug_log}" >"${output}"
    else
        printf 'debug log is not available: %s\n' "${debug_log}" >"${output}"
    fi
done

chown -R ihexon:ihexon "${report_dir}"

cat "${report_dir}/typec-status.txt"
if grep -q '18d1:4ee8' "${report_dir}/lsusb.txt"; then
    printf 'android_usb=18d1:4ee8\n'
else
    printf 'android_usb=not-enumerated\n'
fi
printf 'typec_kernel_errors=%s\n' \
    "$(grep -Eic 'fusb|tcpm|type.?c' "${report_dir}/kernel-warnings.log" || true)"
printf 'report=%s\n' "${report_dir}"
