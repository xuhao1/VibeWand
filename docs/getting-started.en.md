# Getting started

[简体中文](getting-started.md) · [Documentation](README.md)

## 1. Download and open

Download **[VibeWand-0.5.5-macOS-arm64.zip](https://github.com/xuhao1/VibeWand/releases/download/v0.5.5/VibeWand-0.5.5-macOS-arm64.zip)** from [GitHub Releases](https://github.com/xuhao1/VibeWand/releases/latest). This package requires **macOS 13+** and an **Apple Silicon Mac**; it does not include an Intel binary.

1. Double-click the ZIP in Finder to extract **VibeWand.app**.
2. Drag it into **Applications**.
3. Double-click **VibeWand**. Its menu-bar icon provides **Settings…** and the floating panel controls.

This package is ad-hoc signed and has not been notarized by Apple. If macOS blocks the first open, follow [Apple's first-open guidance](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac) in **System Settings → Privacy & Security**. No command-line launch is required.

To try it without hardware, choose **Settings → Developer → Demo**. Return to **Live control** to use your device. If you prefer to compile it, follow [Build from source](development.md#build-from-source--从源码编译), then open the resulting app in Finder.

## 2. Allow Accessibility

Allow **VibeWand** in **System Settings → Privacy & Security → Accessibility**. Check the permission state in **Settings → General**. Without this permission, VibeWand starts in demo mode. Ad-hoc signed updates may need permission registered again.

## 3. Connect your hardware

Open **Settings…** from the menu bar, then **Devices & inputs**.

| Hardware | Steps |
| --- | --- |
| VibeKey / AU05 | Quit Ulanzi Studio, connect the receiver, and select VibeKey. VibeWand yields the device while Studio is running. |
| Supported gamepad | Connect with USB or pair in macOS Bluetooth settings, then select Controller. Automatic discovery needs no HID import. |
| Remote / unsupported HID device | Use a measured profile matching its actual interface. Follow [Hardware](device-templates.en.md) and [HID integration](hid-profiles.md) first. |

Open **Connect device…** and check the live device name and connection status. Selecting a picture or template does not pair hardware. A saved profile is not evidence of a live connection.

## 4. Set up dictation

Choose your microphone in macOS or your input method. Configure the speech service to accept a held Fn trigger, then focus an editable field and test the trigger with the keyboard before trying VibeWand.

Hold the VibeKey microphone key or Controller △; release to finish. VibeWand sends Fn press/release and does not record or transcribe audio itself. On Bluetooth, use your Mac or an external microphone. For USB controller audio, check the actual macOS input-device list separately.

## 5. Try the default workflow

1. Bring a supported app to the foreground and read a reply. Turn the dial or use R1 / R2 to scroll.
2. Focus a draft, hold the dictation button, speak, then release. With an observed nonempty draft, navigation moves the caret.
3. Confirm only when ready: OK on VibeKey or ○ on Controller. Return follows the target app's send/newline preference.
4. Double-press the dial or Controller × to open app switching. Navigate and confirm; back cancels.

The floating panel shows input and context without taking keyboard focus. Its gear opens settings; × hides it. Restore it from the menu bar.

Continue with [Default controls](core-experience.en.md), [Settings and remapping](settings.en.md), or [Troubleshooting](troubleshooting.en.md).
