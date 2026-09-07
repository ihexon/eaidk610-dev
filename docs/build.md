# Build and release

## Build inputs

| Location | Purpose |
| --- | --- |
| `armbian/` | Official Armbian build framework, pinned as a Git submodule |
| `config/image.env` | Image, kernel series, and U-Boot settings |
| `userpatches/config/boards/` | EAIDK610 board definition |
| `userpatches/kernel/archive/rockchip64-7.2/` | Project kernel patches |
| `userpatches/overlay/boot/overlay-user/` | Board overlay source |
| `packaging/eaidk610-board-overlays/` | Board package metadata and installation hook |
| `scripts/` | Packaging, build, and image validation |

The framework is pinned by the submodule commit. Each build resolves the Linux
7.2 stable branch to a commit before compilation. Exact source revisions and
patch checksums are recorded in `BUILD-MANIFEST.txt`.

## GitHub Actions

The manual **Build and release EAIDK610 Armbian image** workflow accepts a new
release tag such as `eaidk610-armbian-edge-r5`.

It runs on `ubuntu-24.04-arm`, using Armbian's ARM64 Docker environment and one
standard `compile.sh build` invocation. Armbian prepares sources, applies its
Rockchip patches and project patches, and builds U-Boot, the kernel packages,
and the root filesystem.

The board package is installed during image customization. Image validation
covers the bootloader area, partition layout, kernel/modules, board DTB, and
enabled overlay. The image is compressed with XZ and published together with
the kernel DEBs and board package. Failure diagnostics are retained for one day.

## Boot configuration

The complete image uses Armbian's standard boot script and `armbianEnv.txt`.
The board package enables `rk3399-eaidk-610-typec-fix` in `user_overlays`.

An existing extlinux installation must reference the same overlay in its
selected boot entry:

```text
FDTOVERLAYS /boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo
```

The board package does not rewrite existing extlinux entries. Changes to the
kernel or boot-time device tree take effect after a reboot.
