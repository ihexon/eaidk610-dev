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
- `armbian/typec-test-localversion.sh`: gives the test kernel a release distinct
  from the board's known-good kernel.

Run the workflow from the repository's Actions page, or with:

```sh
gh workflow run typec-test-kernel.yml --repo ihexon/eaidk610-dev --ref main
```

The workflow only builds and uploads an artifact. It never connects to the
EAIDK610, edits `/boot`, installs packages, or reboots the board.
