#!/bin/bash

set -Eeuo pipefail

board=${3:-}
if [[ ${board} != eaidk610 ]]; then
	printf 'Refusing EAIDK610 customization for BOARD=%s\n' "${board:-unset}" >&2
	exit 2
fi

overlay_name=rk3399-eaidk-610-typec-fix
root_prefix=${EAIDK610_ROOT_PREFIX:-}
overlay_source=${root_prefix}/tmp/overlay/boot/overlay-user
overlay_target=${root_prefix}/boot/overlay-user
armbian_env=${root_prefix}/boot/armbianEnv.txt

install -d -m 0755 "${overlay_target}"
install -m 0644 "${overlay_source}/${overlay_name}.dtbo" \
	"${overlay_target}/${overlay_name}.dtbo"

sed -i '/^user_overlays=/d' "${armbian_env}"
printf 'user_overlays=%s\n' "${overlay_name}" >> "${armbian_env}"
