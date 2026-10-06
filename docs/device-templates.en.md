# Device templates

[Getting started](getting-started.en.md) · [Default controls](core-experience.en.md) · [Documentation](README.md)

[中文](device-templates.md) · [Core experience](core-experience.en.md) · [HID integration](hid-profiles.md)

VibeWand includes three switchable logical layouts: **VibeKey, Controller, and Remote**. Since 0.10.0 there is a fourth, **[Keyboard](#keyboard)**, which needs no device. Select a control in the diagram to edit its click, double-click, long-press, hold, or navigation action. Each template retains its own timing and context overrides.

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

| Action | VibeKey default | Controller default (0.10.2) | Remote default |
| --- | --- | --- | --- |
| Previous / next | Turn dial left / right | D-pad or either stick | Left / right direction; Up / Down |
| Sessions / switch | Dial click | Press L1 | Menu click; or hold center |
| Confirm / Enter | OK | ○ | Center click |
| Model / reasoning | Hold dial | Long press L1 | Hold Menu |
| Switch applications | Double-click dial | Hold L2, release to switch | Double-click center |
| Delete / back | ESC | □ Backspace; × Back | Back |
| Keep deleting (while editing) | Hold ESC | Hold □ | Hold Back |
| Native Escape | ESC with an empty draft | Press × | Back with an empty draft |
| Dictation | Hold microphone key | Hold △ or R2 | Hold voice key |
| Command (once a model is set up) | Long press the dial and keep holding | Hold R1 | The keyboard's command key |
| Confirm app switch | Dial or OK | Release L2, or ○ | Center or Menu |
| Controls card | Menu-bar menu | ☰, or the menu-bar menu | Menu-bar menu |

The controller's rule is one job a button: the right shoulder talks (R1 a command, R2 dictation), the left shoulder switches (L1 chats, L2 apps), the face buttons confirm and delete, the sticks and the D-pad move; and a button means the same thing while reading, editing and in a list. One hand on the right side reads, speaks, corrects and sends, with the right stick, R1, R2 and the four face buttons; changing chat, model and app is under the left hand. PS5-style face symbols explain positions, while the product calls the preset “Controller.” All actions are editable, and another controller can use different physical bindings. The default layout and how it differs from 0.10.1 are in [Default controls](core-experience.en.md#controller-one-job-a-button).

The controller exposes 19 physical buttons and up, down, left, and right on each stick, for 27 configurable inputs. The Sticks group includes both direction and press entries, matching the photo hotspots. L3 / R3, Share, Home, and Mute start unassigned. Sliding on the touchpad moves the pointer; a short press clicks the left mouse button. Stick directions and the D-pad share these defaults:

| Direction | Default behavior |
| --- | --- |
| Up / down | Scroll up / down; previous / next item in a list |
| Left / right | Move the caret when there is a draft, nothing when there is none; previous / next item in a list |
| Any direction in the app switcher | Up / left selects the previous app; down / right selects the next |

Crossing a stick's dead zone acts immediately, holding a direction repeats, and returning to center stops it. Each stick direction has one editable movement / sustained-navigation binding, rather than tap or long-press gestures. The D-pad is made of buttons: by default each is “press at once, repeat while held”, at the pace of a stick, and it can be given a press, double press, long press or hold instead. Supported controllers deliver button and stick input through the native backend. Measured HID bindings are needed only when using an advanced override. Extra buttons depend on the controls macOS exposes. The native touchpad supports relative single-finger pointer movement and a short press to click. Lifting or replacing the finger re-anchors without jumping. Two-finger scrolling, taps and dragging are not implemented.

The remote layout takes its direction ring, center, voice, menu, and back arrangement from the Xiaomi Bluetooth Remote 2 Pro, but the product calls the preset “Remote.” Center confirms. Menu switches sessions / browser tabs on click and opens model selection on hold; both confirm inside a picker. Since 0.10.2 Up / Down scroll by default and step through a list; Power, Home, and Volume buttons can also be configured and are unassigned by default. Their names do not automatically invoke the device's native functions. NFC is outside the current integration scope.

The dial and the remote keep the directions set in 0.5.5: dial left / Left scrolls down, dial right / Right scrolls up. The controller's sticks were reversed with them from 0.5.5 to 0.10.1 (up scrolled down); since 0.10.2 the sticks and the D-pad move the way they point: up scrolls up, down scrolls down. Caret movement and previous/next selection have kept their directions throughout. Explicit Scroll up/down actions retain their named meaning.

Face buttons follow the user-requested convention: ○ confirms, □ deletes and × goes back. This differs from [Sony’s current PS5 system-menu defaults](https://www.playstation.com/en-us/support/hardware/ps5-button-functions/), where × selects and ○ cancels. □ does nothing in pickers; in the chat, model and effort pickers and in app switching ○ confirms and × cancels, with no double press to wait for. Up to 0.10.1 the chat picker had × confirm and ○ go back, × doubled as double press for apps and long press for chats, and ○ as long press for models; in 0.10.2 those moved to L1 and L2, and the command key from L2 to R1.

## Keyboard

**Added in 0.10.0.** With no device at hand the keyboard is the device: six key combinations each stand for one button, and gestures, contexts and application support are exactly those of VibeKey.

| Control | Default combination | Default action |
| --- | --- | --- |
| Dictation | ⌃⌥⌘ Space | Hold to speak, release to finish |
| Main | ⌃⌥⌘ ↑ | Press for chats / confirm, double press to switch apps, long press for models |
| Left / Right | ⌃⌥⌘ ← / ⌃⌥⌘ → | Scroll, move the caret or change the candidate, by context; holding the key keeps going |
| Confirm | ⌃⌥⌘ Return | Confirm / Enter |
| Back | ⌃⌥⌘ Backspace | Delete / back; hold to keep deleting while editing |

- **Selecting it.** Choose Keyboard under Settings → Devices & inputs, or at the device step of the first-run guide. Accessibility access is needed.
- **In force only while selected.** With this layout selected VibeWand takes the combinations above and they no longer reach the app in front; every other key is untouched. Select another device layout and the combinations are the apps' again. With “Follow the device in use” on, other devices stand by and take over at a press, and the keyboard does not stand by like that: a press on VibeKey or a controller switches to that device, and going back to the keyboard means selecting it in Settings again.
- **Changing them: record by pressing.** Select a control in the diagram or the list, click Record under Key combination, and press the key you want, with ⌃ ⌥ ⇧ ⌘ held if you like. Any key that sends a key press can be recorded, and you need not know what it is called: the extra keys of a custom keyboard or a macro pad, F13 to F20, the number pad, Home / End / Page Up / Page Down, and keys VibeWand has no name for, which are shown by number, as in “Key 105”. The press that is recorded reaches no app and does not fire the control it stood for until then. A key the system uses itself, such as F14 and F15 for brightness by default, is recorded too, and is VibeWand's while the keyboard layout is selected. Escape alone cancels. Once recorded, the modifiers can still be switched on and off one by one.
- **Which keys may stand alone.** A key that text is typed or edited with needs one of ⌃, ⌥ and ⌘ beside it: letters, digits, punctuation, Space, Return, Tab, Backspace, Delete, Escape and the arrows. With ⇧ alone or with no modifier such a combination does not fire, because that key could then no longer be typed. Any other key may stand alone: F1 to F20, the number pad, the paging keys and extra keys. When two controls share a combination only the earlier one fires. Each control can be put back to its default, or set to None.
- **A key that gets no answer while recording.** It does not send an ordinary key press: media keys such as volume, playback and brightness are of that kind, and so are functions a keyboard's firmware keeps to itself. Set it to F13 to F20 in the keyboard's own configuration tool (VIA, QMK and the like) and it can be recorded. A modifier pressed alone is not a key press either.
- **If three modifiers at once are awkward,** a key-remapping tool can make a spare key press ⌃⌥⌘ together, or pick combinations that suit your hand.
- **When dictation goes through an external input method,** all the dictation combination does is hold Fn for you. Your hand is on the keyboard already, and pressing the input method's own voice key is the surer way: with the combination's modifiers still down, the input method may not take that Fn for its voice key. The dictation combination is mainly for built-in dictation, that is, macOS dictation or a speech API.
- **The command key is not one of the six.** Command mode uses the keyboard's own command key, by default right ⌘ held on its own; see [Command mode](command-mode.en.md#the-command-key). A combination that happens to use right ⌘ is not taken for a command.
- **The overlay** draws key caps for this layout instead of a device photo, with what each key does right now beside its cap.

Verified: in a TextEdit window the test opened for itself, synthetic keys confirmed that a combination was taken and did not reach the document, that holding the dictation combination put the dictated text into the document, and that other keys worked as usual; the number pad's 5 went into the document as usual before it was recorded, and once recorded by pressing it stood for its control and no longer reached the document. No physical keyboard was pressed and no custom keyboard with extra keys was attached; the recorder was looked at only in off-screen renders; and whether the actions VibeWand sends while the modifiers are held are unaffected by them in every app has not been tried app by app.

## Gestures and persistence

- VibeKey uses a 0.28-second double-click window and a 0.55-second long press. Controller and Remote use 0.32 and 0.65 seconds.
- Every controller button (R1, R2, L1, L2, the face buttons, the D-pad, L3 / R3 and the rest) has five gestures: press, double press, long press, hold / release, and “press at once, repeat while held”. The last is an arrow key's behaviour: once as the button goes down, again every 0.09 seconds after 0.35 seconds held, stopping on release with no extra step on the way up. On one button a hold comes first, then press-at-once, then press, double press and long press; a binding that is shadowed is kept but does not fire, and Settings says so.
- **Migration on upgrading to 0.10.2:** in a saved controller layout, a binding equal to the old default takes the new default, and a binding you changed stays. What you had given R1 / R2 (they had a press and nothing else then) moves to the gesture that suits it: a command or dictation becomes hold to speak and release to finish, where it used to start on one press and end on the next; scrolling, the caret and previous / next become press-at-once; anything else becomes a press. Those buttons then take no new defaults. A button that came empty and that you had given an action (an L2 you switched off, say) takes none either, so that a newly added hold cannot shadow your setting. A D-pad direction you had given a press, double press or long press keeps it and does not become scrolling. For the whole new layout, use Reset under Devices & inputs. Saved VibeKey, Remote and Keyboard layouts are untouched.
- **Going back loses layouts.** 0.10.1 and earlier cannot read the layouts 0.10.2 saves (they name an action those versions do not have) and, on launch, reset the layouts of every device and the selected device to their defaults, not the controller's alone. Export each layout under Devices & inputs before going back. From 0.10.2 on the reverse does not happen: reading layouts written by a later version, it leaves out only the binding it cannot read and keeps the rest, and gives up one device's layout only when that layout names a button it does not have.
- A click waits when a double-click action exists. Double-clicking does not also execute a single click. App-switch confirmation is immediate.
- Hold-to-dictate requires both press and release reports. A pulse-only binding cannot represent a reliable hold.
- Reset affects only the active template. Restoring a single binding copies that template's baseline, rather than merely erasing an override.
- Local `UserDefaults` storage uses `vibeWand.deviceTemplates.v1`. The first migration retains older gesture mappings and an explicitly imported HID interface in the VibeKey configuration; they do not spill into other layouts.
- Switching layouts, changing mappings, disconnecting, or quitting releases held Fn and app-switch modifiers and cancels pending clicks.

## Hardware integration and acceptance

1. Connect a controller over USB or pair it in macOS Bluetooth settings, then choose Controller for automatic detection. Check its live connection status and device name.
2. For Remote or a controller unsupported by macOS, inspect the real interfaces and input elements using the [HID integration guide](hid-profiles.md), then import a profile matching only that dedicated interface. Controller HID overrides live under Advanced compatibility and can be removed to restore automatic detection.
3. Enable physical-events-only capture in the Developer settings. Verify each press, release, direction, and reconnect before testing application actions.
4. With a generic HID override, verify the R2 trigger's resting value, pressed value, and return to zero. A `button` or `pulse` binding requires zero at rest and nonzero while pressed; other ranges need normalization. Since 0.10.2 the logical inputs for R1 / R2 are `r1` and `r2`, and they need a `button` binding to take a long press or a hold; an older override bound to `left` / `right` still gives single navigation steps. Use `axis` for a centered stick, not an ordinary `absolute` encoder: returning to center would otherwise emit reverse movement. Trigger thresholds still require separate verification.
5. With a generic HID override, if a direction ring produces one enumerated hat-switch value instead of separate button usages, a decoder is needed to split directions. Private reports and vendor handshakes also need a dedicated `HIDEventSource`.

The generic backend supports explicitly selected interfaces with buttons, edge pulses, relative / position-difference encoder axes, and centered-stick axes. Sticks use the device descriptor’s actual logical range; the default activation dead zone is 22% of half-range and release zone is 16%. Threshold crossing acts immediately; repetition starts after 350 ms and continues every 90 ms until neutral release. Magnitude-based acceleration, hat-switch enumeration, multi-finger touchpad gestures, and haptics are not implemented. A generic HID override does not supply native touchpad coordinates. A template is an editable interaction configuration, not a universal plug-and-play driver.

## Microphones and audio

External dictation sends held Fn and leaves microphone selection to the input method. Built-in dictation records from the microphone of the device whose dictation key is held (the Core Audio input with the same USB vendor/product ID, such as the VibeKey receiver), falls back to the macOS default input when the device has none, and can be pinned to the system sound input under Voice input → Microphone. The device is chosen for that recording only; the macOS default input is left alone. See [Voice input](voice-input.md).

For the DualSense reference controller, distinguish transports. [JoyHarness's firsthand investigation](https://github.com/nixihz/JoyHarness/blob/main/docs/research/dualsense-wireless-microphone.md) reports a USB audio input on macOS 26.5.2. On 2026-10-04 this project received and decoded microphone Opus frames from the current Bluetooth controller on Mac, and a later standalone prototype published a system input and reduced sequence gaps through Game Mode. Residual gaps remain, and controller navigation pauses during capture. See the [Bluetooth microphone investigation](dualsense-microphone.md). The current release still uses a Mac or external microphone for Bluetooth control; missing software support does not establish a hardware limitation.

[Sony's compatibility page](https://www.playstation.com/en-us/support/hardware/pair-dualsense-controller-bluetooth/) supports USB / Bluetooth controller connections to Mac but does not promise built-in microphone compatibility. Keep official guarantees distinct from observed USB compatibility. A microphone-mute HID event is not an audio stream.

[Xiaomi's official page](https://www.mi.com/xiaomi-bluetooth-remote-2-pro) and [store catalog](https://m.mi.com/commodity/list/2028) describe the reference remote's smart voice, NFC casting, and USB-C charging. These TV features do not establish macOS audio-input support. Verify the voice-button reports and the microphone audio path separately.

## Extension boundary

Templates describe physical controls and gestures; application adapters execute actions. A new device should first supply a verified event source and then reuse the logical controls. New application or agent actions belong in the action and application layers. Templates do not store scripts, access tokens, or arbitrary commands.

## Validation scope and vendor independence

The README groups supported input types and shows typical device models; model-specific capabilities depend on the actual input path and profile. AU05 input and a local Bluetooth controller have been observed on hardware. Controller button coverage depends on what macOS exposes; USB and touchpad behavior need validation on the intended model. The Remote preset requires a measured HID profile and does not establish universal plug-and-play compatibility. For historical checks, see [AU05 records](direct-device-plan.md) and [controller records](controller-input.md).

VibeWand is independent of Ulanzi, Sony, Xiaomi, and other device manufacturers. There is no affiliation, partnership, sponsorship, or endorsement. Names, trademarks, and model examples identify device layouts and compatibility targets; they do not imply a vendor relationship.
