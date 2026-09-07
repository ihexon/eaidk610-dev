# EAIDK610 U-Boot patch set

The board currently uses unmodified upstream U-Boot `v2026.10-rc3` with
`eaidk-610-rk3399_defconfig`. That exact version has already booted the board
from eMMC.

This directory is reserved for numbered `*.patch` files. The EAIDK610 board
definition selects it with
`BOOTPATCHDIR=eaidk610-v2026.10-rc3`.
