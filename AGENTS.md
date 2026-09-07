# EAIDK610 project instructions

## Scope

- The current workspace is a Docker container, not the EAIDK610.
- The only board used for hardware tests is `ihexon@192.168.1.166`, and board
  deployment, `/boot` changes, or reboot require an explicit user request.
- Use the pinned `armbian/` submodule and Armbian's standard `userpatches/`
  interface. Do not modify the submodule or maintain a parallel raw-Kbuild
  release path.
- The only deliverable is the complete Armbian image. Historical kernel-only
  releases are records, not a second build pipeline.

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
- Do not push, start GitHub Actions, create a release, or deploy to the board
  unless the user explicitly requests that external action.
- Avoid rebuilding after a successful kernel compile solely for a nonessential
  wrapper or reporting issue.

## Device tree

- Keep project board fixes in the single
  `rk3399-eaidk-610-typec-fix` overlay.
- The overlay must keep `tcphy0` connected to the Type-C extcon bridge.
- Headphone detection belongs on `simple-audio-card` as active-high GPIO4_D4.
- Speaker enable belongs to `simple-audio-amplifier` as active-high GPIO0_B3.
- Do not claim USB3 orientation, headphone detection, or speaker playback as
  hardware-verified until they are tested on the board.

## Release files

- Publish the complete image as `eaidk610-armbian-edge.img.xz`.
- Do not expose Armbian's internal artifact fingerprint in user-facing
  filenames.
- Keep detailed version and source provenance in `BUILD-MANIFEST.txt`.
- On failure, retain logs for one day; do not compress or upload a failed full
  image.

## Git, credentials, and remote operations

- Use the HTTPS origin and the active GitHub account `ihexon`.
- Commit as `ihexon <zzheasy@gmail.com>`.
- Never store passwords, tokens, SSH private keys, or sudo credentials in the
  repository, scripts, command arguments, or logs.
- Put complex board operations in a reviewed script, copy it to the board, and
  execute it there. Do not assemble a long destructive SSH one-liner.
- Use task-specific temporary directories and clean them on exit.

## Documentation

- README and current documents contain conclusions, current state, and
  validation boundaries only.
- Do not add conversational history, trial-and-error chronology, shell
  tutorials, or agent operating instructions to README or current documents.
- Put durable agent workflow rules in this file. Put historical evidence in
  `docs/history/` only when it remains useful; otherwise rely on Git history.
- Keep documentation synchronized when a technical conclusion or validation
  status changes.
