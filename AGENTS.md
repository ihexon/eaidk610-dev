# EAIDK610 project instructions

## Scope

- Do not assume the development workspace is the EAIDK610. Use the test target
  supplied by the user; keep connection details in ignored local notes.
- Board deployment, `/boot` changes, or reboot require user authorization.
- This repository contains the Armbian build framework with native EAIDK610
  support. Keep the board in `config/boards/eaidk610.csc`, kernel fixes in
  `patch/kernel/archive/rockchip64-7.2/`, and board assets under
  `config/optional/boards/eaidk610/_packages/bsp-cli/`.
- Do not reintroduce a framework submodule, a required userpatches overlay,
  or a parallel raw-Kbuild release path. Use the framework's native BSP and
  image hooks rather than a standalone board package/customize-image script.
- The active deliverables are the complete Armbian image and the kernel/board
  DEBs produced by that same build. Historical kernel-only releases are
  records, not a second build pipeline.

## Build and validation

- Run expensive builds only in the manual GitHub Actions workflow on
  `ubuntu-24.04-arm`. Do not compile a complete kernel or image in this
  development container.
- Use one standard `./compile.sh build` invocation. Armbian may use its ARM64
  Docker environment and artifact cache on the ARM64 runner.
- Keep preflight checks cheap and deterministic. Do not add a second Armbian
  configuration run, mirror-synchronization gates, log-text assertions, or
  checks that duplicate the actual build.
- Retain final image checks for U-Boot, partition boundary, kernel/modules,
  board DTB, enabled overlay, and the merged Type-C/audio properties.
- Release helpers live in `tools/eaidk610/`; board support must also work with
  a direct root-level `./compile.sh build BOARD=eaidk610` invocation.
- BSP assets must participate in Armbian's package cache hashing so overlay
  changes cannot reuse a stale BSP artifact.
- The former `eaidk610-board-overlays` package owns files now supplied by the
  BSP. Remove that old package before an authorized in-place BSP installation;
  do not force file overwrites or silently migrate a host's boot configuration.
- Do not push, start GitHub Actions, create a release, or deploy to the board
  unless the user explicitly requests that external action.
- Avoid rebuilding after a successful kernel compile solely for a nonessential
  wrapper or reporting issue.
- Use Armbian's native `SRC_EXTLINUX` flow with one boot entry and no recovery
  entry. Keep boot arguments in the board definition and let Armbian generate
  the root UUID; the board image hook adds the overlay directive and management marker.
- Initial migration is explicit through the BSP's `eaidk610-boot-setup`; BSP
  upgrades may refresh only entries marked `/etc/eaidk610/boot-managed`.
  Keep packaged boot defaults generated from the board definition. U-Boot
  flashing requires an explicit whole disk and a partition-boundary check.
  Do not add backups or rollback to the setup tool; fail clearly and retain
  atomic extlinux replacement without claiming power-loss-safe firmware writes.
- Keep kernel logs visible on serial and display. Do not redirect systemd logs
  to the kernel buffer or change its rate limits.

## Device tree

- Keep project board fixes in the single
  `rk3399-eaidk-610-typec-fix` overlay.
- The overlay must keep `tcphy0` connected to the Type-C extcon bridge.
- Headphone detection belongs on `simple-audio-card` as active-high GPIO4_D4.
- Speaker enable belongs to `simple-audio-amplifier` as active-high GPIO0_B3.
- RT5651 audio routes must use the case-sensitive DAPM name `micbias1`.
- Do not invent a codec interrupt in the DT; jack detection uses simple-card GPIO.
- Keep the eMMC node unchanged from the base DTB while validating SD UHS;
  do not bundle eMMC timing or supply changes into SD tests.
- Do not claim USB3 orientation, headphone detection, or speaker playback as
  hardware-verified until they are tested on the board.

## Release files

- Publish the complete image as `eaidk610-armbian-edge.img.xz`; publish its
  image, DTB, headers, libc-dev, U-Boot, and native BSP DEBs with short stable names.
- The BSP release filename is `armbian-bsp-eaidk610-edge.deb`; its Debian
  package name remains `armbian-bsp-cli-eaidk610-edge`.
- Do not expose Armbian's internal artifact fingerprint in user-facing
  filenames.
- Keep detailed version and source provenance in `BUILD-MANIFEST.txt`.
- On failure, retain logs for one day; do not compress or upload a failed full
  image.

## Git, credentials, and remote operations

- Preserve the configured Git remote and commit identity.
- Never store passwords, tokens, SSH private keys, or sudo credentials in the
  repository, scripts, command arguments, or logs.
- Put complex board operations in a reviewed script, copy it to the board, and
  execute it there. Do not assemble a long destructive SSH one-liner.
- Use task-specific temporary directories and clean them on exit.

## Documentation

- README and public documents describe the project, supported interfaces,
  build/release process, and hardware validation coverage.
- Do not add conversational history, trial-and-error chronology, shell
  tutorials, or agent operating instructions to README or current documents.
- Put durable agent workflow rules in this file. Keep investigation notes,
  task plans, deployment logs, and experiment records under `local/notes/`,
  which is excluded by `.gitignore`. Do not force-add these files.
- Do not publish private IP addresses, personal filesystem paths, session
  transcripts, or per-machine task status in public documentation.
- Keep documentation synchronized when a technical conclusion or validation
  status changes.
