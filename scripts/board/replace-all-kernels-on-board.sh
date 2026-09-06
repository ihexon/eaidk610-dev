#!/usr/bin/env bash

set -Eeuo pipefail

readonly release="7.1.8-edge-rockchip64-eaidk610-typec-r1"
readonly old_release="7.1.8-edge-rockchip64"
readonly image_package="linux-image-edge-rockchip64-eaidk610-typec-r1"
readonly dtb_package="linux-dtb-edge-rockchip64-eaidk610-typec-r1"
readonly old_image_package="linux-image-edge-rockchip64"
readonly old_dtb_package="linux-dtb-edge-rockchip64"
readonly image_sha256="00bc986e0f1864d245df7db5902a08197b8c0532790db473ad1dd50a7bcad353"
readonly dtb_sha256="ab825dc5d4badb64d9aefe48e871ecded6f3dd81b7d29364aa804af2c72053bf"
readonly overlay="/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || die "run this script as root"
[[ $# -eq 1 ]] || die "usage: $0 /home/ihexon/eaidk610-release-r1.DIRECTORY"
readonly staging="$(realpath -e -- "$1")"
[[ ${staging} == /home/ihexon/eaidk610-release-r1.* ]] ||
    die "unexpected staging directory: ${staging}"
[[ $(hostname -s) == armbian ]] || die "unexpected target host: $(hostname -s)"
[[ $(dpkg --print-architecture) == arm64 ]] || die "target is not arm64"
[[ $(uname -r) == "${release}" ]] || die "unexpected running kernel: $(uname -r)"

for command_name in dpkg dpkg-deb findmnt mkimage sha256sum; do
    command -v "${command_name}" >/dev/null || die "missing command: ${command_name}"
done

shopt -s nullglob
image_debs=("${staging}"/${image_package}_*.deb)
dtb_debs=("${staging}"/${dtb_package}_*.deb)
[[ ${#image_debs[@]} -eq 1 ]] || die "expected exactly one image package"
[[ ${#dtb_debs[@]} -eq 1 ]] || die "expected exactly one DTB package"
readonly image_deb="${image_debs[0]}"
readonly dtb_deb="${dtb_debs[0]}"

printf '%s  %s\n' "${image_sha256}" "${image_deb}" | sha256sum --check --status
printf '%s  %s\n' "${dtb_sha256}" "${dtb_deb}" | sha256sum --check --status
[[ $(dpkg-deb -f "${image_deb}" Package) == "${image_package}" ]]
[[ $(dpkg-deb -f "${dtb_deb}" Package) == "${dtb_package}" ]]
[[ $(dpkg-deb -f "${image_deb}" Version) == 26.08.0-trunk ]]
[[ $(dpkg-deb -f "${dtb_deb}" Version) == 26.08.0-trunk ]]
[[ $(dpkg-deb -f "${image_deb}" Architecture) == arm64 ]]
[[ $(dpkg-deb -f "${dtb_deb}" Architecture) == arm64 ]]

readonly extract_dir="$(mktemp -d /tmp/eaidk610-release-extract.XXXXXX)"
readonly image_members="$(mktemp /tmp/eaidk610-image-members.XXXXXX)"
readonly dtb_members="$(mktemp /tmp/eaidk610-dtb-members.XXXXXX)"
trap 'rm -rf -- "${extract_dir}"; rm -f -- "${image_members}" "${dtb_members}"' EXIT
dpkg-deb --fsys-tarfile "${image_deb}" | tar -tf - >"${image_members}"
dpkg-deb --fsys-tarfile "${dtb_deb}" | tar -tf - >"${dtb_members}"
grep -Fqx "./boot/vmlinuz-${release}" "${image_members}"
grep -Fq "./lib/modules/${release}/" "${image_members}"
grep -Fqx "./boot/dtb-${release}/rockchip/rk3399-eaidk-610.dtb" "${dtb_members}"
dpkg-deb -x "${image_deb}" "${extract_dir}"
dpkg-deb -x "${dtb_deb}" "${extract_dir}"

[[ -f /boot/extlinux/extlinux.conf ]] || die "missing extlinux.conf"
[[ -f ${overlay} ]] || die "missing required Type-C overlay"
[[ $(grep -c '^LABEL ' /boot/extlinux/extlinux.conf) -eq 1 ]]
grep -qx '  LINUX /boot/Image' /boot/extlinux/extlinux.conf
grep -qx '  INITRD /boot/uInitrd' /boot/extlinux/extlinux.conf
grep -qx '  FDT /boot/dtb/rockchip/rk3399-eaidk-610.dtb' /boot/extlinux/extlinux.conf
grep -qx '  FDTOVERLAYS /boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo' \
    /boot/extlinux/extlinux.conf
readonly extlinux_sha256="$(sha256sum /boot/extlinux/extlinux.conf | awk '{print $1}')"

readonly -a removable_packages=(
    "${old_image_package}"
    "${old_dtb_package}"
    "${image_package}"
    "${dtb_package}"
)
for package_name in "${removable_packages[@]}"; do
    dpkg-query -W "${package_name}" >/dev/null 2>&1 ||
        die "expected installed package is missing: ${package_name}"
done

while IFS= read -r -d '' boot_entry; do
    case "$(basename -- "${boot_entry}")" in
        Image|uInitrd|\
        "vmlinuz-${old_release}"|"vmlinuz-${release}"|\
        "initrd.img-${old_release}"|"initrd.img-${release}"|\
        "uInitrd-${old_release}"|"uInitrd-${release}"|\
        "System.map-${old_release}"|"System.map-${release}"|\
        "config-${old_release}"|"config-${release}"|\
        dtb|"dtb-${old_release}"|"dtb-${release}")
            ;;
        *)
            die "refusing to delete unknown kernel entry: ${boot_entry}"
            ;;
    esac
done < <(
    find /boot -maxdepth 1 -mindepth 1 \
        \( -name Image -o -name 'vmlinuz*' -o -name 'initrd.img*' \
        -o -name 'uInitrd*' -o -name 'System.map*' -o -name 'config*' \
        -o -name 'dtb*' \) -print0
)

readonly available_bytes="$(df --output=avail -B1 /boot | tail -n 1 | tr -d ' ')"
(( available_bytes >= 536870912 )) || die "less than 512 MiB is available on /boot"

{
    printf 'host=%s\n' "$(hostname)"
    printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id)"
    printf 'running_kernel=%s\n' "$(uname -r)"
    printf 'extlinux_sha256=%s\n' "${extlinux_sha256}"
    printf 'packages_before:\n'
    dpkg-query -W "${removable_packages[@]}"
    printf 'boot_before:\n'
    find /boot -maxdepth 1 -mindepth 1 -printf '%f\t%y\t%l\n' | sort
} >"${staging}/pre-replacement-state.txt"

printf 'Preflight passed; removing all installed boot kernels now\n'
DEBIAN_FRONTEND=noninteractive dpkg --purge "${removable_packages[@]}"

rm -f -- \
    /boot/Image \
    /boot/uInitrd \
    "/boot/vmlinuz-${old_release}" \
    "/boot/vmlinuz-${release}" \
    "/boot/initrd.img-${old_release}" \
    "/boot/initrd.img-${release}" \
    "/boot/uInitrd-${old_release}" \
    "/boot/uInitrd-${release}" \
    "/boot/System.map-${old_release}" \
    "/boot/System.map-${release}" \
    "/boot/config-${old_release}" \
    "/boot/config-${release}"
rm -rf -- \
    /boot/dtb \
    "/boot/dtb-${old_release}" \
    "/boot/dtb-${release}"

printf 'All previous boot kernels removed; installing the verified release immediately\n'
DEBIAN_FRONTEND=noninteractive dpkg -i "${dtb_deb}" "${image_deb}"

for path in \
    "/boot/vmlinuz-${release}" \
    "/boot/initrd.img-${release}" \
    "/boot/dtb-${release}" \
    "/lib/modules/${release}"; do
    [[ -e ${path} ]] || die "installed release file is missing: ${path}"
done
cmp -s "${extract_dir}/boot/vmlinuz-${release}" "/boot/vmlinuz-${release}"
cmp -s \
    "${extract_dir}/boot/dtb-${release}/rockchip/rk3399-eaidk-610.dtb" \
    "/boot/dtb-${release}/rockchip/rk3399-eaidk-610.dtb"

tmp_uinitrd="$(mktemp "/boot/.uInitrd-${release}.XXXXXX")"
trap 'rm -f -- "${tmp_uinitrd}"; rm -rf -- "${extract_dir}"; rm -f -- "${image_members}" "${dtb_members}"' EXIT
mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd \
    -d "/boot/initrd.img-${release}" "${tmp_uinitrd}" >/dev/null
chmod 0644 "${tmp_uinitrd}"
[[ $(stat -c %s "${tmp_uinitrd}") -eq \
   $(( $(stat -c %s "/boot/initrd.img-${release}") + 64 )) ]]
[[ $(tail -c +65 "${tmp_uinitrd}" | sha256sum | awk '{print $1}') == \
   $(sha256sum "/boot/initrd.img-${release}" | awk '{print $1}') ]]
mv -f "${tmp_uinitrd}" "/boot/uInitrd-${release}"

ln -sfn "vmlinuz-${release}" /boot/Image
ln -sfn "uInitrd-${release}" /boot/uInitrd
ln -sfn "dtb-${release}" /boot/dtb

[[ $(readlink /boot/Image) == "vmlinuz-${release}" ]]
[[ $(readlink /boot/uInitrd) == "uInitrd-${release}" ]]
[[ $(readlink /boot/dtb) == "dtb-${release}" ]]
[[ $(sha256sum /boot/extlinux/extlinux.conf | awk '{print $1}') == \
   "${extlinux_sha256}" ]]
[[ ! -e "/boot/vmlinuz-${old_release}" ]]
[[ ! -e "/boot/dtb-${old_release}" ]]
[[ ! -e "/lib/modules/${old_release}" ]]

for package_name in "${image_package}" "${dtb_package}"; do
    [[ $(dpkg-query -W -f='${db:Status-Status}' "${package_name}") == installed ]]
done
for package_name in "${old_image_package}" "${old_dtb_package}"; do
    if dpkg-query -W "${package_name}" >/dev/null 2>&1; then
        die "old package remains registered: ${package_name}"
    fi
done
readonly dpkg_audit="$(dpkg --audit)"
[[ -z ${dpkg_audit} ]] || die "dpkg audit is not clean: ${dpkg_audit}"

sync
trap - EXIT
rm -rf -- "${extract_dir}"
rm -f -- "${image_members}" "${dtb_members}"
printf 'PRE_REBOOT_OK\nrelease=%s\nremoved_recovery_kernels=yes\n' "${release}"
