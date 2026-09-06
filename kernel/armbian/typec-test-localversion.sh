#!/usr/bin/env bash

# Keep the test kernel alongside the known-good 7.1.8-edge-rockchip64 kernel.
# The value is duplicated in kernel/build.env intentionally; the build script
# rejects a mismatch before invoking Armbian.
function custom_kernel_make_params__999_typec_test_localversion() {
	local index
	local replaced="no"
	local expected="LOCALVERSION=-edge-rockchip64-eaidk610-typec-r1"

	for index in "${!common_make_params_quoted[@]}"; do
		if [[ "${common_make_params_quoted[$index]}" == LOCALVERSION=* ]]; then
			common_make_params_quoted[$index]="${expected}"
			replaced="yes"
		fi
	done

	if [[ "${replaced}" != "yes" ]]; then
		exit_with_error "Unable to set the Type-C test kernel LOCALVERSION"
	fi
}
