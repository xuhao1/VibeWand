# Development / 开发指南

[Documentation / 文档目录](README.md) · [Contributing / 贡献说明](../CONTRIBUTING.md)

Use an Apple Silicon Mac with full Xcode 26 or later (macOS 26+ SDK) and Homebrew Opus for the bundled application. The current source targets macOS 26; the published 0.8.4 package still runs on macOS 13+. See [Getting started](getting-started.en.md) / [快速开始](getting-started.md) to build the application bundle.

打包环境需要 Apple Silicon Mac、完整 Xcode 26+（macOS 26+ SDK）及 Homebrew Opus。当前源码的最低系统为 macOS 26；已发布的 0.8.4 安装包仍可在 macOS 13 以上运行。

## Build from source / 从源码编译

Download the source from [GitHub](https://github.com/xuhao1/VibeWand), or the source archive attached to the desired [release](https://github.com/xuhao1/VibeWand/releases). The helper currently expects Opus under `/opt/homebrew`. Install the build dependency if absent, then compile the graphical application in the project folder:

从 GitHub 或对应 Release 下载源码。蓝牙组件当前使用 `/opt/homebrew` 下的 Opus；若未安装，请先准备此编译依赖，再构建：

```sh
brew install opus
bash scripts/build-app.sh
```

The script compiles a release build, copies the icon, device images and license notices, and signs the bundle. The result is **`dist/VibeWand.app`**. Open it in Finder or copy it to Applications and double-click it. The application runs from the menu bar; settings, demo, physical capture and diagnostics are available in its graphical interface.

脚本完成 Release 编译、素材与许可证打包和签名，生成 **`dist/VibeWand.app`**。在 Finder 中打开，或复制到「应用程序」后双击；设置、演示、采集与诊断均通过图形界面操作。

The default build targets the build Mac's architecture. The published 0.8.4 package is **arm64 / Apple Silicon**, requires macOS 13+, uses ad-hoc signing, and is not Apple-notarized. The bundled microphone-helper build currently targets arm64, so this packaging flow does not support Intel.

默认编译面向构建机器的架构。已发布 0.8.4 为 **arm64 / Apple Silicon**，要求 macOS 13+，临时签名且未公证；当前麦克风组件固定编译为 arm64，此打包流程不支持 Intel。

## Command kernel / 命令内核

`scripts/build-app.sh` calls `scripts/build-kernel.sh`, which assembles `output/kernel` and copies it into the app as `Contents/Resources/kernel`. It downloads the official Node.js 24.21.0 for Apple Silicon and the packages locked in `kernel/package-lock.json`, checks each against a pinned digest, runs no package script, and then starts the result once (`kernel/smoke.mjs`) before publishing it. An unchanged kernel is reused from `output/kernel`. Set `VIBEWAND_SKIP_KERNEL=1` to build without it; command mode then reports that the build has no kernel.

`scripts/build-app.sh` 会调用 `scripts/build-kernel.sh` 组装 `output/kernel`，并复制到应用的 `Contents/Resources/kernel`。它下载官方 Node.js 24.21.0（Apple Silicon）和 `kernel/package-lock.json` 锁定的包，逐一核对固定的摘要，不运行任何包脚本，并在发布前实际启动一次（`kernel/smoke.mjs`）。内容未变时复用 `output/kernel`。`VIBEWAND_SKIP_KERNEL=1` 可以不带内核构建，命令模式会提示此版本没有内核。

The kernel is DeepSeek Harness driven over the Agent Client Protocol. `kernel/profile/cordis.patch.yml` is its complete plugin tree: a model adapter, a session and the protocol bridge, with no tools of its own. The model's whole reach is the catalog in `Sources/WandAgent/Tools.swift`, served to the kernel over a Unix socket that admits only the kernel's own child processes:

内核是经 Agent Client Protocol 驱动的 DeepSeek Harness。`kernel/profile/cordis.patch.yml` 是它完整的插件树：模型适配、会话和协议桥，没有任何自带工具。模型能做的事以 `Sources/WandAgent/Tools.swift` 的工具表为限；这些工具经一个 Unix 套接字提供给内核，只接受内核自己的子进程连接：

| Tools / 工具 | Purpose / 作用 |
| --- | --- |
| `list_targets`, `find_sessions`, `open_session`, `search_in_app`, `activate_app` | Apps and chats / 应用与会话 |
| `choose`, `finish`, `need_user` | Asking the user and ending a task / 询问用户与结束任务 |
| `ui_snapshot`, `ui_press`, `ui_key`, `ui_menu`, `ui_type` | The front window, through its accessibility tree / 经辅助功能控件树操作前台窗口 |

To change the kernel version, edit `kernel/package.json` and the launcher pin in `scripts/build-kernel.sh`, then refresh the lock with `npm install --package-lock-only --ignore-scripts` in `kernel/`. The profile test in `Tests/WandAgentTests` fails if a package is added to the tree without being listed there.

更换内核版本时，修改 `kernel/package.json` 和 `scripts/build-kernel.sh` 里的启动器版本与摘要，再在 `kernel/` 中用 `npm install --package-lock-only --ignore-scripts` 刷新锁文件。`Tests/WandAgentTests` 里的 profile 测试会在插件树多出未登记的包时失败。

## Tests / 测试

For behavior changes, run the test suite with the same Xcode toolchain:

行为变更使用同一 Xcode 工具链运行测试：

```sh
swift test
```

Command mode is tested with a scripted kernel and never touches another app. One opt-in suite drives a real kernel and a real model with a stand-in for the desktop; it needs a key in the environment and an assembled kernel:

命令模式用脚本内核测试，不触碰其他应用。另有一组需要显式启用的测试，用真实内核和真实模型、以假的桌面宿主运行；它需要环境变量里的密钥和已组装的内核：

```sh
bash scripts/build-kernel.sh
DEEPSEEK_VIBEWAND_DEV=… VIBEWAND_KERNEL_RESOURCES="$PWD/output" swift test --filter KernelLiveTests
```

## Source layout / 源码布局

`AU05Capture` emits normalized input as NDJSON and writes connection status to stderr. The CLI and GUI cannot own the AU05 simultaneously. Normal exit, SIGINT, and SIGTERM release the interface and temporary hooks.

| Location | Responsibility |
| --- | --- |
| `Sources/AU05Device` | Protocol, device discovery, direct HID lifecycle, generic HID profiles |
| `Sources/SpeechInput` | UI-independent recording, Speech SDK, network protocols, preferences, Keychain and dictation lifecycle |
| `Sources/WandAgent` | UI-independent command mode: kernel process and protocol, tool catalog and socket, gateway, task records, Codex chat list |
| `kernel` | The kernel's locked package set, its profile and the boot check |
| `Sources/VibeKeyBridge` | App UI, gestures, application adapters, overlay, voice orchestration, text delivery, application switching, and what command mode's tools do on the desktop |
| `Sources/SpeechAPICheck` | Explicit audio-file API checks, reading credentials only from Keychain |
| `Sources/AU05Capture` | Command-line input capture |
| `Tests` | Protocol, lifecycle, gesture, adapter, and interaction tests |
| `profiles` | Gesture and generic HID examples |
| `docs` | Experience guide, design decisions, device setup, and engineering history |

The internal `VibeKeyBridge` target and bundle identifier `org.vibekey.bridge` remain stable to preserve module references and existing preferences. The app and executable are named VibeWand.

For repeatable signing, set `VIBEWAND_SIGNING_IDENTITY` (the legacy `VIBEKEY_SIGNING_IDENTITY` is also accepted). The script otherwise selects the sole Apple Development identity or uses ad-hoc signing. Ad-hoc updates can require Accessibility permission to be registered again. A successful build replaces the app and preserves the previous bundle under `dist/.previous-build.*`.

## Implementation model / 实现分层

```mermaid
flowchart LR
    A[Device input] --> B[Normalized events]
    B --> C[Context-aware gestures]
    C --> D[Foreground app adapter]
    D --> E[Native controls and key events]
    B --> F[Floating feedback]
```

设备负责输入事件，模板负责手势映射，应用适配器负责执行。新增设备先验证事件源；新增应用先定义身份和快捷键。配置不执行脚本、不包含凭证。

Device sources normalize input, templates map gestures, and app adapters perform operations. Verify a new event source before connecting it to app actions. Configuration does not run scripts or contain credentials.

## Xcode toolchain

If Command Line Tools cannot load SwiftUI macros, use the full Xcode developer directory for that command. The build script already chooses `/Applications/Xcode-beta.app` when present. For that installation:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

命令行工具若缺少 SwiftUI 宏插件，请为该次命令指定完整 Xcode 路径；按实际安装位置调整。

## Optional DualSense voice / 可选手柄语音

The main app bundles the HID/Opus audio helper and its library/license. It is disabled by default. The current experimental Bluetooth microphone path requires macOS 26+ and the `gamepolicyctl` tool provided by Xcode or Command Line Tools; the downloaded app's ordinary controller input and other dictation modes do not need these developer tools. See [integration notes](dualsense-microphone-integration.md).

主包已包含音频组件、Opus 库和许可证，蓝牙语音默认关闭。当前实验路径需要 macOS 26+ 及 Xcode / Command Line Tools 提供的游戏模式工具；普通手柄输入和其他听写模式无需这些开发工具。
