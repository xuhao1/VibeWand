# VibeWand

**License: personal noncommercial use is permitted. Commercial use requires contacting [Hao Xu](https://github.com/xuhao1) and obtaining a separate license.**

**A physical control surface for your macOS AI workflow.**

Turn a dial to read or edit, press to switch context, and hold a button to dictate. VibeWand connects a controller to the apps you already use, with a native floating display and a single place to configure every gesture.

[简体中文](README.zh-CN.md) · [Core experience](docs/core-experience.en.md) · [Documentation](docs/README.md) · [Noncommercial license](LICENSE)

VibeWand is the new name of **VibeKey Bridge**. Version **0.5.5** is an actively developed macOS prototype built with Swift, AppKit, Accessibility, GameController, and IOKit. VibeKey uses its AU05 backend; supported controllers connect automatically through macOS. Remote devices and optional HID overrides require measured device profiles.

## What it does

- **Context-aware controls.** Read a conversation with the dial, move the caret in a nonempty draft, navigate a picker, or switch applications with the same controls.
- **Hold-to-dictate.** A microphone button holds and releases Fn for your configured input method. Audio stays with macOS and the input method.
- **App-aware behavior.** Codex and DeepSeek Harness share the AI workflow; browser tabs and WeChat / Feishu use dedicated keyboard mappings. Add your own app using a Chat, Browser, or Custom preset and edit its shortcuts.
- **Photo-based button mapping.** Select a physical control on a recognizable device photograph, or from its input list, then edit its gestures in the inspector. A searchable action library groups System, Application, and VibeWand actions. Changes are saved locally as you edit.
- **Three controller templates.** VibeKey, Controller, and Remote keep separate gesture configurations. The Controller preset puts every default action within reach of the right hand; the other buttons remain available for your own mappings.
- **Controller touchpad pointer.** Slide one finger to move the Mac pointer; press the touchpad to click. Default face buttons use ○ to confirm, □ to backspace and × to go back. Reading scroll direction follows the updated preset.
- **Chinese and English UI.** Switch languages in General without restarting. Settings, menus, actions, and floating feedback update together.
- **A quiet native overlay.** See physical press, release, and rotation feedback without taking focus from your editor. Adjust size, opacity, and button descriptions; open settings from the small gear button, or hide the panel with × and restore it from the menu bar. An open settings window also appears in the Dock.
- **Local device tools.** Use the AU05 backend, automatic macOS controller detection, or an explicit standard HID profile. A separate capture utility helps inspect and validate input.

The application runs without Ulanzi Studio, Electron, a cloud service, or an API key. It does not bundle an AI model or replace the target app or your speech input method.

## Get started

You need macOS 13 or later and a Swift 5.9+ toolchain. Xcode is recommended for running the test suite.

```sh
bash scripts/build-app.sh
bash scripts/run.sh
```

The build creates `dist/VibeWand.app`. The script uses `/Applications/Xcode-beta.app` when present, otherwise the selected developer toolchain.

1. Quit Ulanzi Studio before connecting an AU05. VibeWand yields the device if Studio is running.
2. Allow **VibeWand** in **System Settings → Privacy & Security → Accessibility**.
3. Open **Settings…** from the menu bar. Select your template in **Devices & inputs**. Connect a supported controller over USB or pair it in macOS Bluetooth settings; detection is automatic. **Connect device…** shows live status, pairing access, and advanced HID options. **General** shows device and permission status.
4. Bring a supported app to the foreground and use the controller. Without Accessibility permission, the app starts in demo mode.

To explore without a device:

```sh
bash scripts/run.sh --demo --settings
```

Launch arguments apply to a newly started app; quit an existing instance first.

## Default VibeKey controls

| Gesture | Default behavior |
| --- | --- |
| Turn left / right while reading or in an empty draft | Scroll down / up |
| Turn left / right in a nonempty draft | Move the caret left / right |
| Turn left / right in a picker | Select previous / next item |
| Press the dial | Open conversations; confirm in a picker; next tab in a browser |
| Double-press the dial | Open macOS application switching; turn to choose, press to confirm |
| Hold the dial | Open the AI app's model controls where supported |
| Hold the microphone button | Hold Fn for dictation; release to finish |
| Press OK | Confirm a choice or send Return |
| Press ESC | Delete before the caret in an editable draft; otherwise cancel |
| Hold ESC | Send native Escape |

Browser rotation scrolls the page, including when a page input has focus. WeChat and Feishu reuse reading, editing, search, confirm, and cancel actions through keyboard mappings. Return follows the target app's own send/newline preference. See the [complete behavior and support boundaries](docs/core-experience.en.md).

The default double-press window is 0.28 seconds and long press is 0.55 seconds. You can change both and override actions by context. An assigned hold action takes priority over single, double, and long presses for that press, so releasing dictation does not also confirm or send. Hold-and-turn gestures belong to the VibeKey dial; Controller and Remote buttons do not create hidden combinations.

## One settings window

A native macOS sidebar organizes six pages. Click anywhere within a navigation row to switch pages. General is the single home for the language preference. Version 0.5.3 adds translucent native materials and follows macOS light or dark appearance across General, Devices, Applications, Overlay, Developer and About, plus the four configuration sheets. Compact headings, consistent spacing and aligned controls keep settings readable; sliders show their current values.

The layout editor follows the Steam Input pattern: a device photo and input list on the left, a selected-input inspector on the right, and a focused action picker when assigning a gesture. The Controller uses a bounded landscape image above its input list, including all eight stick directions. VibeKey and Remote use a tall portrait alongside their list, making better use of the window. Opening settings adds VibeWand to the Dock; minimizing keeps it there, and clicking the Dock icon restores the window. Closing settings returns to menu-bar operation while device input continues.

| Page | Contents |
| --- | --- |
| General | Interface language, device and foreground-app status, Accessibility permission, and dictation information |
| Devices & inputs | Template selection, clickable device photo, input groups, context-specific gestures, action library, timing, and layout import / export |
| Applications | Built-in adapters, per-app enable switches, and custom Chat / Browser / Custom rules with editable shortcuts |
| Overlay | Visibility, descriptions, size, opacity, image export, and position |
| Developer | Demo, physical input capture, compatibility, diagnostics, and reconnect |
| About | Version, license, author, and personal / project website links |

![VibeWand native settings and controller layout](docs/images/settings-native.png)

*Rendered from the implemented native settings view. Browse the [full-page appearance gallery](docs/ui-appearance-gallery.html), [appearance audit](docs/ui-appearance-audit.md), [design rationale](docs/settings-design.md), and [device photography notes](docs/design-device-assets.md).*

Choose a template, click a button, choose its context, and open a gesture to assign an action. The action library distinguishes the current assignment from the template default and includes a clear empty state for searches. **Use default action** restores inheritance; **Unassigned** explicitly disables the gesture. The visible **Import**, **Export**, and **Reset** buttons manage the current template's gesture configuration; device profiles are managed separately under **Connect device…**.

## Devices and support status

| Device / template | Current status |
| --- | --- |
| VibeKey | Direct AU05 vendor HID backend; receiver handshake and all six input types have been observed on hardware |
| Controller | Automatic discovery through macOS GameController after USB connection or Bluetooth pairing; no HID profile required for supported devices |
| Remote | Editable control template; requires verification of macOS pairing, button events, and audio availability |
| Other standard HID controllers | Explicit VID / PID / interface profiles; button, pulse, encoder, and centered-stick axis decoding |

Controller and Remote are generic layouts. The Controller exposes 19 physical buttons plus eight directions across its two sticks, for 27 configurable inputs. Each stick direction can be assigned independently; the HID axis path handles center dead zones, hysteresis, repeated movement, and neutral release. The Remote exposes 12 buttons. Extra buttons start unassigned. Each template has its own gestures and device profile. Selecting Controller starts automatic discovery and updates the floating panel to the controller layout. The connection panel distinguishes automatic detection from an actual connection. Remote still requires a measured HID profile. Optional imported profiles override the built-in connection for that template; remove the Controller override to restore automatic detection. Selecting a template does not pair Bluetooth hardware or create a macOS audio input. The AU05 backend leaves USB audio and firmware management to the system. Full button coverage depends on the controls macOS exposes for the connected model; end-to-end input and dictation should be validated on the intended hardware. Consult [HID setup](docs/hid-profiles.md) before importing a profile.

## Development

```sh
swift build
swift test
swift run AU05Capture --list
swift run AU05Capture --duration 30
swift run AU05Capture --profile /absolute/path/controller.json --duration 30
```

`AU05Capture` emits normalized input as NDJSON and writes connection status to stderr. The CLI and GUI cannot own the AU05 simultaneously. Normal exit, SIGINT, and SIGTERM release the interface and temporary hooks.

| Location | Responsibility |
| --- | --- |
| `Sources/AU05Device` | Protocol, device discovery, direct HID lifecycle, generic HID profiles |
| `Sources/VibeKeyBridge` | App UI, gestures, application adapters, overlay, dictation, application switching |
| `Sources/AU05Capture` | Command-line input capture |
| `Tests` | Protocol, lifecycle, gesture, adapter, and interaction tests |
| `profiles` | Gesture and generic HID examples |
| `docs` | Experience guide, design decisions, device setup, and engineering history |

The internal `VibeKeyBridge` target and bundle identifier `org.vibekey.bridge` remain stable to preserve module references and existing preferences. The app and executable are named VibeWand.

For repeatable signing, set `VIBEWAND_SIGNING_IDENTITY` (the legacy `VIBEKEY_SIGNING_IDENTITY` is also accepted). The script otherwise selects the sole Apple Development identity or uses ad-hoc signing. Ad-hoc updates can require Accessibility permission to be registered again. A successful build replaces the app and preserves the previous bundle under `dist/.previous-build.*`.

## Privacy and diagnostics

VibeWand uses Accessibility to inspect the foreground app's controls and sends local keyboard / pointer events. It does not record audio or upload conversations. Draft inspection reduces text to whether the field is empty; diagnostics do not include draft text, audio, or credentials.

Physical input capture and demo mode are available under **Settings → Developer**. To write a local diagnostic snapshot:

```sh
bash scripts/run.sh --capture-only --diagnostics-path /absolute/path/status.json
```

Capture mode temporarily owns the selected device and displays physical events without sending app or dictation actions. Demo mode operates on simulated drafts and conversations. See [the experience guide](docs/core-experience.en.md) for lifecycle and cancellation behavior.

## Contributing

Useful contributions include reproducible app compatibility reports, verified HID profiles, physical-device testing, accessibility improvements, and focused tests. Include macOS/app versions, the device/interface or template used, expected versus observed behavior, and whether the issue reproduces in physical input capture. Remove private conversation content from reports.

Keep protocol decoding, gestures, and app-specific operations separate. Run `swift test` for behavioral changes; hardware and UI claims also need real-device or real-app verification. Do not treat a sent shortcut as proof that a picker opened.

## Author

Created by **Dr. Hao Xu**, **Tenure-track Associate Professor at Nanjing University**.

[Personal website](http://xuhao1.me) · [Project website](https://vibewand.xuhao1.me)

These links also appear in the app's **About** page.

## License and acknowledgments

VibeWand is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). Personal noncommercial use, modification, and redistribution are permitted under its terms. **Commercial use requires contacting Hao Xu and obtaining a separate commercial license before use.** Contact: [Hao Xu (@xuhao1)](https://github.com/xuhao1), or open a [commercial licensing inquiry](https://github.com/xuhao1/VibeWand/issues/new?title=Commercial%20licensing%20inquiry). A request alone does not grant commercial permission. Because it restricts commercial use, this is not an OSI-approved open-source license. Third-party components retain their original licenses.

AU05 protocol work incorporates the MIT-licensed [AU05 Keys](https://github.com/elliclee/ulanzi-au05-keys) project; see [third-party notices](third-party/README.md) for the pinned revision and complete license. No vendor firmware or proprietary library is distributed. Device images are documented in [asset provenance](assets/device/README.md) and [photo / hotspot design notes](docs/design-device-assets.md).

[Native controller implementation and Bluetooth validation](docs/controller-input.md)
