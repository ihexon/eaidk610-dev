#!/usr/bin/env bash

set -Eeuo pipefail

input=${1:?usage: read-kernel-compiler.sh COMPILE_H_OR_DASH}
compiler=$(sed -n \
    's/^#define[[:space:]]\+LINUX_COMPILER[[:space:]]\+"\(.*\)"$/\1/p' \
    "${input}")

if [[ -z ${compiler} ]]; then
    printf 'Unable to read LINUX_COMPILER from %s\n' "${input}" >&2
    exit 1
fi

printf '%s\n' "${compiler}"
