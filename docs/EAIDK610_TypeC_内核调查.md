# EAIDK610 Type-C 内核调查结论

## 根因

Linux 7.1.8 的 FUSB302 软件 Try.Source 路径在切换到 Rp 后清空 CC 缓存，
`tcpm_get_cc()` 只返回缓存；COMP_CHNG 的 `comp=false` 分支没有重新分类并通知
TCPM。TCPM 因而看不到有效 Rd，最终从 Source 尝试回落到 Sink。

板上 debugfs 日志、固定 Linux 源码和运行中内核的 AArch64 反汇编对这一行为给出
了一致证据。同期 Armbian rockchip64 补丁没有修复该 FUSB302 路径。

## 修复

项目补丁在未连接状态设置 Rp 时启动 FUSB302 已有的 fixed-source toggling，
复用 TOGDONE 的 Open/Rd/Ra 测量、缓存更新和 `tcpm_cc_change()` 通知路径。
驱动缓存 attached 状态，已连接时不进入该分支。

补丁位于：

`userpatches/kernel/archive/rockchip64-7.2/0001-usb-typec-fusb302-detect-unattached-source-connectio.patch`

## 实机结论

Linux 7.1.8 kernel-only r1 已在 `192.168.1.166` 启动。OnePlus 8T 反向连接并
带线启动时，Type-C 在 `port_type=dual` 下自动进入 Source/Host，方向为
reverse，供电模式为 1.5A，并以 USB2 480 Mbps 枚举。日志确认补丁启动
source toggling、测得 `cc1=Ra, cc2=Rd`，TCPM 随后进入 `SRC_ATTACHED` 和
`SRC_READY`。该轮没有 FUSB302、TCPM 或 Type-C warning/error。

## Device tree 结论

- `tcphy0_usb3` 的 `orientation-switch` 布尔属性不被 RK3399 tcphy 驱动消费；
  `tcphy0` 必须连接 Type-C extcon bridge，才能取得角色和插头方向。
- 主线 RT5651 不消费 codec 节点上的 `hp-det-gpios` 和 `spk-con-gpio`。
- 耳机检测属于 simple-audio-card，实际信号 `HP_DET_H` 为 GPIO4_D4 高有效。
- 扬声器使能属于 simple-audio-amplifier，为 GPIO0_B3 高有效，PT5305 由
  `VCC5V0_SYS` 供电。
- 上述修复均已进入同一个项目 overlay。基础 DTB 中不受支持的旧属性仍存在，
  但不再是功能消费者。
- 历史 kernel-only r1 的 `linux-dtb` 包不含该项目 overlay。当前流程将 overlay
  构建为 `eaidk610-board-overlays.deb`，完整镜像安装此包并默认启用。

## 验证边界

当前证据证明 FUSB302 修复在一次反向 USB2 场景有效，并证明新 overlay 能与
最终 EAIDK610 DTB 合并。尚未证明 USB3 双方向、反复拔插、Sink/Device、实际
文件传输、耳机插拔事件或扬声器播放全部通过。
