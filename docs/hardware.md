# Hardware support

Target: OPEN AI LAB EAIDK-610, Rockchip RK3399, 4 GiB RAM, eMMC.

## Board fixes

| Component | Configuration |
| --- | --- |
| FUSB302 | Detects unattached Source connections through fixed-source toggling |
| Type-C | Dual role, Source preference, 5 V / 1.5 A advertisement; PD and DisplayPort disabled |
| USB3 Type-C PHY | `tcphy0` receives role and orientation through the Type-C extcon bridge |
| Headphone detection | simple-audio-card, GPIO4_D4, active high |
| Speaker amplifier | simple-audio-amplifier, GPIO0_B3, active high, powered by VCC5V0_SYS |
| RT5651 | Correct `micbias1` audio route; skips requesting an unwired codec interrupt |
| Serial console | UART2, 1500000 baud, 8N1, with device-tree `stdout-path` |
| Bluetooth | Board-specific alias to the BCM4345C0 firmware supplied by `armbian-firmware` |

Device-tree changes reside in the single `rk3399-eaidk-610-typec-fix` overlay.
The upstream base DTB remains unchanged. The board package owns the compiled
overlay and firmware alias.

## Validation coverage

| Area | Verified scope |
| --- | --- |
| Image | Automated bootloader, partition, kernel/modules, DTB, and overlay validation |
| Boot | U-Boot and Linux boot from eMMC; Ethernet and serial console available |
| Type-C USB2 | Linux 7.1.8: automatic Source/Host and 480 Mbps enumeration with a reverse-connected OnePlus 8T |
| USB3 Type-C | PHY/extcon wiring verified; SuperSpeed transfers in both orientations not yet qualified |
| Audio | Linux 7.2.3 with board package 1.0.1: card registration and a 48 kHz stereo silent PCM playback test |
| Bluetooth | Board package 1.0.1: firmware patch build 0230 loads successfully |

Audio registration and silent PCM playback do not establish audible output,
microphone capture quality, or headphone insertion/removal behavior. Bluetooth
pairing and data transfer are not covered by the firmware-loading check.
Type-C coverage does not establish repeated hotplug reliability, Sink/Device
operation, or sustained 1.5 A delivery. The 1.5 A value is a CC advertisement,
not a measured continuous-load rating.
