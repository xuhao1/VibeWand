# Contributing / 参与贡献

[Project home](README.md) · [中文首页](README.zh-CN.md) · [Development / 开发指南](docs/development.md)

Useful contributions include reproducible app compatibility reports, verified HID profiles, physical-device testing, accessibility improvements, and focused fixes. Please read the [noncommercial license](LICENSE) before contributing.

欢迎提交应用适配报告、实测 HID 配置、设备验证、辅助功能改进与功能修复。贡献前请阅读[非商用许可证](LICENSE)。

## Report an issue / 报告问题

Include macOS and VibeWand versions, target app version, device model and connection method, selected template, steps to reproduce, and expected versus observed behavior. For input problems, say whether physical capture detects paired press/release events. Remove private conversations, audio, credentials, and personal paths from attachments.

请附上系统与应用版本、设备和连接方式、所选模板、复现步骤及预期 / 实际结果。输入问题请说明物理采集是否收到成对按下与松开事件；附件去除私人内容和凭证。

## Submit a change / 提交修改

Keep device decoding, gesture mapping, and app operations separate. Follow the [development guide](docs/development.md) to build and run tests appropriate to behavior changes. Hardware and UI compatibility claims also need real-device or real-app verification; sending a shortcut alone does not prove that a picker opened.

保持设备解码、手势映射和应用操作分层。行为变更运行相关测试；硬件与界面兼容性还需实机或真实应用验证。文档改动应同步中英文，检查本地链接，并注明示意图与真实截图的区别。

For documentation, update both languages, verify local links, and distinguish illustrations from implemented UI captures. Put design history in engineering records rather than the user guides.
