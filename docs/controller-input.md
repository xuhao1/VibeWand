# 原生手柄接入 / Native controller input

VibeWand 0.5.5 的手柄模板默认接入 macOS GameController。USB 和系统已配对的蓝牙手柄使用同一输入路径，无需手填厂商编号或导入 HID 配置；已有自定义 HID 配置仍是显式覆盖。

The Controller layout uses macOS GameController by default. USB and system-paired Bluetooth controllers share the same input path; no vendor-ID setup or HID profile is required. An existing custom HID profile remains an explicit override.

## 输入与生命周期 / Input and lifecycle

- 按键按下/松开、R1/R2 单步导航、两根摇杆的八个方向、方向键与系统提供的扩展按键。
- 摇杆死区 0.22，回中阈值 0.16；首次重复等待 350 ms，之后每 90 ms 一步，不补发积压事件。
- 后台输入、自动发现、连接/断开通知与定期复核；保持当前手柄，避免混入另一台设备。
- 切换模板、断开、休眠或停止时取消按住状态；重新接入时已按住的键/偏离中心的摇杆须先松开/回中。
- 浮窗跟随模板切换图片、尺寸、热点、映射说明与状态；已隐藏的浮窗不会被切换模板重新弹出。

Inputs include press/release, R1/R2 steps, eight stick directions, the D-pad and extensions exposed by the system. Sticks use a 0.22 dead zone, 0.16 release zone, 350 ms initial repeat delay and 90 ms repeat interval. Background input, hotplug, periodic discovery, sleep/wake cleanup and suppression of pre-held input are implemented. The HUD changes with the selected layout while preserving hidden state.

## 触摸板与默认按键 / Touchpad and default buttons

0.5.5 使用 macOS 原生 `touchpadPrimary` 单指坐标控制系统光标；USB / 蓝牙共用这一路径。手指移动产生相对位移，首次落指、抬起、长时间没有样本、明显接触点跳变、断开和休眠均重新锚定，不把触摸板位置直接映射到屏幕位置。短按触摸板默认发送鼠标左键，可在动作库里重新配置。系统坐标处理覆盖负坐标的副屏和屏幕间空隙。

Version 0.5.5 reads the native `touchpadPrimary` finger coordinates over the same USB/Bluetooth backend. Movement is relative to the current system pointer. First contact, lift, stale samples, large discontinuities, disconnect and sleep re-anchor rather than jumping to an absolute screen location. A short touchpad press left-clicks by default and remains remappable. Display bounds support negative-origin monitors and gaps.

使用已有辅助功能权限；演示和只采集模式不发送鼠标移动或点击。切换到其他模板后移除旧触摸回调。当前仅单指移动与短按点击，不含轻点、双指滚动或拖拽。原生旧版接口没有独立的接触标记，未触摸时坐标为 `(0, 0)`；经过精确中心点时也会重新锚定。通用 HID 覆盖不提供原生触摸坐标。

The existing Accessibility permission applies. Demo/capture modes send no pointer events, and changing templates detaches the old callback. Only single-finger movement and short-press clicks are implemented, without taps, two-finger scrolling or dragging. The legacy native API reports `(0, 0)` without a separate contact flag, so crossing the exact center re-anchors too. A generic HID override does not supply native touch coordinates.

默认面键按用户习惯改成 **○ 确认 / Enter、□ 退格、× 返回**；× 双击切应用、长按会话 / 标签页，○ 长按模型 / 强度，△ 按住听写。选择器 / 应用切换器中 ○ 立即确认、× 立即取消、□ 不执行。默认阅读滚屏方向反转，文字光标、候选和应用前后方向保持原有逻辑。旧默认配置一次性升级，手动改配与时序保留。

Face buttons follow the requested **○ confirm / Enter, □ Backspace, × back** convention. Double × switches apps; long × opens chats/tabs; long ○ opens models/effort; hold △ dictates. In pickers/app switching, ○ confirms immediately, × cancels immediately and □ does nothing. Default reading scroll directions are reversed, while caret/selection/app navigation keep their directions. Old baseline mappings upgrade once; custom remaps and timings are preserved.

该面键习惯与 [Sony 当前 PS5 系统菜单说明](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/)中 × 选择、○ 取消不同；文档不将用户定制映射声称为 PS5 的统一默认。触摸接口参照 [Apple touchpadPrimary](https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad/touchpadprimary)，无接触与坐标方向约定参照 [Chromium 原生 GameController 实现](https://chromium.googlesource.com/chromium/src/+/refs/tags/149.0.7827.155/device/gamepad/game_controller_gamepad.mm)。

This user convention differs from [Sony's documented PS5 system-menu defaults](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/), which use × to select and ○ to cancel. Touch support uses [Apple's touchpadPrimary API](https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad/touchpadprimary), with release/polarity behavior checked against [Chromium's native GameController implementation](https://chromium.googlesource.com/chromium/src/+/refs/tags/149.0.7827.155/device/gamepad/game_controller_gamepad.mm).

## 验证记录 / Verification

2026-10-04：本机蓝牙手柄被系统和 VibeWand 原生后端识别。用户重新连接并操作后，物理采集记录得到 84 条事件，涵盖左右摇杆八个方向及方向键上/左/右；按下、回中/松开事件成对，结束时无残留按住状态。切换至其他模板，再切回手柄后能够自动重新接入。已恢复实时控制。

On 2026-10-04, macOS and VibeWand recognized the local Bluetooth controller. After the user reconnected and operated it, capture mode recorded 84 events across all eight stick directions and D-pad up/left/right. Press/release and neutral transitions were balanced with no stuck input. Returning to Controller from another layout automatically reattached it. Live control was restored.

130 项自动测试通过，包括原生 GameController 快照映射、生命周期、模板/手势隔离及浮窗几何与隐藏状态。自动测试不等同于全按键或音频实机验收。

All 130 automated tests passed, including native GameController snapshot mappings, lifecycle cleanup, layout/gesture isolation and HUD geometry/hidden state. This is not a claim that every physical button or audio route was tested.

USB 接入代码与蓝牙共用原生后端，但本轮未插线实测 USB。当前 macOS 原生接口没有提供参考手柄的静音键事件；麦克风是独立的系统音频输入，控制器识别不自动改变音源或启用录音。

USB is implemented through the same native backend, but no physical USB trial was performed in this pass. The native API does not expose the reference controller's mute button. Its microphone is a separate system audio endpoint; controller discovery does not change audio sources or start recording.

参考 / References: [Apple controller discovery](https://developer.apple.com/documentation/gamecontroller/discovering-game-controllers), [controller capability declaration](https://developer.apple.com/documentation/bundleresources/information-property-list/gcsupportedgamecontrollers).

0.5.5：137 项自动测试通过，新增触摸相对位移、抬手/断连/休眠、屏幕边界、采集/演示不注入事件、默认映射迁移与文字按键检查。触摸板实机验证单独记录；此前 84 条设备事件仅证明按钮/摇杆输入。

Version 0.5.5: all 137 automated tests passed, including relative touch motion, lift/disconnect/sleep, display bounds, capture/demo suppression, preset migration and text-button mappings. Physical touch verification is recorded separately; the earlier 84 events validate button/stick input only.
