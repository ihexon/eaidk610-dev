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
| Audio clock and defaults | Codec MCLK follows I2S1 and is output on GPIO4_A0; BSP supplies board-specific ALSA defaults: onboard microphone boost 40 dB, headset microphone boost 20 dB, ADC digital gain 0 dB |
| Analog audio selection | Native ALSA UCM profile exposes Speaker, Headphones, Mic, and Headset; a simple-card pin switch controls the speaker amplifier independently of headphone playback |
| HDMI | Separate VCCA0V9_S3 and VCCA1V8_S3 analog supplies; existing I2S2 HDMI sound card enabled |
| SARADC | Reference supply connected to analog VCCA1V8_S3, separate from digital VCC1V8_S3 |
| SD card | GPIO0_A1-controlled 3.0 V card supply; RK808 VCC_SDIO supplies bus I/O; UHS SDR50/SDR104 enabled with a 200 MHz limit |
| eMMC | HS400 at 1.8 V with internal PHY strobe pull-down; base supply and clock configuration retained; Enhanced Strobe not enabled |
| Serial console | UART2, 1500000 baud, 8N1, with device-tree `stdout-path` |
| Image boot logs | Native extlinux; serial and display kernel consoles, loglevel 8, earlycon enabled, systemd startup status shown; default systemd log routing retained |
| Bluetooth | BCM4345C0 firmware alias; UART0 TX/RX mapped to DMAC1 requests 0/1; DMA operation pending hardware validation |

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

## Analog audio

The BSP supplies the EAIDK610 UCM profile and initial mixer state. New images
start with onboard microphone capture enabled at 40 dB analog boost and 0 dB
ADC digital gain. The headset microphone has a separate 20 dB analog default;
its gain and listening quality remain unqualified. Existing installations keep
their saved mixer state during BSP upgrades.

The UCM HiFi profile provides mutually exclusive Speaker/Headphones playback
and Mic/Headset capture routes. DAC1 is shared by the headphone output and
speaker amplifier. PipeWire uses software volume control to keep the codec ADC
at 0 dB digital gain. Microphone monitoring into the DAC is
disabled. No sample rate or sample format is forced by the profile.

Headphone insertion is reported through `Headphones Jack`. Images include
PipeWire, its PulseAudio-compatible service, and WirePlumber. When their user
services are running, they can use UCM jack events to select headphones and
disable the speaker amplifier. Analog playback is preferred over the generic
HDMI fallback unless the user selects a different default. UCM is configuration,
not an event daemon;
direct ALSA applications do not perform automatic route selection. The GPIO
cannot identify whether the inserted plug has a microphone, so onboard capture
remains preferred and headset capture is explicitly selectable. Bluetooth AIF2
audio routing is not enabled.

## Audio driver and scheduling defaults

The kernel patch set declares DW HDMI I2S audio playback-only. An absent
monitor's all-zero ELD uses the existing stereo fallback during PCM probing;
nonempty capability data is still parsed and refreshed on hotplug. The
Rockchip I2S register cache explicitly initializes the transfer-control
register to its documented stopped state.

EAIDK610 images set `rt_group_sched=0` so RTKit can grant realtime scheduling
to audio threads under cgroup v2 without zero-bandwidth RT task groups.
Normal CPU/memory cgroup controls remain enabled; per-group SCHED_FIFO/RR
bandwidth allocation is disabled. This does not enable PREEMPT_RT or remove
the global realtime bandwidth limit. Existing installations need an explicit
boot-argument update; installing a BSP does not rewrite their boot settings.

These driver and scheduling changes are not yet build- or hardware-qualified.
HDMI hotplug/playback, audio-thread realtime priority and runtime suspend/resume
require verification with the updated kernel and boot arguments.

## Watchdog

The DesignWare watchdog's fixed timeout fallback matches the 16 counter
ranges documented in RK3399 TRM V1.4 Part1, section 17.4. A missing
`snps,watchdog-tops` warning does not itself mean the watchdog is unusable.
The native BSP supplies a systemd manager drop-in enabling runtime watchdog
monitoring with a requested 30-second timeout by default in new images.
The reboot watchdog retains systemd's default 10-minute timeout. No separate
watchdog daemon or device-tree change is required.

The same runtime setting has been enabled on hardware; the driver reports an
active watchdog and a 30-second timeout. Expiry-triggered reset, reboot
persistence and the packaged image default remain hardware-unqualified.

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
| Type-C userspace tool | Argument handling and sysfs fixture tests; r9 native BSP installation and non-root status/help verified on Linux 7.2.4. Userspace-requested role changes are not yet hardware-qualified |
| Audio | Linux 7.2.3 with board package 1.0.1: card registration and a 48 kHz stereo silent PCM playback test |
| Onboard microphone | Linux 7.2.4, r9 BSP with updated audio-clock overlay: reboot verified; codec MCLK follows I2S1 at 12.288 MHz and GPIO4_A0 is assigned. Two 10-second, 48 kHz S16_LE stereo captures with IN2/BST2 enabled produced nonzero samples without clipping; listening quality remains unqualified |
| Analog audio configuration | Linux 7.2.4: updated overlay reboot verified; onboard 40 dB boost and 0 dB ADC gain confirmed; initial ALSA state restores and all four UCM routes apply successfully, including speaker pin mute and exclusive IN2/IN3 selection. PipeWire/WirePlumber run with the board profile. Physical jack switching, audible playback, headset capture, full-duplex streams, and additional sample formats remain unqualified |
| Bluetooth | Board package 1.0.1: firmware patch build 0230 loads successfully |
| Bluetooth UART DMA | Overlay mapping follows RK3399 TRM V1.4 Part1, table 12-2; DT compilation and merge checked. DMA channel acquisition, sustained traffic and suspend/resume remain unqualified |
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
