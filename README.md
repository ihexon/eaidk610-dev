# EAIDK610 Armbian image

This repository produces a directly bootable Armbian image for the OPEN AI LAB
EAIDK-610 (RK3399).

Current image composition:

- Armbian `rockchip64` edge, Linux 7.2 stable series;
- Debian Trixie Minimal;
- upstream U-Boot `v2026.10-rc3` with mainline TPL/SPL and Rockchip BL31 v1.36;
- the Armbian Rockchip patch stack, EAIDK610 FUSB302 Try.Source fix, and
  RT5651 optional-interrupt fix;
- upstream `rk3399-eaidk-610.dtb` plus one project-owned board overlay,
  installed and enabled by `eaidk610-board-overlays.deb`.

The overlay provides managed Type-C VBUS/role switching, RK3399 USB3 PHY
orientation through extcon, active-high GPIO4_D4 headphone detection, and an
active-high GPIO0_B3 simple speaker amplifier. The board package also fixes
RT5651 audio routes, the early serial console, and Bluetooth firmware lookup.

The active build uses the pinned `armbian/` submodule and project changes under
`userpatches/`. Linux 7.1 kernel-only r1 is retained only as a historical
release record.

Each release contains `eaidk610-armbian-edge.img.xz`, the image, DTB, headers,
and libc-dev kernel DEBs, plus `eaidk610-board-overlays.deb`. Exact Armbian,
Linux, U-Boot, patch, and overlay provenance is recorded in
`BUILD-MANIFEST.txt`.

The FUSB302 repair has passed an initial USB2 reverse-orientation board test.
The complete Linux 7.2 image and merged device tree have passed offline
validation. USB3 in both orientations, headphone events, and speaker playback
still require hardware validation.
Board package 1.0.1 has passed a reboot test on `.177`: the RT5651 card
registers, earlycon initializes, and the Bluetooth firmware patch loads.
