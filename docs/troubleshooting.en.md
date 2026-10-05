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

Ad-hoc signed updates can require Accessibility permission to be registered again. The UI and keyboard shortcuts of target apps may change with app versions.

## Separate hardware input from application behavior

In **Settings → Developer**, choose physical input capture. It temporarily owns the selected device and shows physical events while sending no app shortcuts, Fn, or pointer output. Confirm press/release pairs, stick return to center, and reconnect behavior. Restore live mode before trying app actions.

Use **Settings → Developer → Export diagnostics…** to save a local diagnostic file.

Diagnostics contain mode, connection/authorization status, counters, held controls, and action status; they do not contain conversation text, audio, or credentials. Inspect attachments before sharing. [Report an issue](../CONTRIBUTING.md).

## Know the support boundary

Remote pairing/button/audio paths require validation. Controller buttons depend on macOS capabilities; controller recognition does not establish microphone availability. Touchpad support covers relative single-finger movement and short-press click. Reconnect after forced termination if a device remains unavailable; firmware recovery after a crash has not been established.

See [Application support](applications.en.md), [Hardware](device-templates.en.md), and [HID integration](hid-profiles.md) for detailed boundaries. For build failures, use [Development](development.md).
