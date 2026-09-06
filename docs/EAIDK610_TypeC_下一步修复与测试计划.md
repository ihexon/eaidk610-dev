# EAIDK-610 Type-C：下一步内核修复与测试计划

> 2026-09-06 计划更新：活动交付从独立内核包升级为 EAIDK610 完整
> Armbian edge 镜像。官方 `armbian/build` 固定为 submodule，我们只维护
> `userpatches/` 中的 board、kernel、U-Boot 与镜像定制。GitHub Actions 在
> ARM64 runner 构建、离线检查并发布 pre-release。详见
> `docs/构建架构与发布.md`；下文的 7.1 r1 记录作为已验证基线保留。

更新日期：2026-09-06。

## 结论与执行顺序

FUSB302 软件 Try.Source CC 状态更新补丁已经用 GitHub Actions 构建，并安装到 `ihexon@192.168.1.166`。测试板已成功重启进入独立版本 `7.1.8-edge-rockchip64-eaidk610-typec-r1`；首轮带手机反向插入启动在 `port_type=dual` 下自动进入 Source/Host、枚举手机，补丁定点日志证明新路径完成 Rd 分类并通知 TCPM。继续保留现有 Type-C overlay，不修改相同 DT 属性。

顺序：GitHub CLI 与仓库访问（已完成）→ 固定构建基线（已完成）→ 编写小范围驱动补丁和定点日志（已完成）→ ARM64 内核编译与打包（已完成）→ 建立远端回退入口（已完成）→ 安装并启动测试内核（已完成）→ 自动角色选择首轮验收（已通过）→ 发布 r1 pre-release（已完成）→ 正反插与角色切换回归 → 整理正式补丁。

本文同时记录当前执行进度。容器内的 GitHub 身份、HTTPS 仓库访问、固定构建输入、FUSB302 补丁和手动 workflow 已准备并推送。Actions run `34017439800` 通过标准 `./compile.sh kernel` 完成补丁应用、内核编译、模块/DTB 安装及四类 Debian 包生成，workflow 全绿，下载 artifact 的全部 SHA256 和关键归档成员复验通过；相同产物已发布为 GitHub pre-release [`eaidk610-typec-r1`](https://github.com/ihexon/eaidk610-dev/releases/tag/eaidk610-typec-r1)。image 与 DTB 包已经校验、安装并实机启动；首轮日志显示 `start unattached SRC toggling` 后正确测得 `Ra/Rd`，TCPM 随即进入 `SRC_ATTACHED` 和 `SRC_READY`。全面拔插与双角色回归尚未完成，因此暂不标记稳定版。

## 一、当前状态与不可突破的边界

| 项目 | 当前状态 |
| --- | --- |
| 执行端 | Docker 容器，工作区 `/home/ihexon/eaidk610-dev`；不是 EAIDK610，不承载板级 `/boot`、overlay 或 Type-C 硬件 |
| 测试板 | `ihexon@192.168.1.166`；运行 `7.1.8-edge-rockchip64-eaidk610-typec-r1`，原内核仍保留，overlay 已加载 |
| 已验证功能 | 带手机反向插入启动；从 `port_type=dual` 自动 Try.Source 到 Source/Host；OnePlus 8T 以 USB2 480 Mbps 枚举 |
| 未完成事项 | 正插、正反方向多次拔插、连接电脑的 Sink/Device、实际文件复制、拔线/VBUS 清理、USB3 和长期回归 |
| 远端最后一次检查 | 自动角色为 Source/Host，`orientation=reverse`、partner 存在，手机为 `18d1:4ee8`；Type-C 相关错误数为 0 |
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

### 3.1 采用 Armbian 标准 kernel 流程

当前 r1 的确由 Armbian build 驱动：`scripts/build-test-kernel.sh` 固定 build 提交后执行 `./compile.sh kernel`。框架负责取得固定 Linux 源码、按 rockchip64-7.1 的既定顺序应用补丁、放入板上配置、执行内核/模块/DTB 安装并生成 Debian 包。run `34013982555` 的日志显示总计应用 228 项，其中第 1 项是本仓库 FUSB302 补丁，其余为 Armbian rockchip64 补丁集；该补丁集明确包含 `typec-extcon` bridge、TCPM 修正、Rockchip USB PHY/charger detection 等改动。因此不能从纯上游 `25c76bea...` 加一份 FUSB302 补丁就直接替代当前内核。

本项目选择继续走 Armbian 正统 kernel 流程，不再维护传统 Kbuild/tar 的并行路线。GitHub Actions 只完成四件事：固定 Armbian 提交、把配置和补丁安装到标准 `userpatches` 路径、执行现代 kernel-only CLI、收集 Armbian 原生 `.deb`：

```sh
./compile.sh kernel \
  BOARD=rockpro64 \
  BRANCH=edge \
  KERNEL_CONFIGURE=no
```

必要的项目定制也全部使用 Armbian 支持的 `userpatches` 接口：板上配置放入 `userpatches/config/kernel/linux-rockchip64-edge.config`，FUSB302 补丁放入 `userpatches/kernel/archive/rockchip64-7.1/`。唯一的 family override 负责让测试内核拥有独立 kernelrelease；若仍使用默认 `rockchip64`，测试 Image、模块和 DTB 会与已知可用版本同名，无法安全并存。该 override 显式继承原 `linux-rockchip64-edge` 配置和 `archive/rockchip64-7.1` 补丁目录，不改变补丁基线。

构建脚本不再解开 `.deb`、复制 Image/System.map、重打 modules/DTB tar 包，也不解析 Armbian 内部源码目录或 `compile.h`。Armbian 成功后只复制 `output/debs/*.deb`，用 `dpkg-deb` 检查 image/DTB 包名、arm64 架构以及归档成员中的目标 kernelrelease、模块目录和 EAIDK610 DTB；这套轻量检查先用 run `34013982555` 的成功包离线通过，再由 run `34017439800` 的全量重建证明。新 run 的 r1 内核编译为 2217 秒、Armbian 打包为 54 秒，整个 job 为 42 分 6 秒，保留原生包不会显著增加时间。

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
- artifact 的 `SHA256SUMS` 改在构建命令及 `tee` 完全结束后由独立的 `if: always()` 步骤生成，避免散列计算后 `build.log` 仍被追加。早期 wrapper 曾解析 `include/generated/compile.h`，简化后的正统流程已删除这项非部署必需的解析。
- run `34012127716` 证明 family 修正有效：内核完成编译，image、DTB、headers、libc-dev 四个包均完成创建，版本和模块目录一致。随后仓库脚本的全树 `git diff --check` 命中 Armbian 既有 DTS 补丁中的空白字符并退出；这不是本次 FUSB302 文件的问题。检查范围因此收窄为 `drivers/usb/typec/tcpm/fusb302.c`，继续保留对本补丁的 whitespace 验证而不让无关基线告警阻断产物收集。
- run [`34013982555`](https://github.com/ihexon/eaidk610-dev/actions/runs/34013982555) 再次完成内核编译（2274 秒）和四类 Debian 包生成。artifact 中 `SHA256SUMS` 对日志及四个包全部校验通过；解开 image 包得到唯一模块目录 `7.1.8-edge-rockchip64-eaidk610-typec-r1`，内核镜像包含本补丁新增的日志字符串。workflow 只在包已上传后因 `compile.h` 使用制表符而未被元数据解析表达式匹配，最终显示失败；解析表达式已修正，但按“内核编译完成即可”的验收标准不再为此重复全量构建。
- run [`34017439800`](https://github.com/ihexon/eaidk610-dev/actions/runs/34017439800) 从简化提交 `4d82288ca488720b95e739e903054b651ec8be2b` 手动触发且全绿完成。外层为 GitHub 托管 `ubuntu-24.04-arm`，标准 `./compile.sh kernel` 步骤成功；日志确认本补丁以 `001/228` 应用并实际编译 `drivers/usb/typec/tcpm/fusb302.o`，内核编译 2217 秒、打包 54 秒，总 job 42 分 6 秒。下载 artifact 后 `SHA256SUMS` 全部通过，四个 `26.08.0-trunk` 软件包均为 arm64；image 包包含目标 `vmlinuz` 和模块目录，DTB 包包含 `rockchip/rk3399-eaidk-610.dtb`。image 与 DTB 包的 SHA-256 分别为 `00bc986e0f1864d245df7db5902a08197b8c0532790db473ad1dd50a7bcad353`、`ab825dc5d4badb64d9aefe48e871ecded6f3dd81b7d29364aa804af2c72053bf`。

这些记录说明早期问题在仓库外围校验，而不是 Armbian 没有编译出内核：run `34000886605` 已完成内核和模块，run `34012127716`、`34013982555` 还完成了四类包，run `34017439800` 则证明简化后的整条流程可以全绿结束。为避免以后在约 38 分钟之后才暴露脚本错误，workflow 先执行 `scripts/preflight-test-kernel-build.sh`，在任何下载和编译前检查：固定提交格式、config/补丁/family 文件 SHA-256、关键内核配置、family 与预期 kernelrelease 一致性及补丁语法。安装少量 runner 依赖后、启动 Armbian 前，再下载固定 Linux 提交的目标 `fusb302.c`，执行补丁精确 apply check。

Armbian `compile.sh kernel` 成功返回后，构建脚本立即写入 `KERNEL-BUILD-SUCCEEDED.txt` 并复制全部原生 `.deb`。之后只有已用现有成功包验证过的包元数据/成员名检查，不再访问易变化的 Armbian 内部 worktree，也不自行解包重打包。kernelrelease、image/DTB 包唯一性、模块目录和目标 DTB 仍是强校验，不能为了 workflow 变绿而放弃部署正确性。

## 五、仓库与 workflow 交付内容

当前仓库交付目录如下：

```text
eaidk610-dev/
├── .github/workflows/typec-test-kernel.yml
├── scripts/build-test-kernel.sh
├── scripts/preflight-test-kernel-build.sh
├── scripts/install-test-kernel-on-board.sh
├── scripts/check-typec-on-board.sh
├── kernel/build.env
├── kernel/config-7.1.8-edge-rockchip64
├── kernel/armbian/rockchip64-family.conf
├── kernel/patches/0001-usb-typec-fusb302-detect-unattached-source-connectio.patch
├── kernel/README.md
└── .gitignore
```

不要提交完整 Linux 源码树、编译输出、系统镜像和凭据。构建步骤写入 workflow；复杂安装和采集操作使用仓库内经语法检查的脚本，scp 到 `.166` 后一次执行，不在板上安装常驻修复服务。两个脚本不包含 sudo 密码、SSH 凭据或 GitHub token。

workflow 要求：

- 支持 `workflow_dispatch`，初期不因任意文档提交自动启动大规模编译。
- 所有不依赖编译产物的失败条件必须先由静态 preflight 检出；新增产物校验必须先用已有成功包离线测试，不能首次在 30 分钟后的产物上试验。
- 使用 GitHub 托管的 ARM64 `ubuntu-24.04-arm`，不把本地 Docker 执行容器或 `.166` 注册为自托管 runner；workflow 先在宿主核对 `uname -m=aarch64` 和 Debian `arm64` 架构。Armbian 可在该 ARM64 runner 内启动其 ARM64 构建容器，日志中的 `🐳` 和 OCI manifest 下载即来自这一层；完整编译仍全部发生在 GitHub Actions。[runner 说明](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- checkout、artifact 等第三方 action 固定到核实过的提交；权限从 `contents: read` 开始，不授予无关写权限。
- Linux、Armbian 补丁集、配置和补丁均可追溯；禁止静默换到 latest 内核。
- 通过测试专用 Armbian `LINUXFAMILY` 设置独立 `KERNELRELEASE` `7.1.8-edge-rockchip64-eaidk610-typec-r1`，使内核、模块目录、Debian 路径和包名一致；最终仍以构建输出值为准。
- 使用固定 Armbian `rockchip64-7.1` 补丁集和板上配置，完整编译 Image、模块与 DTB；不解包重打包，只检查原生 Debian 包的控制字段和归档成员名。失败时也上传构建日志和诊断信息。
- Artifact 直接包含 Armbian `output/debs` 原生包、构建清单、成功标记、SHA256SUMS 和构建日志，名称为 `eaidk610-typec-test`。
- Armbian 成功返回后立即落盘成功标记并保存原始包；影响启动安全的版本、模块目录和 DTB 校验仍须失败。
- 构建清单记录仓库提交、Linux/Armbian 提交、固定输入哈希、kernelrelease、run ID 和原生包版本。
- workflow 只编译并上传 artifact，不从云端自动 SSH 到内网开发板；人工复验后将 r1 的原生包、完整 artifact bundle、校验和与匹配安装脚本发布为 pre-release，不在 CI 中自动发布或自动部署。

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

## 六、只向 .166 安装测试内核（已完成）

### 6.1 产物、安装和回退入口

从 run `34013982555` 下载 artifact 后，只选用 image 和 DTB 软件包；headers、libc-dev 未上传也未安装。上传前后核对的 SHA-256 为：

```text
fb80950b87cbd85a212ed2425c5b6bc2bff234c54ac608682a49b35a711be39b  linux-image-edge-rockchip64-eaidk610-typec-r1_*.deb
c38792402dcad9aa00527c2ab487203183cfb8e860e6f8ca62e2f88643a4db2a  linux-dtb-edge-rockchip64-eaidk610-typec-r1_*.deb
```

安装前核对目标主机为 `armbian`、运行版本为 `7.1.8-edge-rockchip64`、root 文件系统有约 12 GiB 可用，并保存 extlinux 与启动链接状态。两个测试包有独立包名，因此没有覆盖或卸载原 `linux-image-edge-rockchip64`；以下原版恢复文件仍在：

```text
/boot/vmlinuz-7.1.8-edge-rockchip64
/boot/uInitrd-7.1.8-edge-rockchip64
/boot/dtb-7.1.8-edge-rockchip64/
/lib/modules/7.1.8-edge-rockchip64/
```

实际部署使用 `scripts/install-test-kernel-on-board.sh`。复杂操作先写成完整脚本，经 `bash -n` 和可用时的 ShellCheck 检查，再 scp 到 `/home/ihexon/eaidk610-typec-test/` 由 sudo 一次执行；密码只通过交互式 sudo 输入，未写入脚本、命令参数、环境、文件或日志。

Armbian image 包成功生成 `/boot/initrd.img-7.1.8-edge-rockchip64-eaidk610-typec-r1`，但目标系统没有负责同步生成新 `uInitrd` 的 initramfs post-update hook。首次部署检查因此在重启前停止。正式脚本随后用目标版本 initrd 生成 U-Boot legacy ramdisk，验证 64 字节 header 后的 payload 与 initrd 哈希完全一致，再原子替换目标 `uInitrd`。这保证没有复用旧内核 initramfs。

启动配置本身未改写，仍只有一个 `LABEL Armbian`：

```text
LINUX /boot/Image
INITRD /boot/uInitrd
FDT /boot/dtb/rockchip/rk3399-eaidk-610.dtb
FDTOVERLAYS /boot/overlay-user/rk3399-eaidk-610-typec-fix.dtbo
```

三个软链接在重启前均核对为测试版本，base DTB 与 overlay 通过 `fdtoverlay` 合并检查；备份保存在 `/boot/eaidk610-typec-backup-20260906-142239`。通知用户后执行重启，SSH 正常断开并在约 22 秒后恢复；boot ID 从 `f06223cb-8c8b-4e85-b7ac-af69d1fc7f9a` 变为 `8b24b245-36ad-49f0-a8f2-fb7221506077`，确认不是旧会话或未完成的重启。

### 6.2 当前运行状态

```text
uname -r: 7.1.8-edge-rockchip64-eaidk610-typec-r1
Image -> vmlinuz-7.1.8-edge-rockchip64-eaidk610-typec-r1
uInitrd -> uInitrd-7.1.8-edge-rockchip64-eaidk610-typec-r1
dtb -> dtb-7.1.8-edge-rockchip64-eaidk610-typec-r1
```

`dpkg --audit` 无输出，image 与 DTB 测试包状态均为 installed。`typec_extcon` 已加载，文件来自 `/lib/modules/7.1.8-edge-rockchip64-eaidk610-typec-r1/kernel/drivers/usb/typec/typec-extcon.ko`。测试板已证明能够从完整的新 Image、initramfs、模块目录、DTB 和原 overlay 启动；不再需要为相同补丁重复耗时的内核构建。

## 七、验收方法与通过标准

首次重启验收已完成。手机在板端反向插入并带线启动，期间没有手动写 sysfs：测试内核从 `port_type=dual` 自动进入 Source/Host，`orientation=reverse`、`power_operation_mode=1.5A`、partner 存在；OnePlus 8T 以 `18d1:4ee8` 在 USB2 480 Mbps 下枚举。

debugfs 给出了修复路径的直接证据：开机 4.485062 秒记录 `start unattached SRC toggling for Rp-1.5`，随后测得 `cc1=Ra, cc2=Rd` 并通知 TCPM；TCPM 从 `SRC_TRY_WAIT` 进入 `SRC_TRY_DEBOUNCE`、`SRC_ATTACHED`，最后到 `SRC_READY`。本次启动未发现 FUSB302/TCPM/Type-C warning/error。完整日志在板上 `/home/ihexon/typec-test-log-8b24b245-36ad-49f0-a8f2-fb7221506077`，采集脚本为 `scripts/check-typec-on-board.sh`。

以上只完成“带手机启动、反向、一次”的首轮场景，不能替代下面的完整验收。后续每轮仍先验证运行版本、overlay 和实际角色：

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

当前进度：带手机反向启动 1 次通过，错误与资源的首轮检查通过；表内其余次数和方向仍未执行。手机是否显示充电、实际文件复制、拔线后的 VBUS 关闭必须结合用户现场观察，不能只依据 SSH/sysfs 推断。

电脑是否枚举具体 USB 功能还依赖有效 gadget，不能把“没有配置 gadget”误判为角色切换失败。USB3 属于另一个验收维度；仅看到 480 Mbps 不足以宣称 USB3 已验证。

每轮短时间复现后立即保存 TCPM/FUSB302 日志，由一个采集程序读取，避免相互消耗环形日志。复杂采集操作使用脚本 scp 到 `.166` 后一次执行：

```sh
scp scripts/check-typec-on-board.sh \
  ihexon@192.168.1.166:/home/ihexon/eaidk610-typec-test/
ssh -t ihexon@192.168.1.166 \
  'sudo /home/ihexon/eaidk610-typec-test/check-typec-on-board.sh'
```

记录每轮插拔方向、设备/线缆、用户操作、充电表现和成败。修复后的关键证据应是有效 CC 分类及通知进入 TCPM，随后正常 Source 建连；不能仅以 `echo` 返回成功、GPIO 为高或 CI 绿色为结论。

## 八、失败回退与清理

若测试内核可 SSH 但出现回归，不需要改写内容未变的 extlinux；在 `.166` 将三个明确的软链接恢复到保留的旧版本，核对后再重启：

```sh
sudo ln -sfn vmlinuz-7.1.8-edge-rockchip64 /boot/Image
sudo ln -sfn uInitrd-7.1.8-edge-rockchip64 /boot/uInitrd
sudo ln -sfn dtb-7.1.8-edge-rockchip64 /boot/dtb
readlink /boot/Image
readlink /boot/uInitrd
readlink /boot/dtb
sudo sync
```

本段不附无条件重启命令；确认目标是 `.166`、日志已保存和串口就绪后再重启。若 SSH 无法进入，按安装前已经验证的 U-Boot 手动启动旧配置或离线恢复方法操作。

当前不回退也不卸载：测试内核已经正常启动，旧内核作为恢复版本继续保留。清理失败版本前，确认它既不是 `uname -r` 的运行版本，也不被启动配置或任何软链接引用，再按明确版本目录删除，不能使用宽泛的 `/boot/*` 或 `/lib/modules/*` 删除命令。

最后交付：修复补丁、固定构建输入、workflow、可下载产物、校验清单、实测记录与回退说明。若全部验收通过，再评估去掉多余诊断日志并整理上游提交；若失败，只报告具体未通过项，继续围绕证据迭代。

旧计划中关于 `eaidk02` 上已部署 overlay、等待本机重启和本机回退文件的描述已不属于当前执行范围。当前唯一内核安装和重启目标是 `.166`，仍必须在用户知情且串口/离线恢复入口已确认后执行。

## 九、恢复工作时的第一件事

测试内核已安装并启动；简化后的正统 Armbian 流程也已由 run `34017439800` 从提交 `4d82288ca488720b95e739e903054b651ec8be2b` 完成全量重建、绿色 workflow 和下载后包内容复验，验证产物已发布为 pre-release `eaidk610-typec-r1`。本次只是重建和发布相同 r1，没有重复部署到 `.166`。恢复实机测试时先确认 `.166` 仍运行 `7.1.8-edge-rockchip64-eaidk610-typec-r1`，然后在用户配合下完成正插、正反方向多次拔插、拔线/VBUS、电脑 Sink/Device 和实际文件传输测试，每组用 `scripts/check-typec-on-board.sh` 留证。后续 r2 继续使用相同的 Armbian `userpatches + ./compile.sh kernel + 原生 .deb` 流程。
