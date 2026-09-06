# EAIDK610 U-Boot patch set

The board currently uses unmodified upstream U-Boot `v2026.10-rc3` with
`eaidk-610-rk3399_defconfig`. That exact version has already booted the board
from eMMC.

Add future U-Boot changes here as numbered `*.patch` files. Armbian will apply
this directory because the EAIDK610 board definition sets
`BOOTPATCHDIR=eaidk610-v2026.10-rc3`.
