#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
# shellcheck source=../config/image.env
source "${repo_root}/config/image.env"

case ${1:-} in
	'') network_check=no ;;
	--network) network_check=yes ;;
	*) printf 'usage: %s [--network]\n' "$0" >&2; exit 2 ;;
esac

fail() {
	printf 'preflight: %s\n' "$*" >&2
	exit 2
}

[[ ${ARMBIAN_BUILD_COMMIT} =~ ^[0-9a-f]{40}$ ]] || fail 'invalid Armbian commit'
[[ ${ARMBIAN_UBOOT_COMMIT} =~ ^[0-9a-f]{40}$ ]] || fail 'invalid U-Boot commit'
[[ ${ARMBIAN_KERNEL_SERIES} == 7.2 ]] || fail 'unexpected edge series'

actual_submodule=$(git -C "${repo_root}/armbian" rev-parse HEAD)
[[ ${actual_submodule} == "${ARMBIAN_BUILD_COMMIT}" ]] || fail 'Armbian submodule is not pinned to image.env'
[[ -z $(git -C "${repo_root}/armbian" status --short) ]] || fail 'Armbian submodule is dirty'
grep -Fq 'url = https://github.com/armbian/build.git' "${repo_root}/.gitmodules"

board_file="${repo_root}/userpatches/config/boards/${ARMBIAN_BOARD}.csc"
[[ -f ${board_file} ]] || fail 'EAIDK610 board definition is missing'
grep -Fqx 'BOOTCONFIG="eaidk-610-rk3399_defconfig"' "${board_file}"
grep -Fqx 'BOOT_FDT_FILE="rockchip/rk3399-eaidk-610.dtb"' "${board_file}"
grep -Fqx "BOOTBRANCH_BOARD=\"tag:${ARMBIAN_UBOOT_TAG}\"" "${board_file}"
grep -Fqx 'BL31_BLOB="rk33/rk3399_bl31_v1.36.elf"' "${board_file}"
grep -Fqx 'BOOT_SCENARIO="binman"' "${board_file}"

common_inc="${repo_root}/armbian/config/sources/families/include/rockchip64_common.inc"
edge_config=$(sed -n '/^[[:space:]]*edge)/,/;;/p' "${common_inc}")
grep -Fq "KERNEL_MAJOR_MINOR=\"${ARMBIAN_KERNEL_SERIES}\"" <<< "${edge_config}"
grep -Fq 'UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"' \
	"${common_inc}"
grep -Fq 'dd if=$1/u-boot-rockchip.bin of=$2 bs=32k seek=1 conv=notrunc status=none' \
	"${common_inc}"
kernel_config="${repo_root}/armbian/config/kernel/linux-rockchip64-edge.config"
for symbol in CONFIG_TYPEC_TCPM=y CONFIG_TYPEC_FUSB302=y CONFIG_TYPEC_EXTCON=m; do
	grep -Fqx "${symbol}" "${kernel_config}" || fail "missing ${symbol}"
done

patch_path="${repo_root}/${KERNEL_PATCH}"
overlay_source="${repo_root}/${TYPEC_OVERLAY_SOURCE}"
printf '%s  %s\n' "${KERNEL_PATCH_SHA256}" "${patch_path}" | sha256sum --check --status
printf '%s  %s\n' "${TYPEC_OVERLAY_SOURCE_SHA256}" "${overlay_source}" | sha256sum --check --status
git apply --numstat "${patch_path}" | grep -Fq $'drivers/usb/typec/tcpm/fusb302.c'
[[ -d ${repo_root}/userpatches/u-boot/eaidk610-v2026.10-rc3 ]]

command -v dtc >/dev/null || fail 'device-tree-compiler is required'
overlay_check=$(mktemp /tmp/eaidk610-overlay.XXXXXX.dtbo)
dtc -q -@ -I dts -O dtb -o "${overlay_check}" "${overlay_source}"
dtc -q -I dtb -O dts -o /dev/null "${overlay_check}"

customizer_root=$(mktemp -d /tmp/eaidk610-customizer.XXXXXX)
install -D -m 0644 "${overlay_source}" \
	"${customizer_root}/tmp/overlay/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dts"
install -D -m 0644 "${overlay_check}" \
	"${customizer_root}/tmp/overlay/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo"
install -D -m 0644 /dev/null "${customizer_root}/boot/armbianEnv.txt"
printf 'fdtfile=rockchip/rk3399-eaidk-610.dtb\nuser_overlays=obsolete\n' \
	> "${customizer_root}/boot/armbianEnv.txt"
EAIDK610_ROOT_PREFIX=${customizer_root} "${repo_root}/userpatches/customize-image.sh" \
	"${ARMBIAN_RELEASE}" rockchip64 "${ARMBIAN_BOARD}" no arm64
grep -Fqx "user_overlays=${TYPEC_OVERLAY_NAME}" \
	"${customizer_root}/boot/armbianEnv.txt"
[[ -s ${customizer_root}/boot/overlay-user/${TYPEC_OVERLAY_NAME}.dtbo ]]

bash -n "${repo_root}/scripts/build-image.sh" \
	"${repo_root}/scripts/validate-image.sh" \
	"${repo_root}/userpatches/customize-image.sh"

if [[ ${network_check} == yes ]]; then
	read -r stable_linux_commit _ < <(git ls-remote \
		https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
		"refs/heads/linux-${ARMBIAN_KERNEL_SERIES}.y")
	read -r mirror_linux_commit _ < <(git ls-remote https://github.com/gregkh/linux.git \
		"refs/heads/linux-${ARMBIAN_KERNEL_SERIES}.y")
	[[ ${stable_linux_commit} == "${mirror_linux_commit}" ]] || fail 'stable Linux mirror is not synchronized'
	linux_commit=${EAIDK610_EDGE_LINUX_COMMIT:-${stable_linux_commit}}
	[[ ${linux_commit} == "${stable_linux_commit}" ]] || fail 'requested edge Linux commit is no longer branch head'
	[[ ${linux_commit} =~ ^[0-9a-f]{40}$ ]] || fail 'cannot resolve edge Linux head'
	check_root=$(mktemp -d /tmp/eaidk610-edge-check.XXXXXX)
	source_file=drivers/usb/typec/tcpm/fusb302.c
	install -D -m 0644 /dev/null "${check_root}/${source_file}"
	curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
		--output "${check_root}/${source_file}" \
		"https://raw.githubusercontent.com/gregkh/linux/${linux_commit}/${source_file}"
	git -C "${check_root}" init --quiet
	git -C "${check_root}" add "${source_file}"
	git -C "${check_root}" apply --check "${patch_path}"

	uboot_config_url="https://raw.githubusercontent.com/u-boot/u-boot/${ARMBIAN_UBOOT_COMMIT}/configs/eaidk-610-rk3399_defconfig"
	uboot_config=$(mktemp /tmp/eaidk610-uboot-defconfig.XXXXXX)
	curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
		--output "${uboot_config}" "${uboot_config_url}"
	grep -Fqx 'CONFIG_DEFAULT_FDT_FILE="rockchip/rk3399-eaidk-610.dtb"' "${uboot_config}"
	grep -Fqx 'CONFIG_TPL=y' "${uboot_config}"
	resolved_uboot=$(git ls-remote https://github.com/u-boot/u-boot.git \
		"refs/tags/${ARMBIAN_UBOOT_TAG}^{}" | awk '{print $1}')
	[[ ${resolved_uboot} == "${ARMBIAN_UBOOT_COMMIT}" ]] || fail 'U-Boot tag moved or is unavailable'
	bl31_url=https://raw.githubusercontent.com/armbian/rkbin/master/rk33/rk3399_bl31_v1.36.elf
	bl31_file=$(mktemp /tmp/rk3399-bl31-v1.36.XXXXXX.elf)
	curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
		--output "${bl31_file}" "${bl31_url}"
	printf '%s  %s\n' 3be6cdf32462d7f676d109bb2a97af9a1f469f058674ef0a5cb20941af2923d5 \
		"${bl31_file}" | sha256sum --check --status

	armbian_userpatches="${repo_root}/armbian/userpatches"
	if [[ -e ${armbian_userpatches} && ! -d ${armbian_userpatches} ]]; then
		fail 'armbian/userpatches exists but is not a directory'
	fi
	install -d "${armbian_userpatches}"
	cp -a "${repo_root}/userpatches/." "${armbian_userpatches}/"
	diff -qr "${repo_root}/userpatches" "${armbian_userpatches}"
	install -d "${repo_root}/artifacts/diagnostics"
	config_dump_raw="${repo_root}/artifacts/diagnostics/preflight-config-dump.raw.log"
	config_dump=$(mktemp /tmp/eaidk610-configdump.XXXXXX.json)
	CONFIG_DEFS_ONLY=yes "${repo_root}/armbian/compile.sh" config-dump \
		BOARD="${ARMBIAN_BOARD}" BRANCH="${ARMBIAN_BRANCH}" \
		RELEASE="${ARMBIAN_RELEASE}" BUILD_MINIMAL="${ARMBIAN_BUILD_MINIMAL}" \
		BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
		KERNELBRANCH="commit:${linux_commit}" EXTRAWIFI=no \
		COMPRESS_OUTPUTIMAGE=sha,img ARTIFACT_IGNORE_CACHE=yes SHARE_LOG=no \
		> "${config_dump_raw}"
	# Armbian emits GitHub workflow commands on stdout under Actions. Keep the
	# raw stream for diagnostics and select only its one configuration object.
	jq -R -c \
		'fromjson? | select(type == "object" and has("KERNEL_MAJOR_MINOR"))' \
		"${config_dump_raw}" > "${config_dump}"
	[[ $(wc -l < "${config_dump}") -eq 1 ]] || fail 'config-dump did not emit exactly one configuration object'
	jq -e --arg series "${ARMBIAN_KERNEL_SERIES}" \
		--arg kernel_commit "commit:${linux_commit}" \
		--arg tag "tag:${ARMBIAN_UBOOT_TAG}" '
		.KERNEL_MAJOR_MINOR == $series and
		.KERNELPATCHDIR == ("archive/rockchip64-" + $series) and
		(.WANT_ARTIFACT_KERNEL_INPUTS_ARRAY |
			index("\u0027KERNELBRANCH=" + $kernel_commit + "\u0027") != null) and
		(.WANT_ARTIFACT_KERNEL_INPUTS_ARRAY | index("\u0027EXTRAWIFI=no\u0027") != null) and
		.BOOTCONFIG == "eaidk-610-rk3399_defconfig" and
		.BOOTBRANCH == $tag and
		.BOOTPATCHDIR == "eaidk610-v2026.10-rc3" and
		.BOOT_SCENARIO == "binman" and
		(.UBOOT_TARGET_MAP | endswith(";;u-boot-rockchip.bin")) and
		.BL31_BLOB == "rk33/rk3399_bl31_v1.36.elf" and
		.BOOT_FDT_FILE == "rockchip/rk3399-eaidk-610.dtb" and
		(.WANT_ARTIFACT_ALL_NAMES_ARRAY | index("uboot") != null) and
		(.WANT_ARTIFACT_ALL_NAMES_ARRAY | index("kernel") != null) and
		(.WANT_ARTIFACT_ALL_NAMES_ARRAY | index("rootfs") != null)
	' "${config_dump}" >/dev/null
	printf 'edge_linux_commit=%s\n' "${linux_commit}"
fi

printf 'EAIDK610_IMAGE_PREFLIGHT_OK\n'
