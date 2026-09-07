# Build and release

## Build inputs

| Location | Purpose |
| --- | --- |
| `compile.sh`, `lib/` | Armbian's native build entry point and implementation |
| `config/boards/eaidk610.csc` | Board definition, extlinux settings, and BSP/image hooks |
| `config/optional/boards/eaidk610/_packages/bsp-cli/` | Board overlay source, included in native BSP assets and cache hashing |
| `patch/kernel/archive/rockchip64-7.2/` | Armbian Rockchip patches and EAIDK610 fixes |
| `patch/u-boot/eaidk610-v2026.10-rc3/` | Board-selected U-Boot patch directory; currently no patches |
| `tools/eaidk610/` | Release defaults, lightweight preflight, image validation, and release collection |

The framework is maintained directly in this repository. Each release build
resolves the Linux 7.2 stable branch to a commit before compilation. Exact source revisions and
patch checksums are recorded in `BUILD-MANIFEST.txt`.

EAIDK610 is a built-in community-supported board (`.csc`). Its native build
interface is:

```sh
./compile.sh build BOARD=eaidk610 BRANCH=edge RELEASE=trixie BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no EXTRAWIFI=no
```

No populated `userpatches/` directory or project wrapper is required for board
support. The release helper adds artifact collection and validation to this
same build path; it does not provide a separate compiler or packager.

## GitHub Actions

The manual **Build and release EAIDK610 Armbian image** workflow accepts a new
release tag such as `eaidk610-armbian-edge-r5`.

It runs on `ubuntu-24.04-arm`, using Armbian's ARM64 Docker environment and one
standard `compile.sh build` invocation. Armbian prepares sources, applies its
Rockchip patches and project patches, and builds U-Boot, the kernel packages,
and the root filesystem.

The native `armbian-bsp-cli-eaidk610-edge` package contains the compiled overlay
and Bluetooth firmware alias and is installed by Armbian. Image validation
covers the bootloader area, partition layout, kernel/modules, board DTB, and
enabled overlay. The image is compressed with XZ and published together with
the kernel DEBs and board package. Failure diagnostics are retained for one day.

## Boot configuration

The complete image uses Armbian's native extlinux support (`SRC_EXTLINUX=yes`)
with one entry in `/boot/extlinux/extlinux.conf` and no recovery entry.
It does not use `boot.cmd`, `boot.scr`, or `armbianEnv.txt`.

Armbian generates the kernel, initrd, and base DTB paths and the root filesystem
UUID. The board's image hook adds `rk3399-eaidk-610-typec-fix.dtbo` through
`fdtoverlays`. The entry uses Armbian's
stable `/boot/Image`, `/boot/uInitrd`, and `/boot/dtb/` links.

Boot arguments are maintained in the board definition: display console `tty1`,
serial console `ttyS2` at 1500000 baud, `loglevel=8`, `earlycon`, and
`systemd.show_status=yes`, without quiet or splash. Systemd log targets and rate
limits remain unchanged. Status prompts use the primary serial console and are
not mirrored. The earliest boot output requires serial until the display console
is initialized.

Installing the BSP DEB alone does not migrate an existing system to extlinux
or rewrite its extlinux entries. Existing entries must reference the overlay:

```text
FDTOVERLAYS /boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo
```

The BSP package does not rewrite existing extlinux entries. Changes to the
kernel or boot-time device tree take effect after a reboot.
