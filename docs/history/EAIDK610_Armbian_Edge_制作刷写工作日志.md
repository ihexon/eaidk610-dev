# EAIDK610 Armbian Edge 镜像制作与刷写工作日志

## 1. 最终结论

- 目标设备：OPEN AI LAB EAIDK-610，SoC 为 Rockchip RK3399，4 GiB 内存，单 eMMC 启动。
- 最终系统：Armbian Community 26.11.0-trunk.19 Trixie Minimal。
- 最终内核：`7.1.9-edge-rockchip64`。
- 使用设备树：`rockchip/rk3399-eaidk-610.dtb`。
- 使用自构建组合启动固件：`u-boot-rockchip.bin`，写入镜像 LBA 64，即字节偏移 32768。
- eMMC 根分区从 LBA 32768，即 16 MiB 处开始；U-Boot 位于分区前保留区，不覆盖根分区。
- 启动方式：U-Boot Distro Boot 扫描到 eMMC 第一分区的 `/boot/boot.scr`，由脚本加载内核、initrd 和 EAIDK-610 DTB。
- 串口：`/dev/ttyUSB0`，1500000 baud，8N1；Linux console 为 `ttyS2`。
- 最终验证：TPL/SPL、BL31、U-Boot、Linux 7.1.9、eMMC 根文件系统、以太网、SSH、串口登录均正常。

## 2. 最终文件及校验值

未压缩镜像修改完成时的信息：

```text
文件：Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img
大小：4265607168 bytes
SHA-256：5412a898ca54f820d0194a2bc1fdd4866731ecfca50a40aac723372d31694e46
```

启动固件：

```text
文件：u-boot-rockchip.bin
大小：9480704 bytes
SHA-256：c144dcc2607d3dee54da1c50c08b166f8d82f383ace246af95b1cd440be739f4
```

Maskrom 下载器：

```text
文件：rkbins/rk3399_loader_v1.30.130.bin
SHA-256：a7816076be4dc015a85188782d7eb4baedfa028ad0a90e348ec4c6b06efeb3fc
```

最终压缩包：

```text
文件：Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz
大小：1014147024 bytes
SHA-256：8f707c58a2330bbf23274d522e0657029b7281d6569c24de5512158264e3e2f2
```

SHA-256 同时写入同名 `.sha256` 文件，`xz -t` 完整性检查通过。

## 3. rkdeveloptool 通用启动 wrapper

主机上的 `rkdeveloptool` 是 AArch64 动态程序，运行时需要同目录的动态加载器和共享库。最终 wrapper 位于：

```text
rkdev/rkdeveloptool.sh
```

其核心执行方式为：

```sh
exec "${SCRIPT_DIR}/ld-linux-aarch64.so.1" \
    --library-path "${SCRIPT_DIR}" \
    "${SCRIPT_DIR}/rkdeveloptool" "$@"
```

检查连接设备：

```bash
lsusb
cd /home/ihexon/eaidk610_dev/rkdev
sudo ./rkdeveloptool.sh ld
```

Maskrom 模式下应识别到 Rockchip USB 设备 `2207:330c`。

## 4. 原始镜像选择

选择 Armbian Community 发布中的 Edge 内核镜像：

```text
Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz
```

选择理由：该镜像使用 `7.1.9-edge-rockchip64`，内核已启用 Rockchip 平台以及 RK3399 所需的 MMC 驱动，并自带：

```text
/boot/dtb-7.1.9-edge-rockchip64/rockchip/rk3399-eaidk-610.dtb
```

解压并立即删除压缩输入可使用：

```bash
unxz Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz
```

## 5. 在镜像中嵌入 U-Boot

U-Boot 写入 LBA 64，必须使用 `conv=notrunc`，否则普通文件输出可能在写入结束位置被截断：

```bash
dd if=u-boot-rockchip.bin \
   of=Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img \
   bs=512 seek=64 conv=notrunc status=progress
sync
```

验证嵌入内容：

```bash
dd if=Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img \
   bs=512 skip=64 count=18517 status=none | \
head -c 9480704 | cmp - u-boot-rockchip.bin
```

验证思路：只比较从字节偏移 32768 开始、长度为 9480704 字节的区域，确保镜像中的启动固件逐字节等于构建产物。

## 6. 修改 Armbian 启动配置

使用 loop 设备挂载镜像第一分区：

```bash
sudo losetup --find --show --partscan \
  Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img
sudo mount /dev/loop0p1 /mnt
```

最终 `/boot/armbianEnv.txt` 的关键配置：

```ini
verbosity=7
bootlogo=false
earlycon=on
console=both
extraargs=cma=256M
overlay_prefix=rockchip-rk3399
fdtfile=rockchip/rk3399-eaidk-610.dtb
rootdev=UUID=efea2db3-f410-4426-b549-bd8855f5a4f2
rootfstype=ext4
```

配置含义：

- `verbosity=7` 生成内核参数 `loglevel=7`，输出完整启动日志。
- `earlycon=on` 增加 `earlycon`，从内核最早期初始化开始输出。
- `console=both` 经 Armbian `boot.cmd` 转换为 `console=ttyS2,1500000 console=tty1`。
- `fdtfile` 强制使用 EAIDK-610 的 RK3399 设备树，不使用 LubanCat2 DTB。

修改 `boot.cmd` 后才必须重新生成 `boot.scr`；本次为保证镜像内脚本一致，也执行了：

```bash
sudo mkimage -C none -A arm64 -T script \
  -d /mnt/boot/boot.cmd /mnt/boot/boot.scr
```

安全完成镜像修改：

```bash
sync
sudo umount /mnt
sudo e2fsck -fn /dev/loop0p1
sudo losetup -d /dev/loop0
```

## 7. 写入 EAIDK-610 eMMC

让开发板进入 Maskrom 模式后，分两步执行。先下载临时 loader：

```bash
cd /home/ihexon/eaidk610_dev/rkdev
sudo ./rkdeveloptool.sh db ../rkbins/rk3399_loader_v1.30.130.bin
```

loader 下载成功并重新枚举 USB 后，写入完整镜像：

```bash
sudo ./rkdeveloptool.sh wl 0 \
  ../Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img
```

写入后复位：

```bash
sudo ./rkdeveloptool.sh rd
```

若 `db` 后 USB 正在重新枚举，不要把 `db` 和 `wl` 写在一条命令中；等待设备重新出现后单独执行 `wl`。

## 8. 刷写回读验证

回读 eMMC 前 16 MiB：

```bash
sudo ./rkdeveloptool.sh rl 0 0x8000 /tmp/eaidk610-readback-first16m.bin
```

其中 `0x8000` 是 32768 个 512 字节扇区，即 16 MiB。比较镜像头部：

```bash
head -c 16777216 \
  Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img \
  | cmp - /tmp/eaidk610-readback-first16m.bin
```

比较无输出且退出码为 0，表示 GPT、U-Boot 和根分区起始区域写入正确。

## 9. 串口日志

主机串口设备：

```text
/dev/ttyUSB0
1500000 baud
8 data bits
no parity
1 stop bit
```

实时查看：

```bash
sudo minicom -D /dev/ttyUSB0 -b 1500000 -8 -o
```

同时保存日志：

```bash
sudo minicom -D /dev/ttyUSB0 -b 1500000 -8 -o \
  -C eaidk610-edge-7.1.9-verbose-boot.log
```

最终日志已验证包含：

```text
U-Boot SPL 2026.10-rc3
U-Boot 2026.10-rc3
Booting Linux on physical CPU 0x0000000000
Linux version 7.1.9-edge-rockchip64
Armbian_community 26.11.0-trunk.19 Trixie ttyS2
```

## 10. 系统内修改与验证

SSH 登录：

```bash
ssh ihexon@192.168.1.177
```

检查内核和生效参数：

```bash
uname -a
cat /proc/cmdline
cat /sys/class/tty/console/active
systemctl status serial-getty@ttyS2.service --no-pager
systemctl is-system-running
```

已验证的实际参数：

```text
earlycon console=ttyS2,1500000 console=tty1 loglevel=7
```

已验证状态：

```text
ttyS2 tty1
serial-getty@ttyS2.service: active
systemctl is-system-running: running
```

## 11. `boot.scr` 与 extlinux 结论

本镜像继续使用 Armbian 的 `boot.cmd`/`boot.scr`，不切换 extlinux。理由：

- 当前 U-Boot 已实际扫描并成功执行 `/boot/boot.scr`。
- `boot.scr` 原生读取 `/boot/armbianEnv.txt`。
- Armbian 的 DTB、initrd、overlay 和 console 参数逻辑已完整保留。
- 日常参数只修改 `armbianEnv.txt`；只有修改 `boot.cmd` 时才重新运行 `mkimage`。

## 12. 最终打包命令

使用多线程、等级 6 打包；该等级兼顾发布镜像的压缩率、内存和耗时。`xz` 成功后默认删除未压缩源文件：

```bash
xz -T0 -6 -v \
  Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img
```

完整性检查：

```bash
xz -t Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz
```

生成压缩包校验文件：

```bash
sha256sum \
  Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz \
  > Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz.sha256
```

恢复未压缩镜像时使用：

```bash
unxz Armbian_community_26.11.0-trunk.19_Lubancat2_trixie_edge_7.1.9_minimal.img.xz
```
