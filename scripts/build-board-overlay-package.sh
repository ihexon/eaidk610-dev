#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
# shellcheck source=../config/image.env
source "${repo_root}/config/image.env"

output=${1:-${repo_root}/userpatches/overlay/eaidk610-board-overlays.deb}
package_source="${repo_root}/packaging/eaidk610-board-overlays"
package_root=$(mktemp -d /tmp/eaidk610-overlay-package.XXXXXX)
trap 'rm -rf -- "${package_root}"' EXIT

cp -a "${package_source}/." "${package_root}/"
chmod 0755 "${package_root}" "${package_root}/DEBIAN"
chmod 0644 "${package_root}/DEBIAN/control"
chmod 0755 "${package_root}/DEBIAN/postinst"
install -d -m 0755 "${package_root}/boot/overlay-user"
chmod 0755 "${package_root}/boot"
dtc -q -@ -I dts -O dtb \
	-o "${package_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo" \
	"${repo_root}/${TYPEC_OVERLAY_SOURCE}"
chmod 0644 "${package_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo"

# Armbian supplies this firmware at the top level; btbcm searches brcm/.
install -d -m 0755 "${package_root}/usr/lib/firmware/brcm"
ln -s ../BCM4345C0.hcd \
	"${package_root}/usr/lib/firmware/brcm/BCM4345C0.openailab,eaidk-610.hcd"

install -d "$(dirname -- "${output}")"
dpkg-deb --build --root-owner-group "${package_root}" "${output}" >/dev/null
printf '%s\n' "${output}"
