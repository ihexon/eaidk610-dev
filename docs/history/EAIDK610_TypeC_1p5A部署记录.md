# EAIDK610 Type-C 1.5A 配置部署记录

> 最新部署与清理（2026-09-06）：本机 eaidk02 和 .166 的启动文件已统一为原版 7.1.8 DTB + 当前单 overlay。两台基础 DTB/DTBO 哈希和离线合并均核对通过。本机没有重启，下次启动生效，保留一组必要回退文件；.166 已加载同版 overlay，本轮未重启，也未改变用户的 Source-only / Source / Host 状态，手机仍已枚举。当前路径和回退说明以 [overlay README](linux_boot/eaidk610-typec-fix/README.md) 开头为准。下文保留历史经过，已删除文件的旧命令不要再执行。

> 后续状态（2026-09-06）：.166 已切换到“原版 DTB + 单个 Type-C 修复 overlay”，并重启确认加载。当前部署和回滚方法见 [overlay 分发说明](linux_boot/eaidk610-typec-fix/README.md)。下面保留此前直接修改完整 DTB 的历史记录，不代表当前启动方式。

> 手机充电修正（2026-09-06）：统一 overlay 已改为 `try-power-role = "source"`，优先由板子给手机供电，保留双角色及 5V/1.5A、关闭 PD 的配置。当前源码和验证记录见上述分发说明；下文完整 DTB 的 Sink 优先配置仅为历史版本。

> 本轮验收限制：Source 优先重启后已生效，但当前手机仍曾回落到 Sink；短暂 Source-only 协商再恢复 dual 后，已保持 Source/Host、VBUS 开关开启。尚未确认手机实际充电，也未出现手机 USB 枚举，自动切换问题不能标为彻底修复。

> 最新进展：用户已确认充电。统一 overlay 又补齐 Type-C → extcon → USB2 PHY / DWC3 数据通知路径并重启，OnePlus 8T 已在 480 Mbps 下枚举，当前 ID 为 `22d9:2771`、Imaging 类接口。基础 DTB 未改；数据桥接已验证，实际文件复制及自动重复插拔尚未验收，本次连接仍使用了临时角色重选。详见 overlay README 最后一节。

> 清理记录：.166 上的 `.before-typec-1p5a`、`.before-typec-fix`、旧完整 1.5A DTB 和旧 extlinux 备份均已删除。工作区旧完整 Type-C DTS/DTB、编译警告、重复远端配置样本、临时部署脚本与内核调查下载已清理。当前仅本机保留一组待首次重启验收的回退文件，详见上述 README；保留修复分发包、工作日志、内核调查结论及无关的烧录/I2C2 工具。

2026-09-06：已向 `ihexon@192.168.1.166` 安装关闭 PD、声明 5V/1.5A 的 DTB。内核为 `7.1.8-edge-rockchip64`，保留此前 FUSB302/TCPM 双角色修复。本次没有重启远端；安装后运行中的端口仍显示 `default`，下次启动才加载新配置。本机 `/boot` 未在本次部署中修改。

## 变更与验证

只修改 `/i2c@ff3d0000/typec-portc@22/connector` 中的属性：

```dts
typec-power-opmode = "1.5A";
```

`pd-disable`、`power-role = "dual"`、`data-role = "dual"`、`try-power-role = "sink"` 及 VBUS regulator 修复保持不变。1.5A 是 Source 模式通过 CC 向对端声明的电流能力，不是软件恒流设置，也不代表已完成满载、压降或温升测试。Sink 模式的可用电流由对端声明。

原理图中 R1466 为 3.6kΩ，按 SY6280 数据手册公式，典型限流值约 1.89A；这不是保证的连续输出额定值，存在器件容差。该电源路径只使用 5V。

按用户要求，直接在完整 `rk3399-eaidk-610-typec-1p5a.dts` 中声明该属性，使用 `dtc` 编译完整 DTB；不使用 overlay。该 DTS 复制自此前验证的 `rk3399-eaidk-610-typec-fixed.dts`，只改变电流声明。完整设备树比较确认只有上述属性变化。传输前后及安装后的 SHA-256 一致。本次先前生成的 overlay 源文件和 DTBO 已移除，最终安装产物来自完整 DTS 的直接编译。

```sh
cd /home/ihexon/eaidk610_dev
dtc -I dts -O dtb \
  -o rk3399-eaidk-610-typec-1p5a.dtb \
  rk3399-eaidk-610-typec-1p5a.dts
```

基准 DTB SHA-256：`6c1193b863463721f84fd6e0937a0e81353e17022d030f7a77e5d12838ff9692`。

新 DTB SHA-256：`b928200571af59c59ae78e8c6f22ea6d2eca1dc0841679b71ceeabc74b592c3f`。

## 远端路径与生效方式

extlinux 的 FDT 路径 `/boot/dtb/rockchip/rk3399-eaidk-610.dtb` 实际指向：

```text
/boot/dtb-7.1.8-edge-rockchip64/rockchip/rk3399-eaidk-610.dtb
```

安装前保留当前正常工作的 DTB 为同目录下 `rk3399-eaidk-610.dtb.before-typec-1p5a`，然后在同目录创建临时文件、验证哈希、rename 替换目标并 sync。更早的 `.before-typec-fix` 原始备份也保留。

在适合重启时执行：

```sh
ssh -t ihexon@192.168.1.166 'sudo reboot'
```

重启后读取生效的设备树属性与端口状态：

```sh
ssh ihexon@192.168.1.166
tr -d '\000' < /sys/firmware/devicetree/base/i2c@ff3d0000/typec-portc@22/connector/typec-power-opmode
cat /sys/class/typec/port0/power_operation_mode
cat /sys/class/typec/port0/power_role
cat /sys/class/usb_role/fe800000.usb-role-switch/role
```

运行时设备树属性应为 `1.5A`。接入 USB-C 外设且本板成为 Source 后，端口应报告 `1.5A`、`source`、`host`。还需通过实际外设或电子负载验证供电；仅修改声明不能证明持续输出能力。

## 回滚到默认电流的双角色修复版

在远端执行：

```sh
sudo cp -a \
  /boot/dtb-7.1.8-edge-rockchip64/rockchip/rk3399-eaidk-610.dtb.before-typec-1p5a \
  /boot/dtb-7.1.8-edge-rockchip64/rockchip/rk3399-eaidk-610.dtb
sudo sync
sudo reboot
```

本文件记录的是 7.1.8 DTB 部署，不涉及工作区内此前打包的 7.1.9 系统镜像。内核/DTB 软件包更新后应核对实际启动的 DTB 并在对应版本重新合并和验证。
