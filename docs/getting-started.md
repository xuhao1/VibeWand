# 快速开始

[English](getting-started.en.md) · [文档目录](README.md)

## 1. 下载并打开

从 [GitHub Releases](https://github.com/xuhao1/VibeWand/releases/latest) 下载 **[VibeWand-0.11.2-macOS-arm64.zip](https://github.com/xuhao1/VibeWand/releases/download/v0.11.2/VibeWand-0.11.2-macOS-arm64.zip)**。本包要求 **macOS 26+**、**Apple Silicon Mac**，不含 Intel 可执行文件，下载约 103 MB（内含命令模式的内核和本机 SenseVoice 的识别程序）；macOS 13–15 请使用 [0.8.4](https://github.com/xuhao1/VibeWand/releases/tag/v0.8.4)。

1. 在 Finder 中双击 ZIP，解压得到 **VibeWand.app**。
2. 拖入「应用程序」。
3. 双击 **VibeWand**，通过菜单栏图标打开「设置…」或显示悬浮面板。

本包使用临时签名，尚未通过 Apple 公证。若首次打开被 macOS 阻止，可按 [Apple 的首次打开说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac)在「系统设置 → 隐私与安全性」处理。

没有设备时，在「设置 → 开发者 → 演示模式」体验；使用设备前切回「实时控制」。自行编译见[从源码编译](development.md#build-from-source--从源码编译)，完成后在 Finder 中打开生成的应用。

### 首次引导

0.10.0 起，第一次打开 VibeWand 会出现一个引导窗口，带你把下面第 2 到第 5 步和命令模式走一遍，每一步都可以跳过：

| 步骤 | 做什么 |
| --- | --- |
| 权限 | 辅助功能和麦克风的授权状态，各有一个按钮直达系统设置 |
| 设备 | 选你手上的设备，按几个键、转一转，亮起来就是收到了。这一步里按键不会发给任何应用。没有设备就选“键盘” |
| 语音 | 四选一：继续用自己的语音输入法、macOS 自带听写、本机 SenseVoice（第一次要下载约 240 MB 的模型）、语音服务 API（填地址、模型和密钥），并当场试一句 |
| 按键 | 当前布局上每个键是干什么的，听写和命令各绑在哪 |
| 命令模式 | 开不开；开的话用 VibeWand 自带的内核还是你装好的 DeepSeek Harness，配模型并测试 |
| 完成 | 各项现在的状态，没配好的可以点回去补 |

已经用过 VibeWand 的人升级后不会被它打断。随时可以从「设置 → 通用 → 首次引导」再打开；「设置 → 开发者」里还可以让它在下次启动时像第一次那样自己出现。0.9.0 没有这个引导，请照下面的步骤设置。

## 2. 授予辅助功能权限

在「系统设置 → 隐私与安全性 → 辅助功能」允许 **VibeWand**，并在「设置 → 通用」检查状态。未授权时程序以演示模式启动。临时签名更新后可能需要重新登记权限。

## 3. 连接硬件

从菜单栏打开「设置…」，进入「设备与按键」。

| 硬件 | 操作 |
| --- | --- |
| VibeKey / AU05 | 退出 Ulanzi Studio，连接接收器，选择 VibeKey。Studio 运行时 VibeWand 会让出设备。 |
| 系统支持的手柄 | USB 连接或先在 macOS 蓝牙设置中配对，再选择手柄；自动识别无需导入 HID 配置。 |
| 遥控器 / 其他 HID 设备 | 先实测并准备匹配真实接口的配置，参阅[硬件说明](device-templates.md)与[HID 接入](hid-profiles.md)。 |
| 没有设备 | 选“键盘”：六组组合键当按键用，默认是 ⌃⌥⌘ 加空格、方向键、回车和退格，每个都可以按一下来录制成别的键。见[键盘布局](device-templates.md#键盘)。 |

在「连接设备…」检查实时设备名称和连接状态。选择模板不会完成配对；配置已保存也不代表设备已连接。

## 4. 配置听写

打开「设置 → 语音输入」。外置模式继续使用 Typeless、豆包等，需让输入法接受「按住 Fn」触发。内置模式可选择 macOS 系统听写、阿里 Qwen 实时语音，或兼容语音转文字 API。密钥进入钥匙串，不随配置导出。先用设置页的「开始测试」检查识别与权限。

聚焦可编辑输入框，按住 VibeKey 麦克风键或手柄 △（0.10.2 起 R2 也行），说完松开，检查文字后再发送。内置模式默认用按下听写键的设备自带的麦克风（例如 VibeKey），设备没有麦克风时用 macOS 默认输入；可在「语音输入」改为始终使用系统声音输入，并填写自己的词表和领域提示。「设备与按键」提供可选 DualSense 蓝牙语音，要求与操作见[接入说明](dualsense-microphone-integration.md)；USB 手柄音频需单独检查系统输入设备列表。详见[语音输入](voice-input.md)。

## 5. 试一次默认流程

1. 切到[支持的应用](applications.md#支持的程序一览)，例如 Codex 或 Claude，阅读回复。转动旋钮，或用手柄的方向键、摇杆滚屏。
2. 聚焦草稿，按住听写键说话，再松开。有字且被识别的草稿中，导航移动光标。
3. 准备好再确认：VibeKey 使用 OK，手柄使用 ○；Return 的发送 / 换行行为由目标应用决定。
4. 双击旋钮打开应用切换，导航后确认，返回键取消；手柄是按住 L2，左右选，松开切换。

上面手柄的操作是 0.10.2 的布局，在手柄上按 ☰ 可以看到整张[按键一览](core-experience.md#按键一览)；0.10.1 及以前滚屏用 R1 / R2，切应用是双击 ×。

悬浮面板显示输入和场景，不抢键盘焦点。齿轮打开设置，× 隐藏面板，菜单栏可重新显示。

接着阅读[默认操作](core-experience.md)、[设置与改键](settings.md)或[问题排查](troubleshooting.md)。想知道 VibeWand 在各个应用里具体读什么、做什么，见 [Computer use](computer-use.md)。
