# Device templates

[Getting started](getting-started.en.md) · [Default controls](core-experience.en.md) · [Documentation](README.md)

[中文](device-templates.md) · [Core experience](core-experience.en.md) · [HID integration](hid-profiles.md)

VibeWand includes three switchable logical layouts: **VibeKey, Controller, and Remote**. Select a control in the diagram to edit its click, double-click, long-press, hold, or navigation action. Each template retains its own timing and context overrides.

## Implementation status

| Template | Input path | Current boundary |
| --- | --- | --- |
| VibeKey | Built-in AU05 receiver protocol | Existing device backend; live connection status is reported separately |
| Controller | macOS GameController automatically discovers USB / paired Bluetooth controllers | Supported devices need no HID profile; live connection and available buttons are reported separately |
| Remote | Import an HID profile captured from the intended device | Layout, defaults, switching, and persistence implemented; pairing, buttons, and release reports need verification |

Switching layouts stops the old input source and updates the floating panel's device photo and input indicators. Controller starts automatic discovery after USB connection or macOS Bluetooth pairing. Its connection panel shows live status and offers Bluetooth settings and a retry action; automatic detection describes the input method, not a claimed connection. Remote still requires a measured HID profile. Advanced compatibility can override Controller with an explicit HID profile; removing it restores automatic detection. No speculative device IDs or button usages are shipped.

## Shared interaction

Previous / next means scrolling while reading, moving the caret while editing, selecting a candidate in a picker, and moving between applications in the app switcher. Confirm and back follow the same context. Application identity, focus, and input-method composition checks still apply.

Every layout covers dictation, navigation, sessions, model / reasoning selection, app switching, confirm / Enter, delete / back, and native Escape. Device mapping and application shortcuts remain separate layers.

| Action | VibeKey default | Controller default: right hand only | Remote default |
| --- | --- | --- | --- |
| Previous / next | Turn dial left / right | R1 / R2 | Left / right direction |
| Sessions / switch | Dial click | Long press × | Menu click; or hold center |
| Confirm / Enter | OK | ○ | Center click |
| Model / reasoning | Hold dial | Long press ○ | Hold Menu |
| Switch applications | Double-click dial | Double-click × | Double-click center |
| Delete / back | ESC | □ Backspace; × Back | Back |
| Native Escape | Hold ESC | Press × | Hold Back |
| Dictation | Hold microphone key | Hold △ | Hold voice key |
| Confirm app switch | Dial or OK | ○ | Center or Menu |

All core controller actions are reachable through the right shoulder, right trigger, and four right-side face buttons. The right stick also provides continuous navigation; no left-hand button or left stick is required. While the right thumb holds △ for dictation, the index finger can still navigate with R1 / R2. PS5-style face symbols explain positions, while the product calls the preset “Controller.” All actions are editable, and another controller can use different physical bindings.

The controller exposes 19 physical buttons and up, down, left, and right on each stick, for 27 configurable inputs. The Sticks group includes both direction and press entries, matching the photo hotspots. Extra buttons such as L1 / L2, L3 / R3, D-pad, Options, Create, Home, and Mute start unassigned. Sliding on the touchpad moves the pointer; a short press clicks the left mouse button. Stick directions have these defaults:

| Stick direction | Default behavior |
| --- | --- |
| Up / down | Scroll down / up in ordinary contexts (reversed from the previous default); previous / next candidate in a picker |
| Left / right | Scroll, move the caret, or select candidates according to context |
| Any direction in the app switcher | Up / left selects the previous app; down / right selects the next |

The two sticks provide optional symmetric navigation; the right-hand layout still covers every core action independently. Crossing the dead zone acts immediately, holding a direction repeats, and returning to center stops it. Each direction has one editable movement / sustained-navigation binding, rather than tap or long-press gestures. Supported controllers deliver button and stick input through the native backend. Measured HID bindings are needed only when using an advanced override. Extra buttons depend on the controls macOS exposes. The native touchpad supports relative single-finger pointer movement and a short press to click. Lifting or replacing the finger re-anchors without jumping. Two-finger scrolling, taps and dragging are not implemented.

The remote layout takes its direction ring, center, voice, menu, and back arrangement from the Xiaomi Bluetooth Remote 2 Pro, but the product calls the preset “Remote.” Center confirms. Menu switches sessions / browser tabs on click and opens model selection on hold; both confirm inside a picker. Up / Down, Power, Home, and Volume buttons can also be configured and are unassigned by default. Their names do not automatically invoke the device's native functions. NFC is outside the current integration scope.

Version 0.5.5 reverses default reading navigation: dial left, R1, stick up/left scroll down; dial right, R2, stick down/right scroll up. Caret movement and previous/next selection keep their directions. Explicit Scroll up/down actions retain their named meaning.

Face buttons follow the user-requested convention: ○ confirms, □ deletes and × goes back. This differs from [Sony’s current PS5 system-menu defaults](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/), where × selects and ○ cancels. In pickers, ○ confirms immediately, × cancels and □ does nothing. Existing baseline bindings migrate once while differing custom mappings and timings remain intact.

## Gestures and persistence

- VibeKey uses a 0.28-second double-click window and a 0.55-second long press. Controller and Remote use 0.32 and 0.65 seconds.
- A click waits when a double-click action exists. Double-clicking does not also execute a single click. App-switch confirmation is immediate.
- Hold-to-dictate requires both press and release reports. A pulse-only binding cannot represent a reliable hold.
- Reset affects only the active template. Restoring a single binding copies that template's baseline, rather than merely erasing an override.
- Local `UserDefaults` storage uses `vibeWand.deviceTemplates.v1`. The first migration retains older gesture mappings and an explicitly imported HID interface in the VibeKey configuration; they do not spill into other layouts.
- Switching layouts, changing mappings, disconnecting, or quitting releases held Fn and app-switch modifiers and cancels pending clicks.

## Hardware integration and acceptance

1. Connect a controller over USB or pair it in macOS Bluetooth settings, then choose Controller for automatic detection. Check its live connection status and device name.
2. For Remote or a controller unsupported by macOS, inspect the real interfaces and input elements using the [HID integration guide](hid-profiles.md), then import a profile matching only that dedicated interface. Controller HID overrides live under Advanced compatibility and can be removed to restore automatic detection.
3. Enable physical-events-only capture in the Developer settings. Verify each press, release, direction, and reconnect before testing application actions.
4. With a generic HID override, verify the R2 trigger's resting value, pressed value, and return to zero. The current `pulse` binding requires zero at rest and nonzero while pressed; other ranges need normalization. Use `axis` for a centered stick, not an ordinary `absolute` encoder: returning to center would otherwise emit reverse movement. Trigger thresholds still require separate verification.
5. With a generic HID override, if a direction ring produces one enumerated hat-switch value instead of separate button usages, a decoder is needed to split directions. Private reports and vendor handshakes also need a dedicated `HIDEventSource`.

The generic backend supports explicitly selected interfaces with buttons, edge pulses, relative / position-difference encoder axes, and centered-stick axes. Sticks use the device descriptor’s actual logical range; the default activation dead zone is 22% of half-range and release zone is 16%. Threshold crossing acts immediately; repetition starts after 350 ms and continues every 90 ms until neutral release. Magnitude-based acceleration, hat-switch enumeration, multi-finger touchpad gestures, and haptics are not implemented. A generic HID override does not supply native touchpad coordinates. A template is an editable interaction configuration, not a universal plug-and-play driver.

## Microphones and audio

VibeWand currently sends a held Fn dictation trigger. It does not capture audio, select a recording device, or provide speech recognition. macOS or the user's dictation application selects the microphone.

For the DualSense reference controller, distinguish transports. [JoyHarness's firsthand investigation](https://github.com/nixihz/JoyHarness/blob/main/docs/research/dualsense-wireless-microphone.md) reports a USB audio input on macOS 26.5.2, while finding no directly usable Bluetooth microphone path on Mac. Check the actual system input list when connected over USB; use a Mac or external microphone for Bluetooth control. This project has not repeated that audio test on the current hardware.

[Sony's compatibility page](https://www.playstation.com/en-us/support/hardware/pair-dualsense-controller-bluetooth/) supports USB / Bluetooth controller connections to Mac but does not promise built-in microphone compatibility. Keep official guarantees distinct from observed USB compatibility. A microphone-mute HID event is not an audio stream.

[Xiaomi's official page](https://www.mi.com/xiaomi-bluetooth-remote-2-pro) and [store catalog](https://m.mi.com/commodity/list/2028) describe the reference remote's smart voice, NFC casting, and USB-C charging. These TV features do not establish macOS audio-input support. Verify the voice-button reports and the microphone audio path separately.

## Extension boundary

Templates describe physical controls and gestures; application adapters execute actions. A new device should first supply a verified event source and then reuse the logical controls. New application or agent actions belong in the action and application layers. Templates do not store scripts, access tokens, or arbitrary commands.

## Validation scope and vendor independence

The README groups supported input types and shows typical device models; model-specific capabilities depend on the actual input path and profile. AU05 input and a local Bluetooth controller have been observed on hardware. Controller button coverage depends on what macOS exposes; USB and touchpad behavior need validation on the intended model. The Remote preset requires a measured HID profile and does not establish universal plug-and-play compatibility. For historical checks, see [AU05 records](direct-device-plan.md) and [controller records](controller-input.md).

VibeWand is independent of Ulanzi, Sony, Xiaomi, and other device manufacturers. There is no affiliation, partnership, sponsorship, or endorsement. Names, trademarks, and model examples identify device layouts and compatibility targets; they do not imply a vendor relationship.
