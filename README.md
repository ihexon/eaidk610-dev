# EAIDK610 Armbian

Armbian images and kernel packages for the OPEN AI LAB EAIDK-610 (RK3399).
This repository is derived from the Armbian build framework and adds native
EAIDK610 board support. It contains the framework itself, not a submodule or an
external build wrapper. Board fixes use the standard kernel patch and BSP flows.

## Downloads

[GitHub Releases](https://github.com/ihexon/eaidk610-dev/releases) provide a
complete bootable image and the kernel packages produced by the same build.

| File | Contents |
| --- | --- |
| `eaidk610-armbian-edge.img.xz` | Complete Armbian image, including U-Boot |
| `linux-image-eaidk610-edge.deb` | Kernel and modules |
| `linux-dtb-eaidk610-edge.deb` | Device trees |
| `linux-headers-eaidk610-edge.deb` | Kernel headers |
| `linux-libc-dev-eaidk610-edge.deb` | Linux userspace API headers |
| `linux-u-boot-eaidk610-edge.deb` | EAIDK610 boot firmware; installation alone does not flash a disk |
| `armbian-bsp-eaidk610-edge.deb` | Native board support, overlay, `eaidk610-typec`, `eaidk610-boot-setup`, audio defaults, and Bluetooth firmware alias |
| `SHA256SUMS`, `BUILD-MANIFEST.txt` | Download checksums and build provenance |

The full image includes the board package and enables its overlay by default.
Releases are marked as pre-releases while hardware coverage remains limited.

The native BSP replaces the former standalone overlay package in new releases.
Existing systems must remove `eaidk610-board-overlays` before installing the new
BSP to avoid file ownership conflicts. Installing DEBs does not migrate their
boot configuration automatically. `eaidk610-boot-setup` explicitly converts an
installed system to extlinux; later BSP upgrades maintain the managed entry.
The tool supports ARM64 Armbian with a plain ext4 root partition and an optional
ext4/FAT boot partition. It can target a mounted offline system. It does not
repartition storage or reboot, and U-Boot flashing requires an explicit disk.
Migration hardware validation is pending; use the complete image for a new
installation. See [boot configuration](docs/build.md#boot-configuration).

## System

- Debian Trixie Minimal, ARM64.
- Armbian rockchip64 edge, Linux 7.2 stable series.
- Upstream U-Boot `v2026.10-rc3`, mainline TPL/SPL, and Rockchip BL31 v1.36.
- Native extlinux boot with one entry and the board overlay enabled by default.
- `eaidk610-typec` CLI for runtime role/policy control, included in the native BSP
  and installed in images by default; no background service required.
- EAIDK610 fixes for Type-C role switching, USB3 PHY orientation, RT5651 audio,
  HDMI supplies and audio, SD card supplies and UHS modes, serial console
  initialization, and Bluetooth firmware lookup.

## Documentation

- [Build and release](docs/build.md)
- [Hardware support](docs/hardware.md)

Based on [armbian/build](https://github.com/armbian/build), upstream commit
`66dbc7af2a77d52ccd3fe2156a55687622848ea3`. Upstream licensing and attribution
are retained in [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).

Report problems through [GitHub Issues](https://github.com/ihexon/eaidk610-dev/issues)
with the release tag, kernel version, relevant kernel messages, and connected
hardware. Remove credentials and private machine details from logs.
