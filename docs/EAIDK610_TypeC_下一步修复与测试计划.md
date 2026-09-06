# EAIDK-610 Type-C：下一步内核修复与测试计划

更新日期：2026-09-06。

## 结论与执行顺序

下一步应修复 FUSB302 驱动的软件 Try.Source CC 状态更新路径，用 GitHub Actions 构建测试内核，再安装到 `ihexon@192.168.1.166` 做实机对照测试。保留当前已经可用的 Type-C overlay，不继续通过修改相同 DT 属性排查这个内核问题。

顺序：GitHub CLI 与仓库访问（已完成）→ 固定构建基线（已完成）→ 编写小范围驱动补丁和定点日志（已完成）→ ARM64 内核编译与打包（已完成）→ 建立远端回退入口 → 安装测试内核 → 自动角色选择验收 → 整理正式补丁。

本文同时记录当前执行进度。容器内的 GitHub 身份、HTTPS 仓库访问、固定构建输入、FUSB302 补丁和手动 workflow 已准备并推送。Actions run `34013982555` 已完成补丁应用、内核编译、模块安装及四类 Debian 包生成，下载 artifact 的全部 SHA256 校验通过；workflow 在其后的非关键编译器元数据解析处标红。按当前验收标准，内核编译任务已经完成；尚未安装或实机验证，测试板启动配置未修改。

## 一、当前状态与不可突破的边界

| 项目 | 当前状态 |
| --- | --- |
| 执行端 | Docker 容器，工作区 `/home/ihexon/eaidk610-dev`；不是 EAIDK610，不承载板级 `/boot`、overlay 或 Type-C 硬件 |
| 测试板 | `ihexon@192.168.1.166`，同版内核；当前 overlay 已加载 |
| 已验证功能 | Android 在正确 Source/Host 角色下能充电、传数据，已观察到 USB2 480 Mbps 枚举 |
| 未完成事项 | 自动 Try.Source 仍可能失败；USB3、自动双向插拔和全面回归尚未验收 |
| 远端最后一次检查 | 用户手动设置了 Source-only；实际为 Source/Host，手机仍枚举 |
| 源码仓库 | `https://github.com/ihexon/eaidk610-dev`；容器内 Git 工作树为 `/home/ihexon/eaidk610-dev/eaidk610-dev`，通过 HTTPS 推送到 `main` |
| GitHub CLI | 已安装；`github.com` 只保留并激活 `ihexon`，仓库权限为 `ADMIN`，Git 通过 HTTPS 由 `gh` 提供凭据 |
| Git 提交身份 | 仓库级配置为 `ihexon <zzheasy@gmail.com>` |
| 内核工程 | 补丁、固定输入、构建脚本和 workflow 已提交并推送；run `34013982555` 已完成内核编译并生成四类 `.deb` |

必须遵守：

- Docker 容器只负责源码、CI 和远程组织；不把容器的 `/boot`、`/sys` 或运行内核当作 EAIDK610 状态，不尝试向容器安装测试内核。
- 先在 `.166` 测试。中断手机连接和重启前通知用户；涉及插拔、正反插、串口恢复时请用户配合。
- 继续使用单个 overlay、单个 `LABEL Armbian`，不增加用户不需要的 fallback 菜单项。
- 保留当前原版 DTB、overlay、5V/1.5A 声明及 `pd-disable`，不同时引入 PD、DP 或供电能力变更。
- 不恢复 VBUS 常开、不直接拉高 GPIO，不用 Source-only 服务掩盖自动协商失败。
- 不把 sudo 密码、GitHub token、SSH 私钥写入仓库、workflow 或日志。

当前配置与内核调查分别见 [overlay 部署说明](linux_boot/eaidk610-typec-fix/README.md) 和 [内核调查报告](EAIDK610_TypeC_内核调查.md)。旧临时下载、旧完整 Type-C DTS/DTB 和部署脚本已清理，不要依赖以前的 `/tmp` 路径。

## 二、gh 与仓库访问（已完成）

容器内的当前状态可用以下命令复核：

```sh
gh auth status
gh api user --jq .login
gh repo view ihexon/eaidk610-dev --json nameWithOwner,viewerPermission
git -C /home/ihexon/eaidk610-dev/eaidk610-dev remote -v
git -C /home/ihexon/eaidk610-dev/eaidk610-dev config --get user.name
git -C /home/ihexon/eaidk610-dev/eaidk610-dev config --get user.email
git -C /home/ihexon/eaidk610-dev/eaidk610-dev ls-remote origin
```

已删除 Docker 容器内其他账号的本地 `gh` 登录信息，只保留 `ihexon`。`origin` 为 `https://github.com/ihexon/eaidk610-dev.git`，`gh auth setup-git` 已配置 Git 凭据帮助器；不再依赖 GitHub SSH key 或临时 `SSH_AUTH_SOCK`。空仓库的 `ls-remote` 成功时可以没有 refs，不能因无输出误判为连接失败。

完成条件已满足：API 身份为 `ihexon`，对仓库有 `ADMIN` 权限，HTTPS Git 远程访问正常，提交作者为 `ihexon <zzheasy@gmail.com>`。workflow 已提交到默认分支，并通过 `workflow_dispatch` 手动触发。

## 三、固定构建基线，不同时升级内核

先使用现有版本做修复，避免把内核升级和 CC 修复混在一次实验中。

| 内容 | 已知值或要求 |
| --- | --- |
| Armbian 软件包 | `linux-image-edge-rockchip64 26.8.3` |
| Linux 基础版本 | `7.1.8` |
| 基础源码提交 | `25c76bea853d0db65b51fb4697a47cbfd9e35e76` |
| 当前软件包 patches hash | `9a481daaebb92ebe` |
| 原编译器信息 | Debian GCC `14.2.0-19`、GNU ld `2.44` |
| 配置来源 | `.166:/boot/config-7.1.8-edge-rockchip64` |
| 测试内核版本后缀 | 必须与原内核不同，并随修订递增 |

在仓库准备好 `kernel/` 目录后取得配置：

```sh
cd /home/ihexon/eaidk610-dev/eaidk610-dev
mkdir -p kernel
scp ihexon@192.168.1.166:/boot/config-7.1.8-edge-rockchip64 \
  kernel/config-7.1.8-edge-rockchip64
ssh ihexon@192.168.1.166 'dpkg-query -s linux-image-edge-rockchip64'
```

构建路线优先沿用固定提交的 Armbian 构建框架，锁定 Linux 提交和 rockchip64 补丁集；核对实际源码与最终 `make kernelrelease`，不能仅以配置文件写了 `edge` 就认定版本正确。

本次第一次构建固定采用 Armbian build 提交 `fd4ebfd1e107d5b89f7a672c7d609789565753b2`。它是按打包时间和 `rockchip64-7.1` 补丁内容选取的候选，不代表已经复现软件包 `26.8.3`；workflow 会在构建清单中记录该提交、Linux 提交、配置/补丁哈希、实际工具链和最终 kernelrelease。若不能复现现有内核行为，应从同一重建基线分别构建“不含 CC 修复”和“含 CC 修复”的对照内核。

必须保留当前 overlay 依赖的 Armbian 改动：`typec-extcon` 桥接、USB2 PHY 的 `extcon,ignore-usb` 支持、相关 DWC3 quirk。纯上游 Image 加旧 Armbian 模块不是等价替代方案。

配置中 FUSB302/TCPM 为内建 `=y`，本次按构建完整测试内核处理。Image、模块、配置和 initramfs 必须匹配，不能用其它版本 headers 或复制旧 `.ko` 代替。

## 四、驱动补丁的具体工作

目标文件首先是 `drivers/usb/typec/tcpm/fusb302.c`。只有实测证据要求时才扩大到 `tcpm.c`。

已确认的代码关系：切换 Rp 会清空 CC 缓存，`get_cc()` 返回缓存，COMP_CHNG 的 false 分支未重新分类并通知 TCPM；硬件 TOGDONE 的 Source 路径则有完整分类。这是本次补丁的切入点。[固定版本 FUSB302 源码](https://github.com/gregkh/linux/blob/25c76bea853d0db65b51fb4697a47cbfd9e35e76/drivers/usb/typec/tcpm/fusb302.c)

已生成补丁 `kernel/patches/0001-usb-typec-fusb302-detect-unattached-source-connectio.patch`，SHA256 为 `5958c673687481b5f19b11892ff90e55d7231640c8869337a4610217da9c8bf8`。补丁增加 FUSB302 自身的 `attached` 状态缓存：当 TCPM 在未连接状态把 CC 从 Rd 切换到任一种 Rp 时，启用芯片已有的 fixed-source toggling；TOGDONE 随后复用现有的双 CC Open/Rd/Ra 测量、缓存更新和 `tcpm_cc_change()` 通知路径。已连接状态不启动 toggling，避免重现“PD power-role swap 期间无法发送消息”的历史回归。

该实现按以下约束审查：

1. 在软件 Try.Source 所使用的 Rp 设置路径中安排有效 CC 状态更新，不依赖一定会出现新的 IRQ 边沿。
2. COMP_CHNG 表示可能连接时，按阈值重新区分 Open、Rd、Ra；不能直接把 `comp=false` 写成 Rd。
3. 测量过程保持有效的 CC 极性、上拉/下拉和 VCONN；若暂时修改测量寄存器，完成或失败后都恢复正确状态。
4. 仅在状态发生有效变化时更新缓存并调用 `tcpm_cc_change()`；避免重复通知反复触发消抖。
5. 本补丁不新增 delayed work；切到 Rd/Open 或下次设置 CC 时，现有 `fusb302_set_toggling(...OFF)` 路径停止 toggling，不产生额外任务生命周期。
6. I2C 失败不能被解释为有效负载；不绕过 TCPM 的角色、消抖和 VBUS 控制流程。
7. 保留现有 Source 断开检测和 Sink BC_LVL 检测；不能只让当前一根线、一个方向成功。

直接复用 `fusb302_get_src_cc_status()` 前，先审查它对 SWITCHES0、MEASURE、toggling 和 VCONN 的副作用；硬件 TOGDONE 场景下可调用，不代表任意已连接场景都可以原样调用。

定点日志复用 FUSB302/TCPM 的 debugfs 环形日志，并新增 CC 请求时的极性/attached 状态、未连接 Source toggling 启动以及 set_roles 的 attached 状态。现有 TOGDONE 测量路径已经记录 STATUS0、阈值测量和最终 CC 分类，不新增持续高频 printk。

补丁在固定 Linux 基础源码上通过 `git diff --check`。本地 Docker 内尝试过相关对象的交叉编译准备，但因容器缺少 `bc` 在生成阶段停止，尚未进入 `fusb302.o` 编译，因此该次本地尝试没有结论。Actions run `34000886605` 随后已完成包含本补丁的完整内核编译和模块安装，证明补丁可在固定 ARM64 构建基线上编译；实机仍需覆盖 Open、Ra、Rd、负载已存在但无新边沿、断开、I2C 错误和角色变化，CI 绿色不能替代电气和时序测试。

### 4.1 GitHub Actions 构建记录

- run `34000659001` 被提前取消，没有形成编译结论；取消不是代码失败。
- run [`34000886605`](https://github.com/ihexon/eaidk610-dev/actions/runs/34000886605) 使用外层 `ubuntu-24.04-arm` runner 和内层 Armbian ARM64 Docker 构建环境。日志显示补丁以 `001/228` 应用到 `fusb302.c`，内核在 2247 秒内完成编译，并将模块安装到 `lib/modules/7.1.8-edge-rockchip64-eaidk610-typec-r1`。
- 该 run 随后在 Debian 打包阶段失败：打包器按默认 family 查找 `image/boot/vmlinu*-7.1.8-edge-rockchip64`，而内核 Make 已生成带 `-eaidk610-typec-r1` 的文件。根因是原 `typec-test-localversion` 扩展只覆盖 Make 的 `LOCALVERSION`，没有同步改变 Armbian 的 `kernel_version_family`。
- 修正方案删除该扩展，改为在 `userpatches/config/sources/families/rockchip64.conf` 中设置测试专用 `LINUXFAMILY=rockchip64-eaidk610-typec-r1`，同时显式保留 `LINUXCONFIG=linux-rockchip64-edge` 和 `KERNELPATCHDIR=archive/rockchip64-7.1`。固定 Armbian 提交的 Make、模块安装、Debian 路径和包名都使用该 family，因此名称将保持一致。
- artifact 的 `SHA256SUMS` 改在构建命令及 `tee` 完全结束后由独立的 `if: always()` 步骤生成，避免散列计算后 `build.log` 仍被追加；编译器版本直接读取内核生成的 `include/generated/compile.h`，不依赖 runner 宿主是否恰好安装同名交叉编译器。
- run `34012127716` 证明 family 修正有效：内核完成编译，image、DTB、headers、libc-dev 四个包均完成创建，版本和模块目录一致。随后仓库脚本的全树 `git diff --check` 命中 Armbian 既有 DTS 补丁中的空白字符并退出；这不是本次 FUSB302 文件的问题。检查范围因此收窄为 `drivers/usb/typec/tcpm/fusb302.c`，继续保留对本补丁的 whitespace 验证而不让无关基线告警阻断产物收集。
- run [`34013982555`](https://github.com/ihexon/eaidk610-dev/actions/runs/34013982555) 再次完成内核编译（2274 秒）和四类 Debian 包生成。artifact 中 `SHA256SUMS` 对日志及四个包全部校验通过；解开 image 包得到唯一模块目录 `7.1.8-edge-rockchip64-eaidk610-typec-r1`，内核镜像包含本补丁新增的日志字符串。workflow 只在包已上传后因 `compile.h` 使用制表符而未被元数据解析表达式匹配，最终显示失败；解析表达式已修正，但按“内核编译完成即可”的验收标准不再为此重复全量构建。

## 五、仓库与 workflow 交付内容

当前仓库交付目录如下：

```text
eaidk610-dev/
├── .github/workflows/typec-test-kernel.yml
├── scripts/build-test-kernel.sh
├── kernel/build.env
├── kernel/config-7.1.8-edge-rockchip64
├── kernel/armbian/rockchip64-family.conf
├── kernel/patches/0001-usb-typec-fusb302-detect-unattached-source-connectio.patch
├── kernel/README.md
└── .gitignore
```

不要提交完整 Linux 源码树、编译输出、系统镜像和凭据。构建步骤写入 workflow；复杂安装操作仍可使用临时脚本 scp 到 `.166` 执行，执行后删除，不在板上保留常驻修复服务。

workflow 要求：

- 支持 `workflow_dispatch`，初期不因任意文档提交自动启动大规模编译。
- 使用 GitHub 托管的 ARM64 `ubuntu-24.04-arm`，不把本地 Docker 执行容器或 `.166` 注册为自托管 runner；workflow 先在宿主核对 `uname -m=aarch64` 和 Debian `arm64` 架构。Armbian 可在该 ARM64 runner 内启动其 ARM64 构建容器，日志中的 `🐳` 和 OCI manifest 下载即来自这一层；完整编译仍全部发生在 GitHub Actions。[runner 说明](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- checkout、artifact 等第三方 action 固定到核实过的提交；权限从 `contents: read` 开始，不授予无关写权限。
- Linux、Armbian 补丁集、配置和补丁均可追溯；禁止静默换到 latest 内核。
- 通过测试专用 Armbian `LINUXFAMILY` 设置独立 `KERNELRELEASE` `7.1.8-edge-rockchip64-eaidk610-typec-r1`，使内核、模块目录、Debian 路径和包名一致；最终仍以构建输出值为准。
- 使用固定 Armbian `rockchip64-7.1` 补丁集和板上配置，完整编译 Image、模块与 DTB；解开生成的 Debian 包核对模块目录和唯一 kernelrelease 后再打包。失败时也上传构建日志和诊断信息。
- Artifact 至少包含 Image、匹配模块、配置、System.map、构建清单、补丁、SHA256SUMS 和构建日志；建议命名 `eaidk610-typec-test`。
- 构建清单记录仓库提交、Linux/Armbian 提交、工具链、补丁哈希、配置差异、kernelrelease、run ID。
- 只编译并上传 artifact，不从云端自动 SSH 到内网开发板，不发布正式 Release。

文件推送到默认分支后，在 Docker 容器中触发和查看：

```sh
gh workflow run typec-test-kernel.yml --repo ihexon/eaidk610-dev --ref main
gh run list --repo ihexon/eaidk610-dev --workflow typec-test-kernel.yml \
  --limit 5 --json databaseId,headSha,status,conclusion,url
```

核对 `headSha` 对应本次补丁，选定具体 run ID 后再监控和下载，不自动取不明来源的“最新产物”：

```sh
read -r typec_run_id
gh run watch "$typec_run_id" --repo ihexon/eaidk610-dev --exit-status
typec_artifacts=$(mktemp -d /home/ihexon/eaidk610-dev/typec-artifacts.XXXXXX)
gh run download "$typec_run_id" --repo ihexon/eaidk610-dev \
  --name eaidk610-typec-test --dir "$typec_artifacts"
```

在下载目录按实际产物结构执行 `sha256sum -c SHA256SUMS`，审查清单及归档路径。Artifact 下载使用当前 `ihexon` 的 `gh` API 登录。[触发说明](https://cli.github.com/manual/gh_workflow_run)、[下载说明](https://cli.github.com/manual/gh_run_download)、[Artifact API](https://docs.github.com/en/rest/actions/artifacts#download-an-artifact)

## 六、只向 .166 安装测试内核

### 6.1 安装前的门槛

先检查 `.166` 的版本、空间、当前启动配置和源文件哈希。确认串口可查看 U-Boot、能够中断自动启动，并已经明确如何从旧配置启动。串口使用 `1500000 8N1`，端口名按实际 USB 串口确认。

如果没有可用的串口/离线恢复办法，不进入远端重启测试。SSH 断开后不能依赖 SSH 本身恢复一个启动失败的内核。

远端之前的旧备份已清理，本次测试需要重新保存“一份当前可用配置”，不能使用旧 `.before-typec-overlay` 路径假定文件仍存在：

```sh
ssh ihexon@192.168.1.166
uname -r
df -h / /boot
cat /boot/extlinux/extlinux.conf
sudo test ! -e /boot/extlinux/extlinux.conf.before-typec-kernel
```

最后一条成功且前述检查通过后，才保存该回退配置：

```sh
sudo cp -p /boot/extlinux/extlinux.conf \
  /boot/extlinux/extlinux.conf.before-typec-kernel
```

已有同名备份时先检查内容，不覆盖。保留当前旧内核 Image、uInitrd、System.map、config 和 `/lib/modules/7.1.8-edge-rockchip64`，不卸载原软件包。

### 6.2 文件布局与切换

建议测试产物使用独立路径：

```text
/boot/typec-test-r1/Image
/boot/typec-test-r1/initrd.img
/boot/typec-test-r1/uInitrd
/boot/config-<实际测试 kernelrelease>
/boot/System.map-<实际测试 kernelrelease>
/lib/modules/<实际测试 kernelrelease>/
```

先普通用户解包并检查路径，再由临时部署脚本逐项安装；不把未经检查的归档直接解压到 `/`。脚本须核对目标机器、旧内核版本、可用空间、哈希和配置，失败时停止并恢复启动配置。

模块安装完成后，在 `.166` 生成匹配的 initramfs，不能复用旧内核的 uInitrd。下面仅为将来部署脚本的核心命令，前提是该版本 Image、config、模块和目标目录已经安装、核对：

```sh
typec_test_kernel=7.1.8-edge-rockchip64-eaidk610-typec-r1
sudo depmod -a "$typec_test_kernel"
sudo /usr/sbin/mkinitramfs -c gzip \
  -o /boot/typec-test-r1/initrd.img "$typec_test_kernel"
sudo mkimage -A arm64 -O linux -T ramdisk -C gzip \
  -n 'uInitrd typec-r1' -d /boot/typec-test-r1/initrd.img \
  /boot/typec-test-r1/uInitrd
```

脚本还需检查 initramfs 内容和镜像头，确认模块加载所需信息齐全。直接生成指定文件，不调用可能重写全局 Image/uInitrd 链接的自动升级步骤。

仅把 `.166` 当前 `LABEL Armbian` 内的两条路径切到：

```text
  LINUX /boot/typec-test-r1/Image
  INITRD /boot/typec-test-r1/uInitrd
```

`FDT`、`FDTOVERLAYS`、`APPEND` 和 root UUID 全部保留原值。Docker 容器不是开发板；所有 extlinux 和 `/boot` 操作都必须通过已核对目标的 `.166` SSH 会话执行。

用临时文件加 rename 更新配置，核对差异确实只有预期路径，执行 `sync`。通知用户即将中断连接，在串口已就绪时才执行 `.166` 的 `sudo reboot`。

## 七、验收方法与通过标准

重启后先验证进入正确测试版本、overlay 仍然加载、桥接模块来自匹配的模块目录，再测试功能：

```sh
uname -r
cat /proc/sys/kernel/random/boot_id
cat /sys/class/typec/port0/port_type
cat /sys/class/typec/port0/preferred_role
cat /sys/class/typec/port0/power_role
cat /sys/class/typec/port0/data_role
lsusb
lsusb -t
sudo dmesg | tail -n 120
```

自动协商验收必须从 `port_type=dual` 开始。先拔线，必要时恢复 dual，再进行全新的插入；不能在 Source-only 已成功连接后改回 dual，就记为自动插入成功。测试前提醒用户此次重选会中断 USB：

```sh
echo dual | sudo tee /sys/class/typec/port0/port_type
```

| 测试 | 最低要求 | 通过条件 |
| --- | --- | --- |
| Android C-to-C 正插 | 10 次完整拔插 | 不手动重选，自动 Source/Host，手机充电且枚举 |
| Android C-to-C 反插 | 10 次完整拔插 | 与正插一致；确认是在板端翻转插头 |
| 带手机启动 | 正反方向分别测试 | 启动后自动进入正确角色，不需 sysfs 干预 |
| 板子连接电脑 | 正反插、恢复后再接手机 | 电脑作为 Source 时板子正常 Sink/Device；再接手机自动恢复 Source/Host |
| 手机数据传输 | 用户选择文件传输模式 | 实际复制一个测试文件并核对内容，无反复断连 |
| 拔线与空闲 | 每轮检查 | partner 消失，VBUS 输出正确关闭，无工作项持续重试 |
| 错误与资源 | 每组测试后检查 | 无 I2C 错误洪泛、GPIO 冲突、WARN/Oops、模块版本错误 |

电脑是否枚举具体 USB 功能还依赖有效 gadget，不能把“没有配置 gadget”误判为角色切换失败。USB3 属于另一个验收维度；仅看到 480 Mbps 不足以宣称 USB3 已验证。

每轮短时间复现后立即保存 TCPM/FUSB302 日志，由一个采集程序读取，避免相互消耗环形日志。下面在 `.166` 执行，日志存入用户目录，便于 scp：

```sh
typec_log_dir=$(mktemp -d /home/ihexon/typec-test-log.XXXXXX)
uname -a > "$typec_log_dir/uname.txt"
sudo cat /sys/kernel/debug/usb/tcpm-4-0022/log > "$typec_log_dir/tcpm.log"
sudo cat /sys/kernel/debug/usb/fusb302-4-0022/log > "$typec_log_dir/fusb302.log"
sudo dmesg > "$typec_log_dir/dmesg.log"
lsusb -t > "$typec_log_dir/lsusb-tree.txt"
```

记录每轮插拔方向、设备/线缆、用户操作、充电表现和成败。修复后的关键证据应是有效 CC 分类及通知进入 TCPM，随后正常 Source 建连；不能仅以 `echo` 返回成功、GPIO 为高或 CI 绿色为结论。

## 八、失败回退与清理

若测试内核可 SSH 但出现回归，在 `.166` 恢复保存的 extlinux 配置，核对其指向旧 Image/uInitrd 后再重启：

```sh
sudo cp -p /boot/extlinux/extlinux.conf.before-typec-kernel \
  /boot/extlinux/extlinux.conf
cat /boot/extlinux/extlinux.conf
sudo sync
```

本段不附无条件重启命令；确认目标是 `.166`、日志已保存和串口就绪后再重启。若 SSH 无法进入，按安装前已经验证的 U-Boot 手动启动旧配置或离线恢复方法操作。

每次迭代保留一个可用旧内核和当前测试版本，部署/采集脚本执行后删除。清理失败版本前，确认它既不是 `uname -r` 的运行版本，也不被启动配置或任何软链接引用，再按明确版本目录删除，不能使用宽泛的 `/boot/*` 或 `/lib/modules/*` 删除命令。

最后交付：修复补丁、固定构建输入、workflow、可下载产物、校验清单、实测记录与回退说明。若全部验收通过，再评估去掉多余诊断日志并整理上游提交；若失败，只报告具体未通过项，继续围绕证据迭代。

旧计划中关于 `eaidk02` 上已部署 overlay、等待本机重启和本机回退文件的描述已不属于当前执行范围。当前唯一内核安装和重启目标是 `.166`，仍必须在用户知情且串口/离线恢复入口已确认后执行。

## 九、恢复工作时的第一件事

恢复工作时使用 run `34013982555` 的 artifact；其 SHA256 和包内 kernelrelease 已核验。下一步若要实机测试，先进入 `.166` 的串口/离线回退检查，再安装测试内核。当前不用再重复编译一个“只开普通日志”的内核；安装、重启和实测仍应围绕上述可验证的小范围改动推进。
