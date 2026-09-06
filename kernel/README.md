# EAIDK610 Type-C test kernel

This directory contains the fixed inputs for the first FUSB302 Try.Source test
kernel. Full compilation is intentionally performed only by the manual GitHub
Actions workflow on an ARM64 runner. The Armbian framework may launch its ARM64
build container on that runner; it does not use the local development container
or the EAIDK610 board for compilation.

Inputs:

- `build.env`: immutable Armbian/Linux commits and the expected kernel release.
- `config-7.1.8-edge-rockchip64`: configuration copied from the test board.
- `patches/`: the focused FUSB302 repair patch.
- `armbian/rockchip64-family.conf`: gives the test kernel a distinct Armbian
  family so its kernel release, module directory and Debian package paths agree.

Before any expensive build, the workflow runs
`scripts/preflight-test-kernel-build.sh`. It verifies the pinned input hashes,
the family/release relationship, required Type-C configuration, and patch
syntax.
The workflow then runs the `--network` variant to check that the patch applies
to `fusb302.c` from the exact pinned Linux commit before starting Armbian.
Run the same check locally after changing any build input:

```sh
scripts/preflight-test-kernel-build.sh
```

When an input changes intentionally, update its SHA-256 in `build.env` in the
same commit. Once Armbian returns successfully, the build script writes
`KERNEL-BUILD-SUCCEEDED.txt` and copies Armbian's original packages without
extracting or repackaging them. The only post-build checks inspect package
metadata and tar member names for the expected kernel release, module tree, and
EAIDK610 DTB. The same checks passed in green workflow run `34017439800`, and
its downloaded artifact was independently verified before release.

Run the workflow from the repository's Actions page, or with:

```sh
gh workflow run typec-test-kernel.yml --repo ihexon/eaidk610-dev --ref main
```

The workflow only builds and uploads an artifact. It never connects to the
EAIDK610, edits `/boot`, installs packages, or reboots the board.

The verified r1 packages are also published as the GitHub pre-release
`eaidk610-typec-r1`. It remains a pre-release until the complete plug-direction,
disconnect/VBUS, Sink/Device, and data-transfer regression matrix is finished.
The release contains all four native Armbian packages, a bundle preserving the
Actions artifact layout, release checksums, and the matching guarded installer.
