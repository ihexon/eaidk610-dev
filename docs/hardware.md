# Hardware support

Target: OPEN AI LAB EAIDK-610, Rockchip RK3399, 4 GiB RAM, eMMC.

## Board fixes

| Component | Configuration |
| --- | --- |
| FUSB302 | Detects unattached Source connections through fixed-source toggling; ignores received Hard Reset status while PD reception is disabled |
| Type-C | Automatic dual role with Sink preference; fixed-5-V PD only: Source 1.8 A, Sink 100 mA interface budget; non-PD CC advertisement 1.5 A; DisplayPort disabled |
| Type-C userspace control | `eaidk610-typec`, supplied by the native BSP; connection status, automatic dual-role policy, role preference, and separate data/power role requests |
| USB3 Type-C PHY | `tcphy0` receives role and orientation through the Type-C extcon bridge |
| Headphone detection | simple-audio-card, GPIO4_D4, active high |
| Speaker amplifier | simple-audio-amplifier, GPIO0_B3, active high, powered by VCC5V0_SYS |
| RT5651 | Headset microphone on IN3P; onboard microphone on differential IN2P/IN2N; both use `micbias1`; skips requesting an unwired codec interrupt |
| HDMI | Separate VCCA0V9_S3 and VCCA1V8_S3 analog supplies; existing I2S2 HDMI sound card enabled |
| SARADC | Reference supply connected to analog VCCA1V8_S3, separate from digital VCC1V8_S3 |
| SD card | GPIO0_A1-controlled 3.0 V card supply; RK808 VCC_SDIO supplies bus I/O; UHS SDR50/SDR104 enabled with a 200 MHz limit |
| eMMC | HS400 at 1.8 V with internal PHY strobe pull-down; base supply and clock configuration retained; Enhanced Strobe not enabled |
| Serial console | UART2, 1500000 baud, 8N1, with device-tree `stdout-path` |
| Image boot logs | Native extlinux; serial and display kernel consoles, loglevel 8, earlycon enabled, systemd startup status shown; default systemd log routing retained |
| Bluetooth | Board-specific alias to the BCM4345C0 firmware supplied by `armbian-firmware` |

Device-tree changes reside in the single `rk3399-eaidk-610-typec-fix` overlay.
The upstream base DTB remains unchanged. Armbian's native EAIDK610 BSP package
owns the compiled overlay and firmware alias. Overlay contents retain the
board fixes from standalone package 1.0.3.

## Type-C power limits

The schematic's USB/USIC sheet 14 shows a fixed 5 V output path from
`VCC5V0_SYS` through U1420 (SY6280AAC) to the Type-C VBUS pins. There is no
supported Type-C input-power path to the system rails; the board uses a separate
12 V supply. A reported Sink role does not mean that USB powers the board.

The [SY6280](https://www.silergy.com/download/downloadFile?ftype=note&id=4369&type=product)
operates at 2.4–5.5 V and has a 6 V absolute maximum. R1466 (3.6 kOhm) sets a
nominal current limit of approximately 1.89 A, not a guaranteed continuous-load
rating. The datasheet specifies a 2 A load capability and advises against
setting the current limit above 2 A. High-voltage PD input/output and 3 A or 5 A
source advertisements are not supported by this power path.

The [FUSB302 controller family](https://www.onsemi.com/download/data-sheet/pdf/fusb302b-d.pdf)
provides PD communication. The overlay declares exactly one fixed 5 V PDO in
each direction: 1.8 A as Source and 100 mA as Sink. The 0.5 W Sink budget covers
the VBUS interface, not system power or battery charging; it is not a measured
consumption figure. TCPM also advertises 1.5 A over CC when sourcing without a
PD contract. No higher-voltage, PPS or EPR PDOs are configured. Data-role and
power-role swaps are advertised; interoperability remains subject to testing.
The 1.8 A Source setting has little margin below the nominal hardware current
limit and is not load-qualified; component tolerances may cause current limiting
before the advertised current is reached. Changing the PDO does not raise the
hardware current limit.

## Type-C userspace control

`eaidk610-typec` controls `/sys/class/typec/port0` through the standard Linux
Type-C ABI. Its commands are `status`, `auto`, `prefer`, `port`, `data`, and
`power`; the complete interface is described by `eaidk610-typec --help`.
Status is readable without root. Changes require root and affect runtime state
only; reboot restores the device-tree defaults. `auto` restores dual-role
policy with Sink preference, without forcing an existing PD connection to swap.

Data and power roles are independent. Requests can fail when the partner cannot
cooperate or the port is busy, and changing port type may interrupt USB traffic.
The tool does not configure gadget functions, alter PD voltage/current limits,
or add a background service. Native BSP asset hashing covers the tool together
with the overlay, and both are included in the standard image build.

## Validation coverage

| Area | Verified scope |
| --- | --- |
| Image | Automated bootloader, partition, kernel/modules, DTB, and overlay validation |
| Boot | U-Boot and Linux boot from eMMC; Ethernet and serial console available |
| Native BSP/extlinux image | r8 complete image build and automated image validation passed; native BSP DEBs installed and board reboot verified with extlinux. Fresh r8 image flashing not yet tested |
| Type-C USB2 | Linux 7.1.8: automatic Source/Host and 480 Mbps enumeration with a reverse-connected OnePlus 8T |
| Type-C role policy | Linux 7.2.4: dual role, Sink preference and PD disablement persist across reboot; PC reconnection selects Sink/Device; Source/Host fallback with an Rd partner observed, Host peripheral enumeration with this policy not yet qualified |
| USB3 Type-C Device | Linux 7.2.4 with persisted Sink preference: CDC ACM gadget reached configured state at SuperSpeed with a Windows PC in reverse orientation; sustained transfers and the other orientation not yet qualified |
| Fixed-5-V PD | r8 DEBs, Linux 7.2.4: reboot and live PDO registration verified; one attached partner negotiated a 5 V / 100 mA Sink contract, requested a Sink-to-Source power-role swap, then established a 5 V / 1.8 A Source contract; data role remained Device. Sustained output current and broader interoperability remain unqualified |
| Type-C userspace tool | Argument handling and sysfs fixture tests; read-only status on Linux 7.2.4. Userspace-requested role changes are not yet hardware-qualified |
| Audio | Linux 7.2.3 with board package 1.0.1: card registration and a 48 kHz stereo silent PCM playback test |
| Bluetooth | Board package 1.0.1: firmware patch build 0230 loads successfully |
| Storage baseline | Linux 7.2.3 with board package 1.0.1: eMMC operates at HS200, 200 MHz, 8-bit, 1.8 V; SD operates at 50 MHz High Speed |
| eMMC HS400 | Linux 7.2.3, AJTD4R eMMC: reboot from eMMC at 200 MHz, 8-bit, 1.8 V with CQE enabled; 512 MiB direct-I/O write/CRC32C readback passed, followed by a 12-second sequential read test; approximately 327 MiB/s read and 54 MiB/s write, with all MMC error counters zero |
| SD UHS | Linux 7.2.3, SN128 SD card: SDR104 at 200 MHz, 4-bit, 1.8 V; 512 MiB direct-I/O write/CRC32C readback passed, followed by a 12-second sequential read test; approximately 86 MiB/s read and 71 MiB/s write, with all MMC error counters zero |
| Board package 1.0.3 | Microphone routing, HDMI/ADC supply topology, HDMI audio enablement, and SD descriptions checked against the schematic; eMMC node unchanged from the base DTB; hardware qualification pending |

Audio registration and silent PCM playback do not establish audible output,
microphone capture quality, or headphone insertion/removal behavior. Enabling
HDMI audio may change ALSA card numbering. Bluetooth
pairing and data transfer are not covered by the firmware-loading check.
Type-C coverage does not establish repeated hotplug reliability, Host peripheral
enumeration with Sink preference, or sustained 1.5 A / 1.8 A delivery. The tested
earlier Linux 7.2.4 build entered Hard Reset / VBUS cycling on disconnect despite
PD being disabled. The received-Hard-Reset guard is included in the deployed r8
kernel; repeated-disconnect regression testing is still pending. USB gadget
functions such as serial, networking, MTP or ADB require separate configuration;
automatic role selection does not enable them. The 1.5 A CC and 1.8 A PD values
are advertisements, not measured continuous-load ratings.

HDMI supply descriptions do not establish the cause of intermittent display
failures. HDMI output/audio, microphone capture, SD power cycling, and suspend/
resume with board package 1.0.3 are not yet hardware-qualified. Advertised
capability does not guarantee stable operation at the highest speed. External
panel configurations are not enabled by this overlay.

Storage measurements cover one eMMC device and one SD card with short I/O
tests. HS400 boot coverage is limited to a software reboot. Cold power-on,
sustained workloads, suspend/resume and other storage variants remain unqualified.
