# EAIDK610 Armbian

Armbian images and kernel packages for the OPEN AI LAB EAIDK-610 (RK3399).
The project uses the official Armbian build framework with a small set of
board-specific kernel patches and a device-tree overlay.

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
| `eaidk610-board-overlays.deb` | Board overlay and Bluetooth firmware alias |
| `SHA256SUMS`, `BUILD-MANIFEST.txt` | Download checksums and build provenance |

The full image includes the board package and enables its overlay by default.
Releases are marked as pre-releases while hardware coverage remains limited.

## System

- Debian Trixie Minimal, ARM64.
- Armbian rockchip64 edge, Linux 7.2 stable series.
- Upstream U-Boot `v2026.10-rc3`, mainline TPL/SPL, and Rockchip BL31 v1.36.
- EAIDK610 fixes for Type-C role switching, USB3 PHY orientation, RT5651 audio,
  serial console initialization, and Bluetooth firmware lookup.

## Documentation

- [Build and release](docs/build.md)
- [Hardware support](docs/hardware.md)

Report problems through [GitHub Issues](https://github.com/ihexon/eaidk610-dev/issues)
with the release tag, kernel version, relevant kernel messages, and connected
hardware. Remove credentials and private machine details from logs.
