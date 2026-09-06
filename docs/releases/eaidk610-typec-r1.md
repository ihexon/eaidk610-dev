# EAIDK610 Type-C kernel r1

This is a test pre-release for the EAIDK610 Type-C automatic-role fix. It was
built by the pinned Armbian build framework with the standard
`./compile.sh kernel` command on GitHub's native ARM64 runner.

## Build provenance

- Kernel release: `7.1.8-edge-rockchip64-eaidk610-typec-r1`
- Build source commit: `4d82288ca488720b95e739e903054b651ec8be2b`
- GitHub Actions run: [34017439800](https://github.com/ihexon/eaidk610-dev/actions/runs/34017439800)
- Armbian build commit: `fd4ebfd1e107d5b89f7a672c7d609789565753b2`
- Linux commit: `25c76bea853d0db65b51fb4697a47cbfd9e35e76`
- Package version and architecture: `26.08.0-trunk`, `arm64`

The run completed successfully. Its log records the local FUSB302 patch as
patch `001/228`, compilation of `drivers/usb/typec/tcpm/fusb302.o`, 2217 seconds
for the kernel build, and 54 seconds for Armbian packaging. The downloaded
artifact passed its complete `SHA256SUMS` check and package-content validation.

## Assets

- Four unmodified Armbian packages: image, DTB, headers, and libc-dev.
- `eaidk610-typec-r1-arm64-artifact.tar.zst`: the complete Actions artifact,
  preserving its original directory layout and internal checksums.
- `install-eaidk610-typec-r1.sh`: guarded installer for the image and DTB
  packages. It validates their exact release hashes, preserves the old kernel,
  prepares the matching U-Boot initramfs, and stops before reboot.
- `SHA256SUMS-release`: checksums for the downloadable release assets.

For installation, download the installer plus the image and DTB packages into
one directory on the EAIDK610, then run the installer as root with that
directory as its argument. Review its `PRE_REBOOT_OK` result and recovery
backup before rebooting. The existing
`/boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo` is required.

## Test status

The kernel has booted successfully on the target board. With a OnePlus 8T
connected in reverse orientation, `port_type=dual` automatically reached
Source/Host, enumerated at USB2 480 Mbps, and the FUSB302/TCPM debug log proved
the repaired Rd-detection path executed.

This remains a pre-release because the full forward/reverse repeated-plug,
disconnect/VBUS, computer Sink/Device, file-transfer, and USB3 regression matrix
is not yet complete. Keep the original kernel and serial/offline recovery path
available.
