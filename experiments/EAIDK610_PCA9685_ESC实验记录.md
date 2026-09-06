# EAIDK610 + PCA9685 + Hobbywing 40A ESC 实验日志

## 1. 目标

验证 EAIDK610 是否能够通过 PCA9685 驱动无人机 ESC，再由 ESC 驱动无刷电机做台架实验。

最终结论：

- EAIDK610 可以作为上位控制器；
- PCA9685 可以作为 PWM 中继；
- Hobbywing 40A ESC 能被 PCA9685 正常驱动；
- 电机可以稳定起转、加速、停止。

## 2. 实验环境

- 开发板：EAIDK610
- 系统：主线内核 DTS
- 远端登录：`ihexon@192.168.1.142`
- 远端主机名：`armbian`
- I2C 设备：`/dev/i2c-2`
- PWM 扩展板：PCA9685
- ESC：Hobbywing 40A
- 电源：6S 电池
- 电机：无人机无刷电机
- 台架要求：已拆桨

## 3. 文件与交付物

最终相关文件放在 `/home/ihexon/eaidk610`：

- [EAIDK-610原理图.pdf](/home/ihexon/eaidk610/EAIDK-610原理图.pdf)
- [EAIDK-610用户使用手册.pdf](/home/ihexon/eaidk610/EAIDK-610用户使用手册.pdf)
- [rk3399-eaidk-610-i2c2-overlay.dts](/home/ihexon/eaidk610/rk3399-eaidk-610-i2c2-overlay.dts)
- [rk3399-eaidk-610-i2c2-overlay.dtbo](/home/ihexon/eaidk610/rk3399-eaidk-610-i2c2-overlay.dtbo)
- [extlinux.conf](/home/ihexon/eaidk610/extlinux.conf)
- [EAIDK610_PCA9685_ESC实验记录.md](/home/ihexon/eaidk610/EAIDK610_PCA9685_ESC实验记录.md)
- 独立控制程序：`/tmp/eaidk610-pca9685-escctl`

## 4. 总体结论

最终确认的工作链路：

```text
EAIDK610 -> I2C2 -> PCA9685 -> PWM -> ESC -> 电机
```

最终可用参数：

- PWM 频率：`50Hz`
- 起转点：约 `1111us`
- 明显加速：约 `1333us`
- 满端：`2000us`

## 5. 接线结论

### 5.1 EAIDK610 -> PCA9685

```text
EAIDK610 3.3V -> PCA9685 VCC
EAIDK610 GND  -> PCA9685 GND
EAIDK610 SDA  -> PCA9685 SDA
EAIDK610 SCL  -> PCA9685 SCL
```

### 5.2 PCA9685 -> ESC

```text
PCA9685 某一路 PWM -> ESC 白色 PWM 线
PCA9685 GND         -> ESC/PDB 公共地
```

说明：

- `V+` 未使用；
- ESC 的白线是信号线；
- 必须共地；
- PCA9685 的地要和 ESC/PDB/电池负极同地；
- 不要把 PCA9685 接到 6S 正极。

### 5.3 ESC -> 电池 / 电机

```text
ESC 厚线 -> 6S 电池 / PDB
ESC 三相 -> 无刷电机
```

## 6. 关键问题与解决过程

### 6.1 先确认 EAIDK610 的 I2C2 是否真的启用

#### 问题

系统最初只看到 `i2c-20`、`i2c-21`，无法直接判断 `i2c2` 是否可用。

#### 解决方法

查看设备树和设备节点：

```bash
ls /dev/i2c-*
ls /sys/bus/i2c/devices
readlink -f /sys/bus/i2c/devices/i2c-2/of_node
tr -d '\0' < /proc/device-tree/aliases/i2c2
```

#### 结果

- `/dev/i2c-2` 存在；
- `/sys/bus/i2c/devices/i2c-2` 对应 `/i2c@ff120000`；
- `i2c2` 已启用。

### 6.2 overlay 最初无法编译

#### 问题

`rk3399-eaidk-610-i2c2-overlay.dts` 最初写法不符合 overlay 结构，`fragment@0` 不在根节点 `/ { ... }` 内，导致 `dtc -@` 报错。

#### 解决方法

将 overlay 改成标准结构：

```dts
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/i2c@ff120000";
        __overlay__ {
            status = "okay";
            clock-frequency = <100000>;
        };
    };
};
```

#### 编译命令

```bash
dtc -@ -I dts -O dtb \
  -o /home/ihexon/eaidk610/rk3399-eaidk-610-i2c2-overlay.dtbo \
  /home/ihexon/eaidk610/rk3399-eaidk-610-i2c2-overlay.dts
```

#### 验证方法

```bash
fdtoverlay -i /boot/dtb/rockchip/rk3399-eaidk-610.dtb \
  -o /tmp/rk3399-eaidk-610-i2c2-test.dtb \
  /tmp/rk3399-eaidk-610-i2c2-overlay.dtbo
```

验证结果中可见：

```text
i2c@ff120000 {
    clock-frequency = <0x186a0>;
    pinctrl-0 = <0x3b>;
    status = "okay";
}
```

### 6.3 extlinux.conf 挂载 overlay

#### 结果

通过 `extlinux.conf` 加入：

```conf
FDT /boot/dtb/rockchip/rk3399-eaidk-610.dtb
FDTOVERLAYS /boot/dtb/rockchip/overlay/rk3399-eaidk-610-i2c2-overlay.dtbo
```

#### 验证

重启后确认：

```bash
ls -l /dev/i2c-*
readlink -f /sys/bus/i2c/devices/i2c-2/of_node
```

### 6.4 运行程序时报权限错误

#### 问题

首次执行独立二进制时，直接访问 `/dev/i2c-2` 报：

```text
Permission denied: '/dev/i2c-2'
```

#### 解决方法

把用户加入 `i2c` 组后重新登录：

```bash
sudo usermod -aG i2c ihexon
```

验证：

```bash
id
```

结果中应包含 `i2c` 组。

### 6.5 先前多次无反应、持续滴滴声

#### 现象

前几轮测试中，电机持续发出有规律滴滴声，但不转。

#### 排查方向

- PWM 频率是否合适；
- 是否共地；
- 是否做了 ESC 油门校准；
- 是否接到了真正的 PWM 输入；
- 是否只是起转阈值太低。

#### 处理

1. 确认 PCA9685 与 ESC/PDB 共地；
2. 执行 ESC 油门校准；
3. 提高测试脉宽到 `1200us`、`1400us`、`1600us`、`1800us`；
4. 最终做 10 段连续爬升测试。

#### 结果

在连续爬升测试中：

- 第 2 段 `1111.1us` 开始低速起转；
- 第 4 段 `1333.3us` 开始明显加速；
- `1800us`、`2000us` 均能正常驱动；
- 重复测试一致。

## 7. 控制程序

### 7.1 生成方式

使用 `uv` + `pyinstaller` 打包为独立二进制。

#### 编译命令

```bash
python3 -m py_compile eaidk610_pca9685_escctl.py
uv run --with pyinstaller pyinstaller --onefile --name eaidk610-pca9685-escctl eaidk610_pca9685_escctl.py
```

#### 产物

```text
/home/ihexon/dronAuto/dist/eaidk610-pca9685-escctl
```

#### 上传

```bash
scp /home/ihexon/dronAuto/dist/eaidk610-pca9685-escctl ihexon@192.168.1.142:/tmp/eaidk610-pca9685-escctl
```

### 7.2 程序功能

- 打开 `/dev/i2c-2`；
- 配置 PCA9685 频率；
- 向所有 channel 同时输出相同 PWM；
- 支持单次脉冲；
- 支持交互式校准；
- 支持 10 段连续爬升测试。

## 8. 主要测试命令

### 8.1 基础低油门测试

```bash
/tmp/eaidk610-pca9685-escctl \
  --bus 2 \
  --channels 0-15 \
  --prime-us 1000 \
  --prime-seconds 2 \
  --pulse-us 1050 \
  --duration 3 \
  --stop-us 1000 \
  --stop-seconds 2
```

### 8.2 校准模式

```bash
sudo /tmp/eaidk610-pca9685-escctl \
  --bus 2 \
  --channels 0-15 \
  --calibrate \
  --prime-us 1000 \
  --prime-seconds 2 \
  --pulse-us 2000 \
  --stop-us 1000 \
  --stop-seconds 2
```

### 8.3 单次高油门测试

```bash
/tmp/eaidk610-pca9685-escctl \
  --bus 2 \
  --channels 0-15 \
  --prime-us 1000 \
  --prime-seconds 2 \
  --pulse-us 1800 \
  --duration 8 \
  --stop-us 1000 \
  --stop-seconds 2
```

### 8.4 连续爬升测试

```bash
/tmp/eaidk610-pca9685-escctl \
  --bus 2 \
  --channels 0-15 \
  --prime-us 1000 \
  --stop-us 2000 \
  --ramp-steps 10 \
  --stop-seconds 2
```

每段保持 20 秒，实际输出步骤如下：

- Step 1/10: `1000.0us`
- Step 2/10: `1111.1us`
- Step 3/10: `1222.2us`
- Step 4/10: `1333.3us`
- Step 5/10: `1444.4us`
- Step 6/10: `1555.6us`
- Step 7/10: `1666.7us`
- Step 8/10: `1777.8us`
- Step 9/10: `1888.9us`
- Step 10/10: `2000.0us`

## 9. 测试结果

### 9.1 起转与加速区间

重复测试后确认：

- `1000us` 为停转/最小输出；
- `1111us` 左右开始低速转动；
- `1333us` 左右进入明显加速；
- `2000us` 正常满端。

### 9.2 电机停止

通过再次发送 `1000us` 输出，电机可停止。

```bash
/tmp/eaidk610-pca9685-escctl \
  --bus 2 \
  --channels 0-15 \
  --prime-us 1000 \
  --prime-seconds 0 \
  --pulse-us 1000 \
  --duration 1 \
  --stop-us 1000 \
  --stop-seconds 0
```

## 10. 经验与注意事项

- PCA9685 和 ESC 必须共地；
- ESC 白线单独接上不够；
- `VCC` 只给 PCA9685 逻辑电源，不要接成 `V+`；
- 台架实验必须拆桨；
- 先校准，再做爬升测试；
- 如果 ESC 持续滴滴声，优先查共地、校准和输入阈值；
- 这套 ESC 对 `50Hz` 标准 PWM 可用。

## 11. 最终状态

当前实验已完成，电机可正常受控运行。
