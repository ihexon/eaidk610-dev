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
| RT5651 | Headset microphone on IN3P; onboard microphone on differential IN2P/IN2N; both use `micbias1`; skips requesting an unwired codec interrupt |
| HDMI | Separate VCCA0V9_S3 and VCCA1V8_S3 analog supplies; existing I2S2 HDMI sound card enabled |
| SARADC | Reference supply connected to analog VCCA1V8_S3, separate from digital VCC1V8_S3 |
| SD card | GPIO0_A1-controlled 3.0 V card supply; RK808 VCC_SDIO supplies bus I/O; UHS SDR50/SDR104 enabled with the existing 150 MHz limit |
| eMMC | Base device-tree configuration retained; no eMMC overrides in the board overlay |
| Serial console | UART2, 1500000 baud, 8N1, with device-tree `stdout-path` |
| Image boot logs | Native extlinux; serial and display kernel consoles, loglevel 8, earlycon enabled, systemd startup status shown; default systemd log routing retained |
| Bluetooth | Board-specific alias to the BCM4345C0 firmware supplied by `armbian-firmware` |

Device-tree changes reside in the single `rk3399-eaidk-610-typec-fix` overlay.
The upstream base DTB remains unchanged. Armbian's native EAIDK610 BSP package
owns the compiled overlay and firmware alias. Overlay contents retain the
board fixes from standalone package 1.0.3.

## Validation coverage

| Area | Verified scope |
| --- | --- |
| Image | Automated bootloader, partition, kernel/modules, DTB, and overlay validation |
| Boot | U-Boot and Linux boot from eMMC; Ethernet and serial console available |
| Native BSP/extlinux image | Native board hooks pass local preflight; complete image build and board boot validation pending |
| Type-C USB2 | Linux 7.1.8: automatic Source/Host and 480 Mbps enumeration with a reverse-connected OnePlus 8T |
| USB3 Type-C | PHY/extcon wiring verified; SuperSpeed transfers in both orientations not yet qualified |
| Audio | Linux 7.2.3 with board package 1.0.1: card registration and a 48 kHz stereo silent PCM playback test |
| Bluetooth | Board package 1.0.1: firmware patch build 0230 loads successfully |
| Storage baseline | Linux 7.2.3 with board package 1.0.1: eMMC operates at HS200, 200 MHz, 8-bit, 1.8 V; SD operates at 50 MHz High Speed |
| Board package 1.0.3 | Microphone routing, HDMI/ADC supply topology, HDMI audio enablement, and SD descriptions checked against the schematic; eMMC node unchanged from the base DTB; hardware qualification pending |

Audio registration and silent PCM playback do not establish audible output,
microphone capture quality, or headphone insertion/removal behavior. Enabling
HDMI audio may change ALSA card numbering. Bluetooth
pairing and data transfer are not covered by the firmware-loading check.
Type-C coverage does not establish repeated hotplug reliability, Sink/Device
operation, or sustained 1.5 A delivery. The 1.5 A value is a CC advertisement,
not a measured continuous-load rating.

HDMI supply descriptions do not establish the cause of intermittent display
failures. HDMI output/audio, microphone capture, SD power cycling, and suspend/
resume with board package 1.0.3 are not yet hardware-qualified. SD UHS
throughput and sustained read/write reliability are unqualified. Advertised
capability does not guarantee stable operation at the highest speed. External
panel configurations are not enabled by this overlay.
