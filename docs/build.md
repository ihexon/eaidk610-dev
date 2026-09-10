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
the kernel, U-Boot and board DEBs. Failure diagnostics are retained for one day.

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

Console autologin is disabled (`CONSOLE_AUTOLOGIN=no`) on both serial and
display consoles. Armbian's first-login setup remains enabled and starts after
an interactive root login. This build-time default does not modify existing
installations or previously released images.

### Existing-system conversion

The BSP includes `eaidk610-boot-setup`. Initial conversion is explicit; installing
the BSP does not take over an unmanaged boot configuration. Conversion selects
the EAIDK610 DTB and overlay, generates a single extlinux entry, and uses the
target root UUID. The extlinux entry is replaced atomically, then obsolete
`boot.cmd`, `boot.scr`, and `armbianEnv.txt` files are removed on first conversion.
No backup, rollback, recovery kernel, or recovery boot entry is provided.

The interface accepts `--root DIR` for a mounted offline installation,
`--root-uuid UUID`, `--extra-args TEXT`, and `--install-uboot DEVICE`.
`--help` describes usage. The kernel, DTB and BSP must already be installed in
the target; its separate `/boot`, if present, must be mounted too. This is not
a package installer or a disk-image writer.

Supported storage is a plain ext4 root partition and an optional ext4/FAT boot
partition. ARM64 Armbian Trixie is the reference system; other distribution
versions, encrypted roots, LVM, and Btrfs layouts are not qualified. Different
boards' images are not universally interchangeable. Offline package installation
still requires a suitable ARM64 chroot environment, independently of this tool.

`/etc/eaidk610/boot-managed` records explicit ownership of the entry. New project
images also carry this marker. BSP upgrades refresh managed entries using the
board definition's packaged defaults, preserving their root UUID and additional
arguments while replacing board-owned arguments. Removing the marker opts out
of automatic refresh. Custom extra arguments may be edited in `append` or passed
with `--extra-args`; board-owned console/logging arguments remain authoritative.

The native `linux-u-boot-eaidk610-edge` DEB supplies firmware from the same build.
The setup tool flashes it only with `--install-uboot DEVICE`, using an explicit
whole disk, checking 512-byte sectors and partition boundaries before writing
the binman image at byte 32768. It never infers the boot disk from the root disk.
Errors stop the operation but do not undo completed steps. In particular, a
failed or interrupted firmware write may leave the board unable to boot and
require external recovery media. Atomic extlinux replacement does not make the
entire conversion or firmware write power-loss-safe.
Storage layouts without room for the firmware require a different image/layout;
the tool does not resize partitions. EAIDK610's native U-Boot packaging hook
disables automatic flashing, including on systems that previously enabled
Armbian's `FORCE_UBOOT_UPDATE` mechanism.

EAIDK610's BSP depends on `base-files` without tying its version to Armbian's
branding release. Other boards retain the upstream version constraint. The BSP
declares its kernel, DTB, firmware and audio runtime dependencies, and conflicts
with other native BSP providers so apt can replace them without forced file
overwrites. The historical `eaidk610-board-overlays` package must still be
removed explicitly before BSP installation. Existing ALSA state is preserved;
board defaults are installed only when no saved state exists.

Fixture tests cover conversion, refresh, root/boot paths, user arguments,
incomplete installations and firmware write bounds. Real-board migration and
firmware flashing with this tool are not yet hardware-validated. Changes to the
kernel or boot-time device tree take effect after a reboot; the tool never
reboots automatically.
