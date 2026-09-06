# EAIDK610 Armbian image

This repository builds a directly bootable Armbian image for the OPEN AI LAB
EAIDK-610 (RK3399). The upstream Armbian build framework is pinned as the
`armbian/` submodule; all project-owned changes stay outside that submodule in
the standard `userpatches/` layout.

The active image uses:

- Armbian `edge` for `rockchip64` (7.2 at the pinned framework revision);
- the full Armbian Rockchip patch stack plus our focused FUSB302 patch;
- upstream U-Boot `v2026.10-rc3`, its mainline TPL/SPL and Rockchip BL31 v1.36;
- the upstream `rk3399-eaidk-610.dtb` plus a project-owned board overlay for
  Type-C, USB3 PHY orientation and analog audio GPIOs;
- Debian Trixie Minimal userspace.

## Repository layout

```text
armbian/                 pinned armbian/build submodule
config/image.env         auditable image inputs
userpatches/             board, kernel, U-Boot and image customization
scripts/                 preflight, build and image validation
scripts/board/           deployment and hardware-check helpers
docs/                    investigation, history and releases
archive/kernel-r1/       preserved 7.1 kernel-only workflow
local/                   ignored binaries, logs and prior local artifacts
references/              ignored vendor PDF references
```

## Build and release

The manual GitHub Actions workflow runs on ARM64. It validates cheap failure
conditions before invoking Armbian, then mounts the completed image read-only
and verifies its bootloader, kernel, modules, DTB, enabled overlay and merged
Type-C/USB3/audio properties before creating a GitHub pre-release.

```sh
git submodule update --init --recursive
scripts/preflight-image-build.sh
gh workflow run build-armbian-image.yml \
  --repo ihexon/eaidk610-dev \
  --ref main \
  -f release_tag=eaidk610-armbian-edge-r2
```

The workflow never connects to a board or flashes eMMC. Hardware deployment is
a separate explicit operation after offline image checks pass. The archived
7.1 kernel-only pipeline is retained for traceability but is not run by the
active image workflow; the complete image build compiles or obtains each
Armbian artifact only once.
