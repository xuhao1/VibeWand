# Documentation / 文档

[Project home](../README.md) · [中文首页](../README.zh-CN.md)

Start with setup, then learn the default workflow or customize it. User guides describe current behavior; engineering records preserve dated observations.

先完成安装与连接，再了解默认操作或按自己的习惯配置。使用指南描述当前行为；工程记录保留特定版本的实测和设计历史。

## Use VibeWand / 使用指南

| Guide | 中文 | What you will find / 内容 |
| --- | --- | --- |
| [Getting started](getting-started.en.md) | [快速开始](getting-started.md) | Download, permission, connection, dictation, first interaction / 下载、授权、连接、听写与第一次操作 |
| [Default controls](core-experience.en.md) | [默认操作](core-experience.md) | VibeKey, Controller, Remote defaults and context behavior / 三种模板默认操作与场景行为 |
| [Settings and remapping](settings.en.md) | [设置与改键](settings.md) | Button editor, action library, timing, import/export, overlay / 按键编辑、动作库、时间、导入导出与悬浮反馈 |
| [Applications](applications.en.md) | [应用适配](applications.md) | Built-in adapters, custom shortcuts, known limits / 内置适配、自定义快捷键与已知边界 |
| [Troubleshooting](troubleshooting.en.md) | [问题排查](troubleshooting.md) | Input capture, diagnostics, permission and connection problems / 采集、诊断、权限与连接问题 |

## Hardware and advanced configuration / 硬件与进阶配置

| Reference / 参考 | Contents / 内容 |
| --- | --- |
| [Device templates](device-templates.en.md) / [设备模板](device-templates.md) | Complete controls, integration status, microphone boundaries / 完整控件、接入状态与音频边界 |
| [Gesture details / 手势细节](gesture-configuration.md) | Inheritance, hold priority, timing and cancellation / 继承、按住优先级、时序与取消 |
| [HID integration / HID 接入](hid-profiles.md) | Inspect interfaces and build measured profiles / 接口检查与实测配置 |

## Contribute / 参与开发

[Development / 开发指南](development.md) covers build/test tools, source layout and signing. Read [Contributing / 贡献说明](../CONTRIBUTING.md) before reporting an issue or submitting a change.

开发指南包含构建测试、源码布局与签名；问题报告和修改流程见贡献说明。

## Engineering and design records / 工程与设计记录

These records support implementation and provenance. They are not first-use instructions or a promise of current hardware compatibility.

以下内容供实现与来源追溯参考，不作为首次使用步骤，也不代表当前硬件兼容性承诺。

- [Native controller and Bluetooth verification / 原生手柄与蓝牙实测](controller-input.md)
- [AU05 protocol and historical checks / AU05 协议与历史检查](direct-device-plan.md)
- [Settings design / 设置设计](settings-design.md)
- [Appearance audit / 外观审查](ui-appearance-audit.md) and [screenshot gallery / 截图图集](ui-appearance-gallery.html)
- [Device images and hotspots / 设备图像与热点](design-device-assets.md)
- [Documentation image provenance / 文档图像来源](images/README.md)

## License and attribution / 许可与署名

[PolyForm Noncommercial license / 非商用许可证](../LICENSE) · [Third-party notices / 第三方记录](../third-party/README.md) · [Device artwork / 设备插画](../assets/device/README.md)

Personal noncommercial use is permitted under the license. Commercial use requires contacting [Hao Xu](https://github.com/xuhao1) and obtaining a separate license. 允许按条款个人非商用使用；商用必须联系徐浩并取得单独授权。
