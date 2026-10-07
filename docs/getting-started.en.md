# Getting started

[简体中文](getting-started.md) · [Documentation](README.md)

## 1. Download and open

Download **[VibeWand-0.11.3-macOS-arm64.zip](https://github.com/xuhao1/VibeWand/releases/download/v0.11.3/VibeWand-0.11.3-macOS-arm64.zip)** from [GitHub Releases](https://github.com/xuhao1/VibeWand/releases/latest). This package requires **macOS 26+** and an **Apple Silicon Mac**; it does not include an Intel binary. The download is about 103 MB, as it carries the kernel for command mode and the SenseVoice recogniser. On macOS 13 to 15, use [0.8.4](https://github.com/xuhao1/VibeWand/releases/tag/v0.8.4).

1. Double-click the ZIP in Finder to extract **VibeWand.app**.
2. Drag it into **Applications**.
3. Double-click **VibeWand**. Its menu-bar icon provides **Settings…** and the floating panel controls.

This package is ad-hoc signed and has not been notarized by Apple. If macOS blocks the first open, follow [Apple's first-open guidance](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac) in **System Settings → Privacy & Security**.

To try it without hardware, choose **Settings → Developer → Demo**. Return to **Live control** to use your device. If you prefer to compile it, follow [Build from source](development.md#build-from-source--从源码编译), then open the resulting app in Finder.

### The first-run guide

Since 0.10.0, the first time VibeWand opens it shows a guide that walks you through steps 2 to 5 below and command mode. Every step can be skipped:

| Step | What it does |
| --- | --- |
| Permissions | Whether Accessibility and the microphone are allowed, each with a button straight to System Settings |
| Your device | Pick the device in your hand, press a few buttons and turn it: what lights up has been received. Nothing you press in this step reaches an app. With no device, pick Keyboard |
| Voice | One of four: keep your own voice input method, macOS dictation, SenseVoice on this Mac (the first use downloads about 240 MB of models), or a speech API (address, model and key), with a place to try a sentence |
| Buttons | What each button of the current layout does, and where dictation and the command are bound |
| Command mode | On or off; if on, the kernel VibeWand ships or the DeepSeek Harness you installed, then set up a model and test it |
| All set | Where each of these stands now, with a way back to whatever is not ready |

Someone who already uses VibeWand is not interrupted by it after an update. It can be opened again from **Settings → General → Setup guide**, and **Settings → Developer** can make it appear at the next launch the way it does the first time. 0.9.0 has no guide; follow the steps below.

## 2. Allow Accessibility

Allow **VibeWand** in **System Settings → Privacy & Security → Accessibility**. Check the permission state in **Settings → General**. Without this permission, VibeWand starts in demo mode. Ad-hoc signed updates may need permission registered again.

## 3. Connect your hardware

Open **Settings…** from the menu bar, then **Devices & inputs**.

| Hardware | Steps |
| --- | --- |
| VibeKey / AU05 | Quit Ulanzi Studio, connect the receiver, and select VibeKey. VibeWand yields the device while Studio is running. |
| Supported gamepad | Connect with USB or pair in macOS Bluetooth settings, then select Controller. Automatic discovery needs no HID import. |
| Remote / unsupported HID device | Use a measured profile matching its actual interface. Follow [Hardware](device-templates.en.md) and [HID integration](hid-profiles.md) first. |
| No device | Select Keyboard: six key combinations stand in for the buttons, by default ⌃⌥⌘ with Space, the arrows, Return and Backspace, and each can be recorded as another key by pressing it. See [the keyboard layout](device-templates.en.md#keyboard). |

Open **Connect device…** and check the live device name and connection status. Selecting a picture or template does not pair hardware. A saved profile is not evidence of a live connection.

## 4. Set up dictation

Open Settings → Voice input. External mode uses your input method configured for held Fn. Built-in mode offers macOS dictation, Alibaba Qwen Realtime and compatible transcription APIs. Keys stay in Keychain and are excluded from exports. Use Start test to check recognition and permissions.

Focus an editable field, hold the VibeKey microphone key or Controller △ (since 0.10.2, R2 as well), and release to finish. Review text before sending. Built-in mode records from the microphone of the device whose key you hold (the VibeKey, for example) and falls back to the macOS default input; Voice input settings can pin the system sound input and hold your own vocabulary and subject hint. An optional DualSense Bluetooth microphone path is available in Devices & inputs; see [requirements and setup](dualsense-microphone-integration.md). For USB controller audio, check the actual macOS input-device list separately. See [Voice input](voice-input.md).

## 5. Try the default workflow

1. Bring a [supported app](applications.en.md#supported-programs-at-a-glance) such as Codex or Claude to the foreground and read a reply. Turn the dial, or scroll with a controller's D-pad or sticks.
2. Focus a draft, hold the dictation button, speak, then release. With an observed nonempty draft, navigation moves the caret.
3. Confirm only when ready: OK on VibeKey or ○ on Controller. Return follows the target app's send/newline preference.
4. Double-press the dial to open app switching, navigate and confirm; back cancels. On a controller hold L2, choose with left / right, and release to switch.

The controller steps above are the 0.10.2 layout; press ☰ on the controller for the whole [controls card](core-experience.en.md#the-controls-card). Up to 0.10.1 scrolling was on R1 / R2 and app switching was a double press of ×.

The floating panel shows input and context without taking keyboard focus. Its gear opens settings; × hides it. Restore it from the menu bar.

Continue with [Default controls](core-experience.en.md), [Settings and remapping](settings.en.md), or [Troubleshooting](troubleshooting.en.md). For what VibeWand reads and does inside each app, see [Computer use](computer-use.en.md).
