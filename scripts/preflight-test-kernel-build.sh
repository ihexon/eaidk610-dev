#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

# shellcheck source=../kernel/build.env
source "${repo_root}/kernel/build.env"

case ${1:-} in
    '') network_check=no ;;
    --network) network_check=yes ;;
    *) printf 'usage: %s [--network]\n' "$0" >&2; exit 2 ;;
esac

require_value() {
    local name=$1
    [[ -n ${!name:-} ]] || {
        printf 'Required build input %s is empty\n' "${name}" >&2
        exit 2
    }
}

for name in \
    ARMBIAN_BUILD_REPOSITORY ARMBIAN_BUILD_COMMIT ARMBIAN_BOARD \
    ARMBIAN_BRANCH ARMBIAN_KERNEL_SERIES ARMBIAN_LINUXFAMILY \
    ARMBIAN_LINUXCONFIG ARMBIAN_KERNEL_PATCH_DIR LINUX_REPOSITORY \
    LINUX_COMMIT KERNEL_CONFIG KERNEL_PATCH EXPECTED_KERNELRELEASE \
    KERNEL_CONFIG_SHA256 KERNEL_PATCH_SHA256 ARMBIAN_FAMILY_SHA256; do
    require_value "${name}"
done

[[ ${ARMBIAN_BUILD_COMMIT} =~ ^[0-9a-f]{40}$ ]]
[[ ${LINUX_COMMIT} =~ ^[0-9a-f]{40}$ ]]
[[ ${KERNEL_CONFIG_SHA256} =~ ^[0-9a-f]{64}$ ]]
[[ ${KERNEL_PATCH_SHA256} =~ ^[0-9a-f]{64}$ ]]
[[ ${ARMBIAN_FAMILY_SHA256} =~ ^[0-9a-f]{64}$ ]]

config_path="${repo_root}/${KERNEL_CONFIG}"
patch_path="${repo_root}/${KERNEL_PATCH}"
family_path="${repo_root}/kernel/armbian/rockchip64-family.conf"

printf '%s  %s\n' "${KERNEL_CONFIG_SHA256}" "${config_path}" | sha256sum --check --status
printf '%s  %s\n' "${KERNEL_PATCH_SHA256}" "${patch_path}" | sha256sum --check --status
printf '%s  %s\n' "${ARMBIAN_FAMILY_SHA256}" "${family_path}" | sha256sum --check --status

grep -Fqx "declare -g LINUXFAMILY=\"${ARMBIAN_LINUXFAMILY}\"" "${family_path}"
grep -Fqx "declare -g LINUXCONFIG=\"${ARMBIAN_LINUXCONFIG}\"" "${family_path}"
grep -Fqx "declare -g KERNELPATCHDIR=\"${ARMBIAN_KERNEL_PATCH_DIR}\"" "${family_path}"
[[ ${EXPECTED_KERNELRELEASE} == *-"${ARMBIAN_LINUXFAMILY}" ]]

grep -Fqx 'CONFIG_TYPEC_FUSB302=y' "${config_path}"
grep -Fqx 'CONFIG_TYPEC_TCPM=y' "${config_path}"
grep -Fqx 'CONFIG_DEBUG_FS=y' "${config_path}"
git apply --numstat "${patch_path}" | grep -Fq $'drivers/usb/typec/tcpm/fusb302.c'
grep -Fq 'start unattached SRC toggling' "${patch_path}"

bash -n \
    "${script_dir}/build-test-kernel.sh" \
    "${script_dir}/preflight-test-kernel-build.sh"

printf 'Static kernel-build preflight passed\n'

if [[ ${network_check} == yes ]]; then
    case ${LINUX_REPOSITORY} in
        https://github.com/*.git) ;;
        *) printf 'Unsupported Linux repository for exact-source preflight: %s\n' \
               "${LINUX_REPOSITORY}" >&2; exit 2 ;;
    esac

    linux_slug=${LINUX_REPOSITORY#https://github.com/}
    linux_slug=${linux_slug%.git}
    source_path=drivers/usb/typec/tcpm/fusb302.c
    source_url="https://raw.githubusercontent.com/${linux_slug}/${LINUX_COMMIT}/${source_path}"
    preflight_root=$(mktemp -d)
    trap 'rm -rf "${preflight_root}"' EXIT
    install -D -m 0644 /dev/null "${preflight_root}/${source_path}"
    curl --fail --silent --show-error --location \
        --retry 3 --retry-all-errors \
        --output "${preflight_root}/${source_path}" "${source_url}"
    git -C "${preflight_root}" init --quiet
    git -C "${preflight_root}" add "${source_path}"
    git -C "${preflight_root}" apply --check "${patch_path}"
    rm -rf "${preflight_root}"
    trap - EXIT
    printf 'Patch applies to the exact pinned Linux source\n'
fi
