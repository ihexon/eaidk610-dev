# EAIDK610 Type-C 当前状态与剩余验收

更新日期：2026-09-07。

## 已完成

| 项目 | 结论 |
| --- | --- |
| FUSB302 修复 | Linux 7.1.8 r1 已编译、安装并在 `.166` 启动 |
| 自动角色 | 一次反向、带手机启动场景自动达到 Source/Host |
| USB2 | OnePlus 8T 已以 480 Mbps 枚举 |
| 完整镜像 | r4 已成功发布完整镜像、四个内核 DEB 和 board DEB |
| USB3 PHY 描述 | `tcphy0` 已在 overlay 中连接 Type-C extcon bridge |
| 耳机检测 | 已在 overlay 中改为 simple-audio-card GPIO4_D4 高有效 |
| 扬声器使能 | 已在 overlay 中改为 simple-audio-amplifier GPIO0_B3 高有效 |
| 发布组成 | 同一次完整镜像构建交付 image、四个内核 DEB 和 board overlay DEB |
| 声卡注册 | `.177` 的 board 包 1.0.1 已修正 micbias1 路由，播放/录音 PCM 已出现 |
| 启动与蓝牙 | `.177` 已验证 earlycon 初始化和蓝牙固件 build 0230 加载 |

## 尚未完成

| 项目 | 验收结论要求 |
| --- | --- |
| USB2 稳定性 | 正反方向多次拔插、断开和带线启动均自动协商正确 |
| Sink/Device | 连接电脑时角色正确，恢复后再次连接手机仍正常 |
| 数据传输 | 实际文件传输成功，无反复断连 |
| USB3 Host | 正反方向均显示 5000 Mbps，并完成存储读写 |
| USB3 Device | 正反方向均以 SuperSpeed gadget 枚举 |
| 耳机检测 | ALSA jack 状态随未插、插入、拔出正确变化 |
| 扬声器 | PT5305 播放时正常使能且扬声器有声 |
| 安全与稳定 | 拔线后 partner/VBUS 状态正确，无 GPIO 冲突、WARN 或 Oops |

## 当前交付边界

活动交付是完整 Armbian image 及同一次构建产生的内核/board DEB，不维护独立的
kernel-only 构建路线。当前 Docker 容器不是测试板，当前实机为 `.177`。
board 包已安装并重启验证；声卡注册成功不代表耳机插拔、实际发声或 USB3
双方向数据传输已经通过验收。RT5651 无中断驱动补丁待新内核验证。
