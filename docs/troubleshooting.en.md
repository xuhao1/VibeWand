# Troubleshooting

[简体中文](troubleshooting.md) · [Getting started](getting-started.en.md) · [Documentation](README.md)

## Input or app actions do not work

| Symptom | Check |
| --- | --- |
| App starts in demo | Check Accessibility in Settings → General. Quit and reopen the app after authorization. |
| AU05 unavailable | Quit Ulanzi Studio and the AU05Capture utility. Only one owner can use its vendor interface at a time; reconnect the receiver if needed. |
| Controller not found | Check USB or macOS Bluetooth pairing, select Controller, and inspect live connection status. Remove an imported HID override to restore native detection. |
| Remote has no events | The preset alone cannot connect it. Import a profile captured from the intended device; verify press and release reports. |
| Events show, actions do not | Check live mode, foreground app identity, adapter enablement, Accessibility, and actual app shortcuts. |
| Buttons do nothing in a terminal, or ESC does not delete | 0.8.3 and earlier dropped button presses while Codex or Claude Code was working; update to 0.8.4. Then check that iTerm2 is in front and the cursor is at the tool's own prompt. When the status reads "no agent prompt seen", only scrolling, Escape and Return are available; see [Applications](applications.en.md). |
| Wrong action after an update | Inspect the current template and context overrides. Export your layout before using Reset. |
| Fn produces no dictation | Focus an editable field and test the same held Fn trigger with your keyboard. Check your speech service and microphone independently. |
| Settings/overlay disappeared | Reopen settings or show the overlay from the menu bar. Closing settings does not stop device input. |

The following concern what 0.10.0 and 0.10.1 added:

| Symptom | Check |
| --- | --- |
| The keyboard layout's combinations do nothing | Check that Keyboard is the layout selected under Devices & inputs and that Accessibility is allowed. A key that text is typed or edited with needs one of ⌃, ⌥ and ⌘ beside it; function keys, the number pad and extra keys may stand alone. When two controls share a combination only the earlier fires. A press on another device switches the layout away; select Keyboard again. |
| Nothing happens when a combination is being recorded | The Record button is greyed out: the keyboard layout is not listening yet, so allow Accessibility first. A key was pressed and not recorded: it does not send an ordinary key press (media keys such as volume, playback and brightness, or a function the keyboard's firmware handles itself); set it to F13 to F20 in the keyboard's configuration tool and record that. |
| Another program takes a combination first | Window managers, input methods and the like may use the same combination. Pick another under Devices & inputs. |
| VibeWand's conversations do not show in DeepSeek Harness | They are listed under Ungrouped with titles that start “VibeWand ·”. A harness that is already open does not notice new ones: quit and reopen the desktop app, reload the web app, or use “View conversations in the browser” on the Command mode page. |
| “Let the model see the window and click in it” is on and the model says it cannot see | Allow VibeWand under System Settings → Privacy & Security → Screen Recording, then quit and reopen it. Recognising icons and layout takes a model that takes pictures. |
| The model says it cannot read an app's controls (NetEase Cloud Music, for one) | Such an app gives accessibility no controls and can only be operated from its picture: turn on “Let the model see the window and click in it” under Settings → Command mode (since 0.10.1). |
| With seeing turned on, the first command that looks at a window takes long | After an install or an update the system takes about half a minute to get ready the first time text is read, and not again after that. |
| An earlier conversation is not carried on | A conversation you opened in the harness is taken over by it, and VibeWand starts a new one. So does changing any command-mode setting, and a context four fifths full. |
| Command mode opened a menu and then said it could not read what was in it | That is 0.9.0. Since 0.10.0 a snapshot leads with what has just appeared. If it still happens, open that command under Command mode → Records and send us the list it read. |
| Codex's effort, set by a spoken command, stopped at another level than the one you named | Codex does not call its levels low, medium and high. Say “the lowest” or “one step down”, or the name on the button: Light, Standard, Extended, Extra High. |
| SenseVoice is chosen and dictation says the models are not downloaded | Click Download and prepare under Voice input, about 241 MB. After a break, clicking again resumes where it stopped. The mirror `hf-mirror.com` is used when `huggingface.co` cannot be reached; with neither reachable nothing can be fetched. |
| The first sentence through SenseVoice is slow | The recogniser starts when the dictation button goes down and takes about two seconds to load its models; after five idle minutes it exits, and the next start takes those two seconds again. A sentence longer than that hides it. |

Ad-hoc signed updates can require Accessibility permission to be registered again. The UI and keyboard shortcuts of target apps may change with app versions.

## Separate hardware input from application behavior

In **Settings → Developer**, choose physical input capture. It temporarily owns the selected device and shows physical events while sending no app shortcuts, Fn, or pointer output. Confirm press/release pairs, stick return to center, and reconnect behavior. Restore live mode before trying app actions.

Use **Settings → Developer → Export diagnostics…** to save a local diagnostic file.

Diagnostics contain mode, connection/authorization status, counters, held controls, and action status; they do not contain conversation text, audio, or credentials. Inspect attachments before sharing. [Report an issue](../CONTRIBUTING.md).

## Know the support boundary

Remote pairing/button/audio paths require validation. Controller buttons depend on macOS capabilities; controller recognition does not establish microphone availability. Touchpad support covers relative single-finger movement and short-press click. Reconnect after forced termination if a device remains unavailable; firmware recovery after a crash has not been established.

See [Application support](applications.en.md), [Hardware](device-templates.en.md), and [HID integration](hid-profiles.md) for detailed boundaries. For build failures, use [Development](development.md).
