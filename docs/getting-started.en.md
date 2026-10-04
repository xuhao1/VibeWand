# Getting started

[简体中文](getting-started.md) · [Documentation](README.md)

## 1. Build and launch

Use macOS 13 or later with Swift 5.9+; a full Xcode installation is recommended. In Terminal:

```sh
git clone https://github.com/xuhao1/VibeWand.git
cd VibeWand
bash scripts/build-app.sh
bash scripts/run.sh
```

The build creates `dist/VibeWand.app`. It uses Xcode beta when installed at `/Applications/Xcode-beta.app`, otherwise the selected toolchain. You can also open the built app in Finder. Signing and toolchain details are in [Development](development.md).

To explore without hardware, quit an existing instance first, then run:

```sh
bash scripts/run.sh --demo --settings
```

Demo actions operate on simulated content. Launch arguments apply only to a newly started instance.

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
