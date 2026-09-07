# EAIDK610 project instructions

## Scope

- Do not assume the development workspace is the EAIDK610. Use the test target
  supplied by the user; keep connection details in ignored local notes.
- Board deployment, `/boot` changes, or reboot require user authorization.
- Use the pinned `armbian/` submodule and Armbian's standard `userpatches/`
  interface. Do not modify the submodule or maintain a parallel raw-Kbuild
  release path.
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
- RT5651 audio routes must use the case-sensitive DAPM name `micbias1`.
- Do not invent a codec interrupt in the DT; jack detection uses simple-card GPIO.
- Do not claim USB3 orientation, headphone detection, or speaker playback as
  hardware-verified until they are tested on the board.

## Release files

- Publish the complete image as `eaidk610-armbian-edge.img.xz`; publish its
  image, DTB, headers, libc-dev, and board DEBs with short stable names.
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
