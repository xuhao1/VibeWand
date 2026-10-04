# Default controls and everyday workflows

[简体中文](core-experience.md) · [Getting started](getting-started.en.md) · [Documentation](README.md)

These are the 0.6.0 template defaults. Saved custom mappings take precedence; reset the active template if you want its defaults. Complete controls and hardware boundaries are in [Device templates](device-templates.en.md).

## Navigation follows context

| Foreground context | Default navigation |
| --- | --- |
| Reading or an empty draft | Scroll the conversation. Dial left / R1 scroll down; dial right / R2 scroll up. |
| Observed nonempty draft | Move the caret left / right. |
| Recognized conversation, model, or effort picker | Select the previous / next candidate. |
| macOS app switcher | Select the previous / next application. |
| Browser | Scroll the page, including when a page input has focus. |

A shortcut alone does not establish that a picker opened. Supported adapters inspect available controls before applying picker behavior. Input-method candidates and unknown dialogs take priority and keep native confirmation/cancellation.

## VibeKey / AU05

| Control | Default action |
| --- | --- |
| Dial turn | Navigate according to context above |
| Dial press | Open conversations; next browser tab; confirm in a picker |
| Dial double-press | Open macOS app switching |
| Dial long press | Open models / reasoning controls where supported |
| Microphone hold / release | Start / finish dictation |
| OK press | Confirm / Return |
| ESC press | Delete before the caret or a selection in an observed editable draft; otherwise cancel |
| ESC long press | Native Escape |

In the app switcher, turn to choose, press the dial or OK to confirm, and use ESC to cancel. Switching cancels after 15 seconds of device inactivity.

## Controller: core actions within the right hand

| Control | Default action |
| --- | --- |
| R1 / R2 | Previous / next navigation by context |
| ○ | Confirm / Return; long press opens model controls |
| □ | Backspace in an editable draft; no action in pickers |
| × | Back; double-press switches apps; long press opens conversations / next browser tab |
| △ hold / release | Start / finish dictation |
| Touchpad | Single-finger movement controls the pointer; short press left-clicks, when exposed by macOS |

In the chat picker, × confirms and ○ goes back. Model/effort pickers and app switching keep ○ confirmation / × cancellation. Editing retains ○ confirmation / □ deletion. Both sticks offer independently editable directions; tilting repeats navigation until centered. Up / left scroll down, down / right scroll up while reading. Extra buttons start unassigned. Touchpad taps, two-finger scrolling, and dragging are not implemented.

## Remote: configurable preset

Left / right navigate, center confirms, double-center switches apps, and long-center opens conversations. Menu opens conversations / the next browser tab, long-Menu opens models, voice holds dictation, and back cancels or deletes by context. The preset requires a verified device profile; it is not ready-to-use hardware support.

## Dictate, edit, then confirm

Focus a draft → hold the microphone key or △ → speak → release → move the caret or delete → confirm when ready. Your selected external input method, system SDK or speech API handles recognition. Releasing a dictation hold does not also click, confirm, or send.

Return can send or insert a newline depending on the target app. Check its preference before using confirmation on a real conversation. Application-specific shortcuts and support limits are in [Applications](applications.en.md).

## Timing and customization

VibeKey uses a 0.28-second double-press window and 0.55-second long press; Controller and Remote use 0.32 and 0.65 seconds. A single press waits when a double-press action exists. Hold actions take priority over click gestures. Hold-and-turn is specific to the VibeKey dial.

Disconnecting, sleeping, changing templates/configuration/modes, or quitting cancels pending actions and releases held Fn and app-switch modifiers. To remap a control or adjust timing, see [Settings](settings.en.md). For verification history, see [native controller records](controller-input.md) and [AU05 records](direct-device-plan.md).
