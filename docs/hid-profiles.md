# 其他 HID 设备与重映射

[硬件与模板](device-templates.md) · [问题排查](troubleshooting.md) · [文档目录](README.md)

设备协议与应用操作分开配置。AU05 使用内置握手和报告协议；系统支持的手柄使用 macOS GameController 自动识别，无需配置文件；其他设备可以用标准 HID usage 配置接入。「设置 → 设备与按键」的照片热点、方向列表与动作库，将物理输入映射为会话、左右移动、听写、确认、取消、模型 / 强度、原生 Escape 或禁用。配置保存在本机，修改时取消旧按住状态。

VibeKey、手柄、遥控器分别保存手势与设备配置。手柄通过 USB 连接或 macOS 蓝牙配对后自动检测；本页的 HID 导入是高级兼容覆盖，适合已采集到准确映射的设备，不是手柄连接的前置步骤。遥控器目前仍需实测 HID 配置。手柄可在「连接设备… → 高级兼容设置」移除覆盖，恢复自动识别。配置不会猜测设备 VID / PID；音频不通过 HID 配置接入。

Supported USB or paired Bluetooth controllers are detected automatically through macOS GameController. The profiles on this page are optional advanced overrides for Controller, and are still required for Remote. Remove the Controller override in Advanced compatibility to return to automatic detection. Pairing and microphone selection remain macOS settings.

## 获取设备描述

```sh
swift run AU05Capture --list > hid-interfaces.json
```

这条命令只读取接口和 input element 描述，不监听普通键盘输入、不输出设备序列号。输出含 `vendorID`、`productID`、接口 `usagePage` / `usage`，以及各 input element 的 usage、逻辑范围和 `relative` 属性。

复制 [键盘类配置示例](../profiles/generic-keypad.example.json)，替换 **设备与接口标识**，并按描述修改 bindings。示例 VID `4660` / PID `1` 是占位值，不能当作支持过的硬件。示例使用 F13–F16 作为四个按钮，左右箭头作为旋转事件；应先将可编程设备的相应控件设成这些 HID 键。使用厂商的配置工具完成一次设备配置，不要求该工具后台运行。

## 配置字段

| 字段 | 含义 |
| --- | --- |
| `name` | GUI 显示的设备名称 |
| `match` | 一个明确的 VID / PID / primary usage page / usage 接口 |
| `exclusiveAccess` | 是否独占这个明确选中的接口，退出后释放 |
| `bindings[].usagePage` / `usage` | input element 标识 |
| `bindings[].kind` | `button`、`pulse`、`relative`、`absolute` 或回中摇杆 `axis` |
| `bindings[].control` | 主按键对应 `voice`、`ok`、`escape`、`dial`；单次导航使用 `left` / `right`；扩展按键见下表 |
| `bindings[].inverted` | 轴方向取反，默认 false |
| `bindings[].negativeControl` / `positiveControl` | 仅 `axis` 使用，分别对应中心负向 / 正向的逻辑摇杆方向 |
| `bindings[].deadZone` | `axis` 启动死区，按中心到端点的半程比例，默认 0.22 |
| `bindings[].releaseZone` | `axis` 回中释放范围，默认 0.16；不得大于 `deadZone` |

`button` 保留按下和松开，因此支持听写按住与长按。`pulse` 在从 0 变成非 0 时产生一次动作，适合用箭头键表示旋转；重复键值不会产生重复脉冲。`relative` 按增量产生左右刻度，`absolute` 以与上次位置的差产生刻度，第一次读到的位置不造成移动。每份轴值最多输出 32 个刻度。`absolute` 暂不处理环形编码器跨边界回绕；此类设备需要专用解码或输出 relative usage。

手柄与遥控器的扩展按键可以使用以下逻辑名称。附加按钮默认不执行动作，在图形设置中按需要分配单击、双击、长按或按住动作；摇杆方向使用独立的持续导航绑定。名称只决定逻辑输入，不会自动识别硬件的 usage 或启用原生电源、音量功能。

| 控件 | 逻辑输入名（按钮 `control` / 轴正负方向） |
| --- | --- |
| 左肩键与左扳机 | `l1`、`l2` |
| 摇杆按压 | `leftStickPress`、`rightStickPress` |
| 左摇杆方向 | `leftStickUp`、`leftStickDown`、`leftStickLeft`、`leftStickRight` |
| 右摇杆方向 | `rightStickUp`、`rightStickDown`、`rightStickLeft`、`rightStickRight` |
| 独立方向键 | `dpadUp`、`dpadDown`、`dpadLeft`、`dpadRight` |
| 附加功能键 | `options`、`create`、`home`、`touchpad`、`mute` |
| 遥控器电源与音量键 | `power`、`volumeUp`、`volumeDown` |

摇杆按压和触摸板按压是按钮输入。摇杆移动使用下述 `axis` 解码，触摸板手势、方向帽枚举拆分与模拟扳机阈值仍需对应的专用解码。AU05 固件协议保持原有六种物理输入。

相对滚轮绑定示例：

```json
{ "usagePage": 1, "usage": 56, "kind": "relative", "inverted": false }
```

这种轴绑定不填写 `control`。多个按钮可指向同一个操作，最后一个按钮松开时才释放该操作。

键盘 / Consumer / Generic Desktop 接口必须设置 `exclusiveAccess: true`，防止系统原本的快捷键与 VibeWand 操作同时执行。它只接管配置明确选中的接口；如果配置指向你的日常键盘，该键盘在 VibeWand 运行期间会被接管。因此应选择专用控制器，核对 VID / PID 和接口后导入。多个相同接口存在时拒绝启动；不自动挑第一个设备。输入监测授权可能需要使用者在系统设置完成。

## 回中摇杆轴

回中摇杆使用 `axis`，不能用 `absolute` 位置差编码器代替：编码器会把回中误当成反向转动。每个轴绑定两个不同的方向；同一方向不得重复分配到多个轴。轴的最小值、最大值和中点来自实际 HID 描述，不在配置里猜测固定范围。

下面仅演示一个横轴的字段，**不是已验证设备配置**；`usagePage` 和 `usage` 都须用目标接口实测值替换。常见 X / Y usage 也不能代替对实际设备的检查。

```json
{
  "usagePage": 1,
  "usage": 48,
  "kind": "axis",
  "negativeControl": "leftStickLeft",
  "positiveControl": "leftStickRight",
  "deadZone": 0.22,
  "releaseZone": 0.16,
  "inverted": false
}
```

为纵轴指定 `leftStickUp` / `leftStickDown`，右摇杆用相应 `rightStick…` 名称；正负方向与画面相反时设置 `inverted: true`。`axis` 不填写 `control`。方向上 / 下、左 / 右都在设置中的「摇杆」分组单独配置，不与 L3 / R3 按下混用。

- 默认 `deadZone: 0.22` 表示超过中心到端点距离的 22% 才启动；有效范围为 0.05–0.8。
- 默认 `releaseZone: 0.16` 表示回到 16% 内才释放，形成迟滞以减少边缘抖动；有效范围为 0–`deadZone`。
- 跨过启动阈值立即发出方向按下和一次导航脉冲；保持 350 ms 后每 90 ms 重复一次。回中发出松开并停止重复，直接反向会先释放旧方向再启动新方向。
- 重复是固定频率，不按推动幅度加速。无效逻辑范围会停止运动；断开、睡眠和更换设备配置停止重复并清理按住状态。

采集时至少检查静止漂移、四个方向、斜向双轴、保持、缓慢回中、快速反向与断开。输入链路与自动测试已经实现，**没有据此宣称实体手柄经过验收**。

### Centered-stick axes (English)

Use `kind: "axis"` for a spring-centered stick. `negativeControl` and `positiveControl` select the two logical directions; omit `control`. Valid names are `leftStickUp/Down/Left/Right` and `rightStickUp/Down/Left/Right`. The sample above demonstrates fields only: replace its usage identifiers after inspecting the actual device. Logical minimum, maximum, and midpoint come from that device's HID descriptor.

The default activation threshold is 22% of half-range (`deadZone`, allowed 0.05–0.8). Release occurs within 16% (`releaseZone`, allowed 0–`deadZone`), providing hysteresis. Crossing the threshold sends down plus an immediate navigation pulse; holding repeats after 350 ms, then every 90 ms. Neutral sends up and stops repetition; reversing releases the previous direction before starting the next. There is no magnitude-based acceleration. Invalid ranges, disconnect, sleep, and profile replacement stop active motion. This implemented input path does not establish physical-device compatibility.

## 导入与测试

1. 退出占用该设备的配置应用。
2. 在「设置 → 设备与按键 → 连接设备…」中导入 HID 配置。无效或重复的 usage 会被拒绝。
3. 先在「设置 → 开发者」启用「只采集物理事件」，查看每个已配置输入及其释放事件是否正确，再关闭采集模式。
4. 如需恢复默认接入方式，解除当前模板的 HID 绑定；手柄选择「恢复自动识别」，VibeKey 恢复 AU05 内置协议。正常退出或切换设备会释放接口、清除按住状态和我们生成的 Fn。

也可通过 CLI 采集归一化后的事件：

```sh
swift run AU05Capture --profile /absolute/path/controller.json --duration 30
```

这个命令不合成应用快捷键；若选择独占接口，原来的系统按键也暂停传递，退出时恢复。用 Ctrl+C 或正常 SIGTERM 结束，会执行清理。

## 当前兼容边界

通用后端使用 independent-devices manager 发现接口，核对唯一匹配后才单独打开选中接口，避免 manager 提前以共享模式打开设备。独占语义参考 [Apple IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen)。已实现 standard HID input value 接入和配置解析；自动测试覆盖按键共享、释放、相对 / 绝对编码器轴、回中轴死区 / 迟滞 / 重复 / 反向与非法配置。此处描述的是通用 HID 后端；手柄默认使用独立的 GameController 后端。完整硬件验收需按具体型号、连接方式及实际公开的控件记录，不能由配置通过校验推断。

使用加密 vendor report、需要厂商握手、单份报告中打包多个非标准字段、LED / 屏幕私有命令的设备，需要添加自己的 `HIDEventSource` 实现。配置文件不能自动破解或猜测这些协议。应用层只消费统一事件，因此添加设备无需修改 Codex 交互状态机。
