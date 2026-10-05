# VibeWand

A small macOS tool for driving Codex, Claude, DeepSeek Harness and WorkBuddy with a dial, a game controller or a remote.

[简体中文](README.zh-CN.md) · [Get started](docs/getting-started.en.md) · [Documentation](docs/README.md) · [Project site](https://vibewand.xuhao1.me)

![Read with a dial, edit and dictate with a controller, confirm with a remote](docs/images/workflow-hero-v2.png)

Most of vibe coding is not typing. You read a reply, flip between chats, change the model, say a sentence, and wait. One hand is enough for all of that. VibeWand puts it on a dial or a controller so you can lean back while you work.

## What it does

- **Read.** Turn the dial or push a stick to scroll the conversation. Once the draft has text in it, the same motion moves the cursor instead.
- **Speak.** Hold the microphone button and talk. When you let go, the text is in the composer, and nothing is sent for you. Use the built-in recognition (macOS dictation or your own speech API), which records from the microphone of the device you are holding and takes your own vocabulary, or keep using an input method such as Typeless.
- **Switch.** Press once for the chat list, turn to choose, press to confirm. Long-press for reasoning effort and models. Double-press to switch macOS apps.
- **Remap.** Every button's press, double press and long press can be reassigned in Settings, and each device keeps its own layout.

<p align="center"><img src="docs/images/overlay-v081-screenshot-en.jpg" width="500" alt="Actual VibeWand 0.8.1 overlay and speech bar in Demo mode"></p>

*Actual VibeWand 0.8.1 window, captured in Demo mode.*

A floating overlay shows what each button will do right now. It collapses into a thin bar when you want it out of the way, and the button that expands and collapses it never moves.

## Devices

| Type | Connection | Tested with |
| --- | --- | --- |
| **VibeKey**<br><img src="assets/device/controller.png" height="110" alt="VibeKey dial controller"> | USB receiver, built-in protocol | Ulanzi VibeKey (AU05) |
| **Controller**<br><img src="assets/device/gamepad.png" height="90" alt="Game controller"> | USB or Bluetooth, detected by macOS | Sony DualSense (PS5) |
| **Remote**<br><img src="assets/device/remote.png" height="110" alt="Remote control"> | Needs an imported HID profile | Xiaomi Bluetooth Remote 2 Pro |

Several devices can stay connected at once. Press a button on one and the overlay and button layout follow it; there is nothing to switch in Settings. A Bluetooth controller powers itself off after about ten idle minutes, so Settings has a "Keep the controller awake" switch.

Per-model details are in the [hardware guide](docs/device-templates.en.md).

**VibeWand is an independent project. It is not affiliated with, sponsored by or endorsed by Ulanzi, Sony, Xiaomi or any other device maker. Product names and trademarks belong to their owners.**

## Apps

| App | Chats | Model / effort | Dictation |
| --- | --- | --- | --- |
| Codex | ⌘K palette | Effort slider; press again for the model list | ✓ |
| Claude | ⌘K palette | Model menu, then the effort slider | ✓ |
| DeepSeek Harness | Sidebar chat list | Model menu and its submenu | ✓ |
| WorkBuddy | Sidebar task search; ⌘K fallback | Model menu | Paste on release |
| Claude Code, Codex and OpenCode in iTerm2 | Types `/resume` | Types `/model` | Pasted on release |
| Browsers | Next tab | Address bar | ✓ |
| WeChat, Feishu | Search / switch chats | — | ✓ |

All five AI rows were exercised on a real machine. The terminal row was accepted in iTerm2 3.7.3 against Codex CLI 0.160.0, Claude Code 2.1.289 and OpenCode 1.18.34 with the screen read back after every step: with a draft at the prompt turning moves the cursor and ESC deletes, a command is typed only at an empty prompt, and buttons keep answering while the agent works; see the [acceptance record](docs/terminal-acceptance.md). WorkBuddy 5.6.2 passed native UI readback checks for task search and opening, model switching, draft editing and dictation delivery with transcript replay. Dictation is not tied to an app: native fields fill in as you speak, and everything else gets a single paste when you release, after which your clipboard is put back. You can add a shortcut rule for other apps in Settings; see [Applications](docs/applications.en.md).

## Install

**[Download VibeWand 0.8.4 (Apple Silicon)](https://github.com/xuhao1/VibeWand/releases/download/v0.8.4/VibeWand-0.8.4-macOS-arm64.zip)** · [Release notes](https://github.com/xuhao1/VibeWand/releases/latest)

Requires macOS 13 or later on an M-series Mac. Unzip, drag **VibeWand.app** into Applications, open it, then:

1. Allow VibeWand under System Settings → Privacy & Security → Accessibility. Without it, the app can neither see the composer nor send keys.
2. Connect your device. For the VibeKey, quit Ulanzi Studio first; the two cannot share the receiver.
3. No device yet? Try Settings → Developer → Demo mode.

This build is ad-hoc signed and not notarized by Apple, so the first launch takes one extra step. See [Get started](docs/getting-started.en.md).

### Build from source

You need Xcode 26 or later and Opus from Homebrew:

```sh
brew install opus
bash scripts/build-app.sh
```

The result is `dist/VibeWand.app`. More in the [development guide](docs/development.md).

## Documentation

[Default controls](docs/core-experience.en.md) · [Settings and remapping](docs/settings.en.md) · [Voice input](docs/voice-input.md) · [Applications](docs/applications.en.md) · [Troubleshooting](docs/troubleshooting.en.md) · [Development](docs/development.md)

## Privacy

Device input and configuration stay on your Mac. VibeWand has no server and needs no account. With an external input method it only holds Fn for you. With built-in recognition, audio stays in memory; macOS dictation runs on device when it can, and API mode sends audio to the endpoint you entered. Keys live in the macOS Keychain and are never part of an exported configuration. Dictated text goes into the field and no further; sending it is up to you. A terminal has no composer control, so VibeWand reads the few rows next to the cursor to find the prompt; they are reduced to a state in memory and dropped, never stored or sent anywhere.

## License

The source is under [PolyForm Noncommercial 1.0.0](LICENSE). Personal, noncommercial use, modification and distribution are allowed. **Commercial use requires a separate license from [the author, Hao Xu](https://github.com/xuhao1)**; open a [commercial licensing inquiry](https://github.com/xuhao1/VibeWand/issues/new?title=Commercial%20licensing%20inquiry) to ask. Because commercial use is restricted, this is source-available rather than open source as the OSI defines it. Third-party components keep their own licenses; see [acknowledgements](third-party/README.md).

By **Dr. Xu** · [Homepage](http://xuhao1.me) · [GitHub](https://github.com/xuhao1)
