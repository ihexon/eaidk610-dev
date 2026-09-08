#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tool="${repo_root}/config/optional/boards/eaidk610/_packages/bsp-cli/usr/bin/eaidk610-typec"
# Source the CLI to test its sysfs operations against regular fixture files.
# shellcheck source=/dev/null
source "${tool}"
test_tmp=$(mktemp -d /tmp/eaidk610-typec-test.XXXXXX)
trap 'rm -r -- "${test_tmp}"' EXIT
port=${test_tmp}/port0

expect_failure() {
	if (main "$@") > "${test_tmp}/error" 2>&1; then
		printf 'Expected command to fail: %s\n' "$*" >&2
		exit 1
	fi
}

# Help works without a board; missing hardware produces a clear error.
main --help >/dev/null
bash -s -- --help < "${tool}" >/dev/null
expect_failure status
grep -q 'port not found' "${test_tmp}/error"
mkdir "${port}"
printf 'source sink [dual]\n' > "${port}/port_type"
printf 'sink\n' > "${port}/preferred_role"
printf 'host [device]\n' > "${port}/data_role"
printf '[source] sink\n' > "${port}/power_role"
printf 'usb_power_delivery\n' > "${port}/power_operation_mode"
printf 'reverse\n' > "${port}/orientation"

# Do not present cached roles as an active connection.
output=$(main)
[[ ${output} == *'Connection: unattached'* && ${output} == *'Power role: none'* ]]
mkdir "${port}-partner"
output=$(main status)
[[ ${output} == *'Port type: dual'* && ${output} == *'Connection: attached'* ]]
[[ ${output} == *'Data role: device'* && ${output} == *'Power role: source'* ]]
[[ ${output} == *'Power mode: usb_power_delivery'* && ${output} == *'Orientation: reverse'* ]]

if (( EUID != 0 )); then
	expect_failure data host
	grep -q 'use sudo' "${test_tmp}/error"
	[[ $(cat "${port}/data_role") == 'host [device]' ]]
fi
# Only fixture writes bypass privilege checking; the installed CLI has no override.
require_root() { :; }

for value in source sink none; do
	main prefer "${value}" >/dev/null
	[[ $(cat "${port}/preferred_role") == "${value}" ]]
done
for value in host device; do
	main data "${value}" >/dev/null
	[[ $(cat "${port}/data_role") == "${value}" ]]
	[[ $(cat "${port}/power_role") == '[source] sink' ]]
done
for value in sink source; do
	main power "${value}" >/dev/null
	[[ $(cat "${port}/power_role") == "${value}" ]]
	[[ $(cat "${port}/data_role") == device ]]
done
for value in dual sink source; do
	main port "${value}" >/dev/null
	[[ $(cat "${port}/port_type") == "${value}" ]]
done
main auto >/dev/null
[[ $(cat "${port}/preferred_role") == sink && $(cat "${port}/port_type") == dual ]]

expect_failure status extra
expect_failure auto extra
expect_failure prefer host
expect_failure port device
expect_failure data source
expect_failure power host
expect_failure data
expect_failure data host extra
expect_failure voltage 9000
[[ $(cat "${port}/data_role") == device && $(cat "${port}/power_role") == source ]]

# Unsupported or failing writes must not report success or continue auto setup.
mv "${port}/power_role" "${test_tmp}/power-role"
expect_failure power sink
grep -q 'not supported' "${test_tmp}/error"
[[ ! -e ${port}/power_role ]]
mv "${test_tmp}/power-role" "${port}/power_role"
rm -- "${port}/preferred_role"
mkdir "${port}/preferred_role"
printf 'source\n' > "${port}/port_type"
expect_failure auto
grep -q 'request failed' "${test_tmp}/error"
[[ $(cat "${port}/port_type") == source ]]

printf 'EAIDK610_TYPEC_TOOL_TEST_OK\n'
