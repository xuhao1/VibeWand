# Contributing / 参与贡献

[Project home](README.md) · [中文首页](README.zh-CN.md) · [Development / 开发指南](docs/development.md)

Useful contributions include reproducible app compatibility reports, verified HID profiles, physical-device testing, accessibility improvements, and focused fixes. Please read the [license](LICENSE) and the [terms for contributions](#license-of-contributions--贡献的授权) below before contributing.

欢迎提交应用适配报告、实测 HID 配置、设备验证、辅助功能改进与功能修复。贡献前请阅读[许可证](LICENSE)和下面的[贡献授权条款](#license-of-contributions--贡献的授权)。

## Report an issue / 报告问题

Include macOS and VibeWand versions, target app version, device model and connection method, selected template, steps to reproduce, and expected versus observed behavior. For input problems, say whether physical capture detects paired press/release events. Remove private conversations, audio, credentials, and personal paths from attachments.

请附上系统与应用版本、设备和连接方式、所选模板、复现步骤及预期 / 实际结果。输入问题请说明物理采集是否收到成对按下与松开事件；附件去除私人内容和凭证。

## Submit a change / 提交修改

Keep device decoding, gesture mapping, and app operations separate. Follow the [development guide](docs/development.md) to build and run tests appropriate to behavior changes. Hardware and UI compatibility claims also need real-device or real-app verification; sending a shortcut alone does not prove that a picker opened.

保持设备解码、手势映射和应用操作分层。行为变更运行相关测试；硬件与界面兼容性还需实机或真实应用验证。文档改动应同步中英文，检查本地链接，并注明示意图与真实截图的区别。

For documentation, update both languages, verify local links, and distinguish illustrations from implemented UI captures. Put design history in engineering records rather than the user guides.

## License of contributions / 贡献的授权

VibeWand is published under the GNU General Public License, version 3 (`GPL-3.0-only`), and its author also licenses it commercially to those the GPL does not fit. Both depend on the author being able to license every part of the code, so a contribution is accepted on these terms. By submitting one (a pull request, a patch or any other material) you agree that:

1. it is your own work, or you have the right to submit it, and you license it to everyone under `GPL-3.0-only`;
2. you grant Hao Xu a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to use, reproduce, modify and distribute it as part of VibeWand, and to license it to others under other terms, commercial licenses included, together with a license to any patent claims of yours that it would otherwise infringe;
3. you keep the copyright in what you wrote.

Say in the pull request that you agree to these terms. If part of a change comes from somewhere else, name the source and its license; code that cannot be given on these terms cannot be merged.

VibeWand 按 GNU 通用公共许可证第 3 版（`GPL-3.0-only`）发布，作者同时向 GPL 不适合的使用者提供商业授权。两者都要求作者能对代码的每一部分授权，所以贡献按下面的条款接受。提交贡献（拉取请求、补丁或其他材料）即表示你同意：

1. 它是你自己的作品，或者你有权提交它，并且你按 `GPL-3.0-only` 把它授权给所有人；
2. 你授予徐浩一项永久、全球、非独占、免费、不可撤销的许可：可以把它作为 VibeWand 的一部分使用、复制、修改和分发，也可以按其他条款（包括商业授权）再授权给他人；你拥有的专利中会被这份贡献侵犯的权利要求，一并许可；
3. 你写的部分，版权仍然归你。

请在拉取请求里写明你同意这些条款。改动里有来自别处的内容时，请写明出处和它的许可；不能按这些条款提供的代码无法合并。
