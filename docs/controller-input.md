# 原生手柄接入 / Native controller input

VibeWand 0.5.6 的手柄模板默认接入 macOS GameController。USB 和系统已配对的蓝牙手柄使用同一输入路径，无需手填厂商编号或导入 HID 配置；已有自定义 HID 配置仍是显式覆盖。

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

默认面键按用户习惯改成 **○ 确认 / Enter、□ 退格、× 返回**；× 双击切应用、长按会话 / 标签页，○ 长按模型 / 强度，△ 按住听写。会话选择器中 × 立即确认、○ 返回；模型 / 强度 / 应用切换中 ○ 立即确认、× 返回。选择器内 □ 不执行。默认阅读滚屏方向反转，文字光标、候选和应用前后方向保持原有逻辑。旧默认配置一次性升级，手动改配与时序保留。

Face buttons follow the requested **○ confirm / Enter, □ Backspace, × back** convention. Double × switches apps; long × opens chats/tabs; long ○ opens models/effort; hold △ dictates. The chat picker uses × to confirm and ○ to cancel. Model/effort pickers and app switching retain ○ confirm / × cancel. All picker confirmations are immediate and □ does nothing there. Default reading scroll directions are reversed, while caret/selection/app navigation keep their directions. Old baseline mappings upgrade once; custom remaps and timings are preserved.

该面键习惯与 [Sony 当前 PS5 系统菜单说明](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/)中 × 选择、○ 取消不同；文档不将用户定制映射声称为 PS5 的统一默认。触摸接口参照 [Apple touchpadPrimary](https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad/touchpadprimary)，无接触与坐标方向约定参照 [Chromium 原生 GameController 实现](https://chromium.googlesource.com/chromium/src/+/refs/tags/149.0.7827.155/device/gamepad/game_controller_gamepad.mm)。

This user convention differs from [Sony's documented PS5 system-menu defaults](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/), which use × to select and ○ to cancel. Touch support uses [Apple's touchpadPrimary API](https://developer.apple.com/documentation/gamecontroller/gcdualsensegamepad/touchpadprimary), with release/polarity behavior checked against [Chromium's native GameController implementation](https://chromium.googlesource.com/chromium/src/+/refs/tags/149.0.7827.155/device/gamepad/game_controller_gamepad.mm).

## 验证记录 / Verification

2026-10-04：本机蓝牙手柄被系统和 VibeWand 原生后端识别。用户重新连接并操作后，物理采集记录得到 84 条事件，涵盖左右摇杆八个方向及方向键上/左/右；按下、回中/松开事件成对，结束时无残留按住状态。切换至其他模板，再切回手柄后能够自动重新接入。已恢复实时控制。

On 2026-10-04, macOS and VibeWand recognized the local Bluetooth controller. After the user reconnected and operated it, capture mode recorded 84 events across all eight stick directions and D-pad up/left/right. Press/release and neutral transitions were balanced with no stuck input. Returning to Controller from another layout automatically reattached it. Live control was restored.

130 项自动测试通过，包括原生 GameController 快照映射、生命周期、模板/手势隔离及浮窗几何与隐藏状态。自动测试不等同于全按键或音频实机验收。

All 130 automated tests passed, including native GameController snapshot mappings, lifecycle cleanup, layout/gesture isolation and HUD geometry/hidden state. This is not a claim that every physical button or audio route was tested.

USB 接入代码与蓝牙共用原生后端，但本轮未插线实测 USB。当前 macOS 原生接口没有提供参考手柄的静音键事件；麦克风是独立的系统音频输入，控制器识别不自动改变音源或启用录音。

USB is implemented through the same native backend, but no physical USB trial was performed in this pass. The native API does not expose the reference controller's mute button. Controller discovery does not change audio sources or start recording. A separate [Bluetooth microphone experiment](dualsense-microphone.md) received and decoded Opus audio on the current Mac, and a later standalone prototype published a system input with significantly fewer gaps using Game Mode. Residual loss and production integration remain open.

参考 / References: [Apple controller discovery](https://developer.apple.com/documentation/gamecontroller/discovering-game-controllers), [controller capability declaration](https://developer.apple.com/documentation/bundleresources/information-property-list/gcsupportedgamecontrollers).

0.5.5：137 项自动测试通过，新增触摸相对位移、抬手/断连/休眠、屏幕边界、采集/演示不注入事件、默认映射迁移与文字按键检查。触摸板实机验证单独记录；此前 84 条设备事件仅证明按钮/摇杆输入。

Version 0.5.5: all 137 automated tests passed, including relative touch motion, lift/disconnect/sleep, display bounds, capture/demo suppression, preset migration and text-button mappings. Physical touch verification is recorded separately; the earlier 84 events validate button/stick input only.

0.5.6：会话默认流程调整为长按 × 打开、单击 × 确认、○ 返回；141 项自动测试通过。原生液态玻璃与上下文箭头提示见 [悬浮窗设计和实现](overlay-liquid-glass.md)。

Version 0.5.6: long × opens chats, press × confirms, ○ goes back; all 141 automated tests pass. See the linked overlay record for native Liquid Glass and context-dependent callouts.

## 0.10.2：肩键成为按键，布局重排 / Shoulders become buttons; the layout rearranged

起因是两条使用反馈：R1 只有“按一下”，没有长按和双击；默认布局混乱。原因和改动如下。

- **R1 / R2 以前被当成旋钮的左右两格接入。**原生后端把右肩键和右扳机映射成 `left` / `right`，只在按下时发一次脉冲，没有松开事件，所以手势引擎无从识别长按、双击和按住。现在它们是独立的 `r1` / `r2`，有按下和松开，和其他键一样有全部触发方式。蓝牙麦克风路径的报告解码同样改了。
- **新增一种触发方式：按下即触发，按住连发。**按键按下时立刻执行一次，按住 0.35 秒后每 0.09 秒一次，松开即停；晚到的时钟只补一步，松开时不补。节奏与摇杆相同，由手势引擎产生，所以任何有按下 / 松开的输入都能用。方向键默认用它。
- **方向默认值统一。**摇杆和方向键上 / 下滚屏（上推向上），左 / 右在有草稿时移动光标、没有草稿时不执行，列表和应用切换里是上一个 / 下一个。0.5.5 到 0.10.1 之间摇杆上推是向下滚，这一条反了回来；旋钮和遥控器的左右没有动。
- **默认布局：一个键一件事。**R1 按住命令（以前在 L2），R2 按住听写，L1 单击会话、长按模型，L2 按住切应用，○ 确认，× 返回，□ 删除，△ 按住听写，☰ 按键一览。会话列表里不再是 × 确认、○ 返回。默认布局没有双击，× 和 ○ 不再等双击窗口。说话放在右肩，是照作者自己改过的布局定的：他把命令键从 L2 挪到了 R1，而那时 R1 只能“按一下开始、再按一下结束”。
- **按键一览。**见[默认操作](core-experience.md#按键一览)。
- **已保存布局的迁移**见[设备模板](device-templates.md#手势与配置)。作者本机保存的手柄布局（R1 命令、R2 确认、L2 关掉、方向键上 / 下是会话和切应用）在一个隔离的偏好域里跑过一遍迁移并读回了结果：R1 变成按住说命令，R2 仍是单击确认，L2 仍然关着，方向键上 / 下不变，L1 多了会话和模型，其余的键换成新默认。之后开发版在他的 Mac 上启动，从真实偏好里读回的手柄布局与这次预演一致。

- **退回旧版。**0.10.1 及更早读不了这一版保存的布局，会把所有设备的布局重置为默认。发布前这在作者的 Mac 上真的发生了一次：开发版迁移完布局以后，另一个会话换上了 0.10.1 的包，四个设备的布局和选中的设备全部回到默认；试用前留有一份备份。这一版起，读到更新的版本写下的布局时只丢掉不认识的那一条。

验证：运行 351 项 Swift 测试，315 项通过，36 项需显式启用的实机与渲染用例在普通测试中跳过，新增的覆盖肩键的按下 / 松开、按下即触发的连发与取消、方向默认值、旧布局迁移、L1 打开会话并逐项前进、L2 按住切应用（演示模式，不发按键）、R1 / R2 按住说话，以及按键一览打开时按键不外发、翻页和关闭。按键一览和缩小版悬浮窗看过中英文离屏渲染图；按键一览的窗口在不显示的情况下构建过一次，确认它用的是系统玻璃、不抢焦点、能接收点击。

**没有验证的：**这一版没有用实体手柄按过任何一个键，也没有在连着手柄的运行中应用里看过按键一览；L2 / R2 扳机作为“按住”键的误触程度、按住 L2 时系统 ⌘Tab 在各应用前台的表现、R1 按住说命令从按下到松开的整个过程，都没有实测。终端实机测试（`TerminalLiveTests`）里手柄的步骤已按新布局改写，但没有重新运行。

Two reports started this: R1 had a press and nothing else, and the default layout was confusing.

- **R1 / R2 used to arrive as the two detents of a dial.** The native backend mapped the right shoulder and trigger to `left` / `right` and sent one pulse on the way down with no release, so the gesture engine could not tell a long press, a double press or a hold. They are now `r1` / `r2` with a press and a release, and take every gesture the other buttons take. The Bluetooth-microphone path decodes them the same way.
- **A new gesture: press at once, repeat while held.** It acts as the button goes down, again every 0.09 s after 0.35 s held, and stops on release; a late clock adds one step and a release adds none. The pace is a stick's, and the gesture engine produces it, so any input with a press and a release can use it. The D-pad uses it by default.
- **One set of direction defaults.** Sticks and the D-pad scroll up and down (up is up), move the caret sideways when there is a draft and do nothing when there is none, and are previous / next in a list and in the app switcher. From 0.5.5 to 0.10.1 a stick pushed up scrolled down; that is undone. The dial and the remote are unchanged.
- **The default layout: one job a button.** R1 held speaks a command (it was on L2), R2 held dictates, L1 opens chats and on a long press models, L2 held switches apps, ○ confirms, × goes back, □ deletes, △ held dictates, ☰ shows the controls card. The chat list no longer has × confirm and ○ go back. Nothing in the default layout is a double press, so × and ○ no longer wait out its window. Talking sits on the right shoulder because of the owner's own remapping: he had moved the command key from L2 to R1, where at the time it could only start on one press and end on the next.
- **The controls card:** see [Default controls](core-experience.en.md#the-controls-card).
- **Migration of saved layouts:** see [Device templates](device-templates.en.md#gestures-and-persistence). The controller layout saved on the owner's Mac (R1 a command, R2 confirm, L2 off, D-pad up / down for chats and app switching) was run through the migration in a preferences domain of its own and read back: R1 is held to speak a command, R2 still confirms on a press, L2 is still off, D-pad up / down are unchanged, L1 gained chats and models, and the other buttons took the new defaults. The development build was then started on his Mac, and the controller layout read back from his real preferences was the same as in this rehearsal.

- **Going back.** 0.10.1 and earlier cannot read the layouts this version saves and reset every device's layout to its default. This happened once on the owner's Mac before the release: after the development build had moved his layout, another session put the 0.10.1 package in its place, and the layouts of all four devices and the selected device went back to their defaults; a copy from before the trial had been kept. From this version on, layouts written by a later version lose only the binding that cannot be read.

Verification: 351 Swift tests ran and 315 passed; 36 opt-in live and review tests are skipped in the normal suite. New coverage: press and release of the shoulders, the repeat and cancellation of press-at-once, the direction defaults, migration of an old layout, L1 opening chats and stepping through them, L2 held to switch apps (demo mode, no keys sent), R1 / R2 held to speak, and the controls card keeping presses to itself, turning its pages and closing. The card and the compact overlay were looked at as off-screen renderings in both languages, and the card's panel was built once without being shown, to see that it sits on the system's glass, takes no focus and accepts a click.

**Not verified:** no button was pressed on a physical controller for this version, and the card was not seen in the running app with a controller connected. How easily the L2 / R2 triggers are touched by accident as hold keys, how the system's ⌘Tab behaves under a held L2 in front of each app, and a command spoken on a held R1 from press to release were not tried. The controller steps of the terminal live test (`TerminalLiveTests`) were rewritten for the new layout and not run again.
