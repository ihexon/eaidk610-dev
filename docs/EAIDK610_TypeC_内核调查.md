# EAIDK-610 Type-C 自动角色选择：内核调查

日期：2026-09-06。对象：`ihexon@192.168.1.166`。初始调查阶段只做诊断；同日后续阶段已安装并启动测试内核，实机结果另列如下。overlay、供电声明、GPIO 和 extlinux 内容均未改动。

后续执行环境于 2026-09-06 更新为 Docker 容器，工作区为 `/home/ihexon/eaidk610-dev`；该容器不是 EAIDK610，也不再把原本的 `eaidk02` 当作执行端。容器只用于源码、GitHub Actions 和远程部署组织；本报告的板上证据和结论仍指向 `.166`，不因执行端变更而改变。所有 `/boot`、`/sys/class/typec`、debugfs、角色切换和重启命令都只能在明确连接 `.166` 后执行，不得对容器本身执行。

## 结论

原版内核日志、基础源码以及板上原版内核镜像的反汇编，共同指向 FUSB302 驱动的软件 Try.Source CC 更新路径不完整。测试内核已在 `port_type=dual`、手机带线启动的场景中自动进入 Source/Host 并完成 USB 枚举，驱动日志也证明新增路径实际执行并把 Rd 更新通知给 TCPM；这比临时 Source-only 重选提供了有效的实机修复证据。

不需要为了开启普通日志再重编译：内核开启了 DEBUG_FS，FUSB302 和 TCPM 有内置环形日志。早期 run `34013982555` 已确认 Armbian 将第一版小补丁作为第 1/228 项应用并生成四类软件包；实际安装的 image 与 DTB 哈希和该 artifact 一致。简化流程后的 run [`34017439800`](https://github.com/ihexon/eaidk610-dev/actions/runs/34017439800) 对提交 `4d82288ca488720b95e739e903054b651ec8be2b` 完成了独立复验：内核编译 2217 秒、Armbian 打包 54 秒，整个 workflow 在 42 分 6 秒后为绿色，非关键的 `compile.h` 元数据解析已经从流程中删除。下载后复验通过的四个 Armbian 原生包已发布为 GitHub pre-release [`eaidk610-typec-r1`](https://github.com/ihexon/eaidk610-dev/releases/tag/eaidk610-typec-r1)；完整回归未完成前不标记为稳定版。

第一版补丁在未连接状态的 Rp 设置路径启用 FUSB302 fixed-source toggling，复用已有 TOGDONE 的双 CC Open/Rd/Ra 分类与通知；同时缓存 `set_roles()` 的 attached 状态，禁止已连接状态走该分支，以避开历史上的 PD power-role swap 回归。补丁由构建脚本复制到 Armbian 的 `userpatches/kernel/archive/rockchip64-7.1/`，再由 `compile.sh kernel` 应用到 `drivers/usb/typec/tcpm/fusb302.c`。固定输入和实现见仓库的 `kernel/build.env`、`kernel/patches/` 及 `.github/workflows/typec-test-kernel.yml`。

当前结论仍限定为首轮验证通过，不能外推为全面验收完成。尚需正插、正反方向多次完整拔插、拔线后的 VBUS/partner 清理、连接电脑时的 Sink/Device、实际文件传输以及 USB3 测试。

## 测试内核部署与首轮实机结果

2026-09-06 从 run `34013982555` 下载并校验 image、DTB 软件包，只向 `.166` 安装。测试包使用独立包名，旧版内核文件与模块目录完整保留。Armbian 包安装生成了匹配的 `initrd.img`，但该板没有自动生成新版本 `uInitrd` 的 post-update hook；部署脚本因此先停止，随后用 `mkimage` 包装匹配 initramfs、核对 payload，再切换 `/boot/Image`、`/boot/uInitrd` 和 `/boot/dtb` 软链接。`extlinux.conf` 保持原样，仍只有一个 `LABEL Armbian` 和原 Type-C overlay。

重启约 22 秒后 SSH 恢复。运行版本为 `7.1.8-edge-rockchip64-eaidk610-typec-r1`，boot ID 为 `8b24b245-36ad-49f0-a8f2-fb7221506077`。手机在板端反向插入并在重启期间保持连接，未做任何 sysfs 角色写入，观察到：

```text
port_type=[dual] source sink
preferred_role=source
power_role=[source] sink
data_role=[host] device
orientation=reverse
power_operation_mode=1.5A
partner=present
```

USB 总线自动枚举 `18d1:4ee8 Google Inc. Nexus/Pixel Device (MIDI)`，设备实际为 OnePlus 8T，连接在 Type-C 控制器对应的 USB2 root hub，速率为 480 Mbps。此结果验证了 Source/Host 与数据枚举，不代表 USB3 已通过，也不能单靠软件观察确认手机端充电指示或长期传输稳定性。

本轮只读取一次 debugfs 环形日志。关键序列为：

| 开机时间 | 组件 | 事件 |
| --- | --- | --- |
| 4.417258 s | TCPM | `SNK_DEBOUNCED -> SRC_TRY` |
| 4.485062 s | FUSB302 | `start unattached SRC toggling for Rp-1.5`，确认补丁路径实际执行 |
| 4.571664 s | FUSB302 | TOGDONE 分类得到 `cc1=Ra, cc2=Rd` |
| 4.621067 s | FUSB302 | 缓存并通知 `cc1=Ra, cc2=Rd` |
| 4.621071 s | TCPM | `SRC_TRY_WAIT -> SRC_TRY_DEBOUNCE` |
| 4.641106 s | TCPM | `SRC_TRY_DEBOUNCE -> SRC_ATTACHED` |
| 4.644343 s | FUSB302 | `pd header := Source, Host, attached=true` |
| 4.757101 s | TCPM | `SRC_STARTUP -> SRC_READY` |

本次启动未发现 FUSB302、TCPM 或 Type-C warning/error，也没有 WARN/Oops 或模块版本错误。`typec_extcon` 已加载，模块文件来自测试版本自己的 `/lib/modules/7.1.8-edge-rockchip64-eaidk610-typec-r1/`。内核仍有音频、蓝牙固件、HDMI dummy regulator 等与本次 Type-C 修改无关的既有告警，不能把它们误记为补丁回归。板上原始采集目录为 `/home/ihexon/typec-test-log-8b24b245-36ad-49f0-a8f2-fb7221506077`。

## 版本和配置

- 原软件包：`linux-image-edge-rockchip64 26.8.3`；原版本 `7.1.8-edge-rockchip64` 仍保留用于恢复。
- 当前测试软件包：`linux-image-edge-rockchip64-eaidk610-typec-r1 26.08.0-trunk` 和 `linux-dtb-edge-rockchip64-eaidk610-typec-r1 26.08.0-trunk`。
- 当前运行版本：`7.1.8-edge-rockchip64-eaidk610-typec-r1`。
- 软件包记录的基础源码提交：`25c76bea853d0db65b51fb4697a47cbfd9e35e76`，对应 Linux 7.1.8。
- 软件包记录的 patches hash：`9a481daaebb92ebe`。
- 原版调查 boot ID：`f06223cb-8c8b-4e85-b7ac-af69d1fc7f9a`；测试内核 boot ID：`8b24b245-36ad-49f0-a8f2-fb7221506077`。
- `CONFIG_TYPEC_FUSB302=y`、`CONFIG_TYPEC_TCPM=y`、`CONFIG_DEBUG_FS=y`、`CONFIG_DYNAMIC_DEBUG=y`、`CONFIG_KPROBES=y`、`CONFIG_FUNCTION_TRACER=y`。
- 运行中设备树 `try-power-role` 为 `source`；测试内核首轮 sysfs 为 `port_type=dual`、`preferred_role=source`，实际角色为 Source/Host。
- `/lib/modules/7.1.8-edge-rockchip64/build` 不存在，不能直接在该板上针对当前内核构建外部模块。

核对命令：

```sh
uname -a
dpkg-query -s linux-image-edge-rockchip64
cat /proc/sys/kernel/random/boot_id
grep -E 'CONFIG_(TYPEC_FUSB302|TYPEC_TCPM|DEBUG_FS|DYNAMIC_DEBUG|KPROBES|FUNCTION_TRACER)=' \
    /boot/config-7.1.8-edge-rockchip64-eaidk610-typec-r1
cat /sys/class/typec/port0/port_type
cat /sys/class/typec/port0/preferred_role
cat /sys/class/typec/port0/power_role
cat /sys/class/typec/port0/data_role
```

## 本轮日志证据

以下时间为开机后的秒数，来自同一轮启动。读取前未执行角色重选；日志记录了此前发生的连接过程。

| 时间 | 组件 | 事件 |
| --- | --- | --- |
| 31.419097 | TCPM | `SNK_DEBOUNCED -> SRC_TRY` |
| 31.419116 | FUSB302 | `cc := Rp-1.5` |
| 31.428401 | TCPM | `SRC_TRY -> SRC_TRY_WAIT`，设置 100 ms 等待 |
| 31.432044 | FUSB302 | `COMP_CHNG, comp=true` |
| 31.432284 | FUSB302 | `cc1=Open, cc2=Open` |
| 31.443873 | FUSB302 | `COMP_CHNG, comp=false` |
| 31.455955 | FUSB302 | `VBUS_OK, vbus=off` |
| 31.528798 | TCPM | `SRC_TRY_WAIT -> SNK_TRYWAIT`，超时 |
| 32.015060 | TCPM | `SNK_DISCOVERY -> SNK_READY` |

在 `comp=false` 之后、Try.Source 超时之前，没有观察到有效 Rd 更新传递给 TCPM。首次开机约 4.49 秒的 Try.Source 同样出现 `comp=false` 后超时。约 41.67 秒的 TCPM 日志也记录了同类回落；不假定所有事件的 FUSB302 原始日志都完整保留。

读取已有日志的命令：

```sh
sudo cat /sys/kernel/debug/usb/tcpm-4-0022/log
sudo cat /sys/kernel/debug/usb/fusb302-4-0022/log
```

这些 debugfs 文件是驱动自己的环形日志，不是普通 `dmesg`。本版本成功读取会推进日志读指针，应保存第一次输出；多个采集程序并发读取可能互相消耗记录。短时间复现后立即采集，不需要先开启大量 printk。

## 源码对应关系

基础源码：

- [fusb302.c，固定提交](https://github.com/gregkh/linux/blob/25c76bea853d0db65b51fb4697a47cbfd9e35e76/drivers/usb/typec/tcpm/fusb302.c)
- [tcpm.c，固定提交](https://github.com/gregkh/linux/blob/25c76bea853d0db65b51fb4697a47cbfd9e35e76/drivers/usb/typec/tcpm/tcpm.c)

核查到的关键逻辑：

1. FUSB302 的 `tcpm_set_cc()` 在设置 Rp/Rd 后，把自身 `chip->cc1/cc2` 缓存清为 Open。Source 模式启用 COMP_CHNG，屏蔽用于 Sink 的 BC_LVL。
2. FUSB302 的 `tcpm_get_cc()` 只返回缓存，不重新读取 CC 电气状态。
3. `fusb302_irq_work()` 的 COMP_CHNG 分支只在 `comp=true` 时清缓存并调用 `tcpm_cc_change()`；`comp=false` 仅记录日志，没有重新分类或上报 CC。
4. TCPM 在 `SRC_TRY_WAIT` 收到有效 Source 连接状态才进入 `SRC_TRY_DEBOUNCE`；否则等待结束后进入 `SNK_TRYWAIT`。
5. 硬件 toggling 的 `fusb302_handle_togdone_src()` 则会调用 `fusb302_get_src_cc_status()` 测量、区分 Open/Rd/Ra，并更新缓存、通知 TCPM。这解释了为什么临时 Source-only 重选可以成功，而软件 Try.Source 仍失败。

重要限制：`comp=false` 只表示低于当前比较阈值，不等于已经确认 Rd，也可能是 Ra 等情况。不能直接添加“comp=false 就把 CC 写成 Rd、开启 VBUS”的简化修复。确认负载、消抖、极性、测量阈值恢复、VCONN 和 VBUS 安全条件必须保留。

## 已核对板上二进制，而非只看上游源码

通过 scp 只读取得板上 `/boot/vmlinuz-7.1.8-edge-rockchip64` 和对应 `System.map`，核对本地/远端 SHA-256 一致；启动配置指向 `/boot/Image`，该链接指向此版本。

```text
50382acfa47c4a16a2c4c5a186cd1d7a29c578051c9d70cdd1e565863df76d07  vmlinuz-7.1.8-edge-rockchip64
a4b2a0bf8c196a5412fbf25bebb6ab99499ab73facdbb5c36d8db7898add7ca1  System.map-7.1.8-edge-rockchip64
```

`System.map` 给出的链接地址：

```text
ffff800080000000  _text
ffff800080d62db8  tcpm_cc_change
ffff800080d6fd68  tcpm_get_cc
ffff800080d711a8  tcpm_set_cc
ffff800080d71878  fusb302_irq_work
```

使用 AArch64 objdump 按上述 `_text` 重定位原始 Image 反汇编：

```sh
aarch64-linux-gnu-objdump -D -b binary -m aarch64 \
    --adjust-vma=0xffff800080000000 \
    --start-address=0xffff800080d71878 \
    --stop-address=0xffff800080d72128 \
    vmlinuz-7.1.8-edge-rockchip64
```

关键分支：`0xffff800080d71b6c` 测试 STATUS0 的 COMP 位。false 路径只调用日志后继续处理其他 IRQ；true 路径在 `0xffff800080d71de4` 清空两个 CC 缓存，并于 `0xffff800080d71dec` 调用 `tcpm_cc_change`。`tcpm_get_cc` 中同样只读缓存。由此确认安装镜像包含上述处理方式，不以 Armbian 必然等于原版上游源码为前提。

## Armbian 补丁调查边界

检查了打包时间附近 Armbian build 提交 `fd4ebfd1e107d5b89f7a672c7d609789565753b2` 的整个 `patch/kernel/archive/rockchip64-7.1/`。未找到修改 FUSB302 驱动的补丁；其中修改 TCPM 的三份补丁涉及 PD capabilities/altmodes 注册与注销，不修复上述 Try.Source CC 事件路径。

此 build 提交按时间选取，不是已完整复现的软件包构建提交；不能声称已重现 `patches hash`。本轮针对关键行为的依据是现场日志、基础源码及板上二进制三者一致。

## 是否需要重编译，以及下一步

现在不需要用户先重编译来开启日志。修复阶段保持相同 Linux 基础版本、板级 overlay 和供电参数，只改 FUSB302 的 CC 更新路径；完整内核编译只在 GitHub Actions 的 ARM64 runner 进行。当前本地 Docker 容器不承担完整编译；Actions 上的 Armbian ARM64 构建容器属于该 runner 内的标准构建层。

r1 使用 Armbian 的现代 kernel-only CLI `./compile.sh kernel`，以可靠复现 rockchip64 edge 的完整补丁顺序。构建日志显示 228 项中第 1 项为本仓库 FUSB302 补丁，后续包含 `typec-extcon`、TCPM、Rockchip USB PHY/charger detection 等板级改动，不能用未应用这套补丁的纯上游 7.1.8 代替。项目决定继续采用正统 Armbian kernel 流程和它生成的原生 `.deb`，不再维护传统 make/tar 并行交付路线。

历史 workflow 的红色结论主要来自本仓库外围步骤，而非 Armbian 没有生成内核：版本 family、过宽的 whitespace 检查和 `compile.h` 制表符解析分别在内核编译后暴露。简化后的 wrapper 删除源码树检查、`compile.h` 解析、自行解包和重打包，只负责准备标准 `userpatches`、调用 `compile.sh kernel`、复制 `output/debs`。编译前静态 preflight 固定并校验 config、FUSB302 补丁和 family 文件哈希，测试关键配置、补丁语法及 kernelrelease 关系，并取固定 Linux 提交的原始 `fusb302.c` 做精确 apply check。run `34017439800` 中这些检查全部通过；下载 artifact 后再次确认全部 `SHA256SUMS`、arm64 包元数据、`vmlinuz-7.1.8-edge-rockchip64-eaidk610-typec-r1`、对应模块目录和 `rockchip/rk3399-eaidk-610.dtb` 均正确。

第一次完整编译证明补丁进入目标源码，但原自定义 `LOCALVERSION` 扩展造成 Armbian 打包名称不一致。后续构建改用 `userpatches/config/sources/families/rockchip64.conf` 覆盖测试用 `LINUXFAMILY`，使 Make、模块目录、Debian 包路径与包名从同一变量生成；run `34017439800` 已以全绿 workflow 再次证明该修正和简化流程有效，实际版本为 `7.1.8-edge-rockchip64-eaidk610-typec-r1`。

定点日志应包括：

- `tcpm_set_cc()` 的请求值、返回值、当前测量极性、清缓存前后状态；
- COMP_CHNG 的原始 IRQ/STATUS0、当前测量阈值、极性和缓存，以及是否调用 `tcpm_cc_change()`；
- 重新分类时的 Open/Rd/Ra 结果，以及阈值/开关状态恢复情况；
- TCPM 的 Try.Source 状态、CC 更新和退出原因（已有日志应优先复用）。

仅增加日志不修复丢失事件；也不建议先扩大超时或直接把 comp=false 当 Rd。修复需要考虑已经存在负载但没有新边沿的情况，而不只补一条 IRQ 分支。

当前 FUSB302/TCPM 均为内建 `=y`，不能靠替换 `.ko` 或 `modprobe` 更新这两个驱动。通常应构建并启动测试内核。若另外设计模块化测试方案，需要匹配完整内核配置与构建产物，不能使用该板现有其它版本 headers 凑合。

验收至少覆盖：手机正反插、多次拔插、带线冷启动、连接电脑的 Sink/Device 行为；同时核对 VBUS 角色安全和手机实际充电、USB 枚举/数据传输。Device 枚举另需有效 USB gadget。没有这些测试不能称自动双角色已修好。
