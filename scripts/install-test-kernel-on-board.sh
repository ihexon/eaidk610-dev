#!/usr/bin/env bash

set -Eeuo pipefail

readonly release="7.1.8-edge-rockchip64-eaidk610-typec-r1"
readonly old_release="7.1.8-edge-rockchip64"
readonly staging="${1:-/home/ihexon/eaidk610-typec-test}"
readonly image_package="linux-image-edge-rockchip64-eaidk610-typec-r1"
readonly dtb_package="linux-dtb-edge-rockchip64-eaidk610-typec-r1"
readonly image_sha256="00bc986e0f1864d245df7db5902a08197b8c0532790db473ad1dd50a7bcad353"
readonly dtb_sha256="ab825dc5d4badb64d9aefe48e871ecded6f3dd81b7d29364aa804af2c72053bf"
readonly overlay="/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || die "run this script as root"

shopt -s nullglob
image_debs=("${staging}"/${image_package}_*.deb)
dtb_debs=("${staging}"/${dtb_package}_*.deb)
[[ ${#image_debs[@]} -eq 1 ]] || die "expected exactly one image package in ${staging}"
[[ ${#dtb_debs[@]} -eq 1 ]] || die "expected exactly one DTB package in ${staging}"
readonly image_deb="${image_debs[0]}"
readonly dtb_deb="${dtb_debs[0]}"

printf '%s  %s\n' "${image_sha256}" "${image_deb}" | sha256sum --check --status
printf '%s  %s\n' "${dtb_sha256}" "${dtb_deb}" | sha256sum --check --status

for path in \
    "/boot/vmlinuz-${old_release}" \
    "/boot/uInitrd-${old_release}" \
    "/boot/dtb-${old_release}" \
    /boot/extlinux/extlinux.conf \
    "${overlay}"; do
    [[ -e ${path} ]] || die "required recovery/boot file is missing: ${path}"
done

backup_dir="/boot/eaidk610-typec-backup-$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "${backup_dir}"
cp -a /boot/extlinux "${backup_dir}/"
[[ ! -f /boot/armbianEnv.txt ]] || cp -a /boot/armbianEnv.txt "${backup_dir}/"
{
    printf 'kernel=%s\nboot_id=%s\n' "$(uname -r)" "$(cat /proc/sys/kernel/random/boot_id)"
    printf 'Image -> %s\nuInitrd -> %s\ndtb -> %s\n' \
        "$(readlink /boot/Image || true)" \
        "$(readlink /boot/uInitrd || true)" \
        "$(readlink /boot/dtb || true)"
    sha256sum /boot/Image /boot/uInitrd /boot/dtb/rockchip/rk3399-eaidk-610.dtb
    dpkg-query -W "${image_package}" "${dtb_package}" 2>/dev/null || true
} >"${backup_dir}/preinstall-state.txt"

# Always install the exact packages whose release hashes were verified above.
# The same r1 package version may have been installed from an earlier CI run;
# package status alone cannot prove that its bytes match this release.
DEBIAN_FRONTEND=noninteractive dpkg -i "${dtb_deb}" "${image_deb}"

dpkg --audit
dpkg-query -W -f='${db:Status-Status}' "${image_package}" | grep -qx installed
dpkg-query -W -f='${db:Status-Status}' "${dtb_package}" | grep -qx installed

for path in \
    "/boot/vmlinuz-${release}" \
    "/boot/initrd.img-${release}" \
    "/boot/dtb-${release}" \
    "/lib/modules/${release}"; do
    [[ -e ${path} ]] || die "installed kernel file is missing: ${path}"
done

tmp_uinitrd=$(mktemp "/boot/.uInitrd-${release}.XXXXXX")
trap 'rm -f "${tmp_uinitrd}"' EXIT
mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd \
    -d "/boot/initrd.img-${release}" "${tmp_uinitrd}" >/dev/null
chmod 0644 "${tmp_uinitrd}"

initrd_size=$(stat -c %s "/boot/initrd.img-${release}")
uinitrd_size=$(stat -c %s "${tmp_uinitrd}")
[[ ${uinitrd_size} -eq $((initrd_size + 64)) ]] || die "uInitrd has an unexpected size"
[[ $(tail -c +65 "${tmp_uinitrd}" | sha256sum | awk '{print $1}') == \
   $(sha256sum "/boot/initrd.img-${release}" | awk '{print $1}') ]] || die "uInitrd payload differs from initrd"

mv -f "${tmp_uinitrd}" "/boot/uInitrd-${release}"
trap - EXIT
ln -sfn "vmlinuz-${release}" /boot/Image
ln -sfn "uInitrd-${release}" /boot/uInitrd
ln -sfn "dtb-${release}" /boot/dtb

[[ $(readlink /boot/Image) == "vmlinuz-${release}" ]]
[[ $(readlink /boot/uInitrd) == "uInitrd-${release}" ]]
[[ $(readlink /boot/dtb) == "dtb-${release}" ]]
[[ -f /boot/dtb/rockchip/rk3399-eaidk-610.dtb ]]
[[ $(grep -c '^LABEL ' /boot/extlinux/extlinux.conf) -eq 1 ]]
grep -qx '  LINUX /boot/Image' /boot/extlinux/extlinux.conf
grep -qx '  INITRD /boot/uInitrd' /boot/extlinux/extlinux.conf
grep -qx '  FDT /boot/dtb/rockchip/rk3399-eaidk-610.dtb' /boot/extlinux/extlinux.conf
grep -qx '  FDTOVERLAYS /boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo' /boot/extlinux/extlinux.conf
cmp -s "${backup_dir}/extlinux/extlinux.conf" /boot/extlinux/extlinux.conf

if command -v fdtoverlay >/dev/null 2>&1; then
    merged_dtb=$(mktemp /tmp/eaidk610-merged.XXXXXX.dtb)
    trap 'rm -f "${merged_dtb}"' EXIT
    fdtoverlay -i /boot/dtb/rockchip/rk3399-eaidk-610.dtb \
        -o "${merged_dtb}" "${overlay}"
    rm -f "${merged_dtb}"
    trap - EXIT
fi

sync
printf 'PRE_REBOOT_OK\nrelease=%s\nbackup=%s\n' "${release}" "${backup_dir}"
