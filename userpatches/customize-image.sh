#!/bin/bash

set -Eeuo pipefail

board=${3:-}
if [[ ${board} != eaidk610 ]]; then
	printf 'Refusing EAIDK610 customization for BOARD=%s\n' "${board:-unset}" >&2
	exit 2
fi

root_prefix=${EAIDK610_ROOT_PREFIX:-}
package=${root_prefix}/tmp/overlay/eaidk610-board-overlays.deb

if [[ -n ${root_prefix} ]]; then
	dpkg-deb --extract "${package}" "${root_prefix}"
	dpkg-deb --control "${package}" "${root_prefix}/tmp/overlay-package-control"
	EAIDK610_ROOT_PREFIX=${root_prefix} \
		"${root_prefix}/tmp/overlay-package-control/postinst" configure
else
	dpkg -i "${package}"
fi
