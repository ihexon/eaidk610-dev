# EAIDK610 development notes

This repository currently tracks the EAIDK610 USB Type-C kernel investigation,
the focused FUSB302 test patch, and its reproducible ARM64 GitHub Actions build.

Start with:

- `docs/EAIDK610_TypeC_内核调查.md`
- `docs/EAIDK610_TypeC_下一步修复与测试计划.md`
- `kernel/README.md`

The Docker workspace is a control and source environment only. Hardware checks,
boot-file changes, installation, and reboot testing apply only to the explicitly
identified EAIDK610 test board.
