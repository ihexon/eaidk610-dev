# EAIDK610 Type-C kernel r1

Linux 7.1.8 kernel-only r1 是 FUSB302 Try.Source 修复的已验证历史版本。

| 项目 | 值 |
| --- | --- |
| Kernel release | `7.1.8-edge-rockchip64-eaidk610-typec-r1` |
| Repository commit | `4d82288ca488720b95e739e903054b651ec8be2b` |
| GitHub Actions run | `34017439800` |
| Armbian commit | `fd4ebfd1e107d5b89f7a672c7d609789565753b2` |
| Linux commit | `25c76bea853d0db65b51fb4697a47cbfd9e35e76` |
| Package version | `26.08.0-trunk` |
| Architecture | `arm64` |

构建使用标准 Armbian `compile.sh kernel`。FUSB302 patch 作为 228 项中的第一项
应用，目标对象完成编译，image、DTB、headers 和 libc-dev 包通过校验。

该内核已在 EAIDK610 启动。OnePlus 8T 反向连接时自动达到 Source/Host，并以
USB2 480 Mbps 枚举；驱动日志证明新的 Rd 检测路径实际执行。

此版本的 `linux-dtb` 包不含后续项目 overlay。它保持 pre-release，因为完整
正反插、断开/VBUS、Sink/Device、数据传输和 USB3 回归没有完成。活动流程现以
一次 Armbian 构建同时交付完整 image、内核 DEB 和 board overlay DEB。
