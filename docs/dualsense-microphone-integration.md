# DualSense 蓝牙语音：主应用接入

手柄页面提供“启用手柄蓝牙语音”开关，默认关闭。实验组件仅供 Apple Silicon、macOS 26+ 使用，当前还需要 Xcode / Command Line Tools 提供的 `gamepolicyctl` 游戏模式工具；USB 与其他手柄仍按原来的系统 GameController 路径接入。打开后，VibeWand 的独立音频组件接收 DualSense HID 音频，发布 **VibeWand DualSense Mic** 系统输入；主应用内置听写按设备 UID 选择该输入，不改系统默认麦克风。外置输入法需在其自身设置中选择这一输入。

音频组件独占蓝牙 HID 时，将正常的手柄报告送回主应用，按键、摇杆和三角键按住/松开仍走原有手势引擎。触摸板点击可用；触摸板滑动指针尚未从该报告路径迁移，启用期间暂停。断开后取消按住状态，手柄重新连接时自动重试。打开期间临时启用 Apple 游戏模式，关闭开关或退出主应用后恢复。录音、原始报告和语音识别内容不会写入桥接进程的日志；只传正常手柄报告。

打包脚本编译原有麦克风原型，将音频组件和 libopus 收进 `VibeWand.app`，随主包统一签名；不要求用户单独运行实验版。首次使用可能需要对 VibeWand 的系统音频录制授权。此权限用于读取本组件发布的麦克风，tap 只选择本组件自身的进程。设备序号缺口仍约 4–6%，使用现有 Opus PLC 补偿；实验版功能不等于 Sony 或 macOS 官方支持。

验证：Swift Debug 构建通过，生产应用打包并验证签名，实机手柄页面开/关能切换输入路径、发布/移除系统输入并恢复游戏模式。组件独立运行收到有效正常报告；主应用通过 Core Audio UID 可以选择新设备并读到 48 kHz 双声道格式。完整真人听写质量尚需单独验收。

0.6.0 发布核对中修正了蓝牙语音报告的 R1 / R2 对应关系，与普通 GameController 路径保持一致，并加入报告格式及导航方向回归测试。

Release verification aligned the Bluetooth audio bridge R1/R2 mapping with native GameController input and added malformed-report and navigation regression checks. The feature remains opt-in and requires macOS 26+ plus the game-mode tool from Xcode/Command Line Tools.
