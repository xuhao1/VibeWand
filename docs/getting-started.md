# 快速开始

[English](getting-started.en.md) · [文档目录](README.md)

## 1. 构建并启动

要求 macOS 13+、Swift 5.9+，建议使用完整 Xcode。在终端运行：

```sh
git clone https://github.com/xuhao1/VibeWand.git
cd VibeWand
bash scripts/build-app.sh
bash scripts/run.sh
```

生成 `dist/VibeWand.app`，也可在 Finder 中打开。构建脚本优先使用 `/Applications/Xcode-beta.app`，否则使用当前选定的工具链。签名和工具链详情见[开发指南](development.md)。

没有设备时，先退出已有实例，再启动演示：

```sh
bash scripts/run.sh --demo --settings
```

演示只操作模拟内容。启动参数仅对新进程生效。

## 2. 授予辅助功能权限

在「系统设置 → 隐私与安全性 → 辅助功能」允许 **VibeWand**，并在「设置 → 通用」检查状态。未授权时程序以演示模式启动。临时签名更新后可能需要重新登记权限。

## 3. 连接硬件

从菜单栏打开「设置…」，进入「设备与按键」。

| 硬件 | 操作 |
| --- | --- |
| VibeKey / AU05 | 退出 Ulanzi Studio，连接接收器，选择 VibeKey。Studio 运行时 VibeWand 会让出设备。 |
| 系统支持的手柄 | USB 连接或先在 macOS 蓝牙设置中配对，再选择手柄；自动识别无需导入 HID 配置。 |
| 遥控器 / 其他 HID 设备 | 先实测并准备匹配真实接口的配置，参阅[硬件说明](device-templates.md)与[HID 接入](hid-profiles.md)。 |

在「连接设备…」检查实时设备名称和连接状态。选择模板不会完成配对；配置已保存也不代表设备已连接。

## 4. 配置听写

在 macOS 或输入法中选择麦克风，让听写服务接受「按住 Fn」触发。先聚焦可编辑输入框，用键盘确认这个触发方式能够工作，再用 VibeWand。

按住 VibeKey 麦克风键或手柄 △，说完松开。VibeWand 只发送 Fn 按下 / 松开，不录音、不转写。蓝牙手柄使用 Mac 或外接麦克风；USB 手柄音频需单独检查系统输入设备列表。

## 5. 试一次默认流程

1. 切到支持的应用，阅读回复。转动旋钮或使用 R1 / R2 滚屏。
2. 聚焦草稿，按住听写键说话，再松开。有字且被识别的草稿中，导航移动光标。
3. 准备好再确认：VibeKey 使用 OK，手柄使用 ○；Return 的发送 / 换行行为由目标应用决定。
4. 双击旋钮或手柄 × 打开应用切换，导航后确认，返回键取消。

悬浮面板显示输入和场景，不抢键盘焦点。齿轮打开设置，× 隐藏面板，菜单栏可重新显示。

接着阅读[默认操作](core-experience.md)、[设置与改键](settings.md)或[问题排查](troubleshooting.md)。
