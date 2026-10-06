# Default controls and everyday workflows

[简体中文](core-experience.md) · [Getting started](getting-started.en.md) · [Documentation](README.md)

These are the 0.10.1 template defaults. Saved custom mappings take precedence; reset the active template if you want its defaults. Complete controls and hardware boundaries are in [Device templates](device-templates.en.md).

## Navigation follows context

| Foreground context | Default navigation |
| --- | --- |
| Reading or an empty draft | Scroll the conversation. Dial left / R1 scroll down; dial right / R2 scroll up. |
| Observed nonempty draft | Move the caret left / right. |
| Recognized conversation, model, or effort picker | Select the previous / next candidate. |
| macOS app switcher | Select the previous / next application. |
| Browser | Scroll the page, including when a page input has focus. |
| Terminal (iTerm2) | Scroll at an empty prompt; move the caret left / right when the prompt holds a draft; previous / next inside a `/resume` or `/model` list that VibeWand opened. |

A shortcut alone does not establish that a picker opened. Supported adapters inspect available controls before applying picker behavior. Input-method candidates and unknown dialogs take priority and keep native confirmation/cancellation. A terminal has no controls to inspect, so the adapter reads the few rows of text next to the cursor to tell the prompt, a draft and a list apart; see [Applications](applications.en.md#claude-code-codex-and-opencode-in-a-terminal). Which apps have these contexts is in [Supported programs at a glance](applications.en.md#supported-programs-at-a-glance).

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
| ESC long press | Keeps deleting while a draft is being edited, until released; elsewhere the same as a press |

In the app switcher, turn to choose, press the dial or OK to confirm, and use ESC to cancel. Switching cancels after 15 seconds of device inactivity.

## Controller: core actions within the right hand

| Control | Default action |
| --- | --- |
| R1 / R2 | Previous / next navigation by context |
| ○ | Confirm / Return; long press opens model controls |
| □ | Backspace in an editable draft, hold to keep deleting; no action in pickers |
| × | Back; double-press switches apps; long press opens conversations / next browser tab |
| △ hold / release | Start / finish dictation |
| Touchpad | Single-finger movement controls the pointer; short press left-clicks, when exposed by macOS |

In the chat picker, × confirms and ○ goes back. Model/effort pickers and app switching keep ○ confirmation / × cancellation. Editing retains ○ confirmation / □ deletion. Both sticks offer independently editable directions; tilting repeats navigation until centered. Up / left scroll down, down / right scroll up while reading. Extra buttons start unassigned. Touchpad taps, two-finger scrolling, and dragging are not implemented.

## Remote: configurable preset

Left / right navigate, center confirms, double-center switches apps, and long-center opens conversations. Menu opens conversations / the next browser tab, long-Menu opens models, voice holds dictation, and back cancels or deletes by context. The preset requires a verified device profile; it is not ready-to-use hardware support.

## Keyboard: with no device

With the Keyboard layout selected, six key combinations stand in for the buttons, with VibeKey's default actions: ⌃⌥⌘ Space held dictates, ⌃⌥⌘ ↑ is the main button (press for chats, double press to switch apps, long press for models), ⌃⌥⌘ ← / → navigate, ⌃⌥⌘ Return confirms, and ⌃⌥⌘ Backspace deletes or goes back. Each one can be recorded as another key by pressing it, a custom keyboard's extra keys included; see [Device templates](device-templates.en.md#keyboard).

## Dictate, edit, then confirm

Focus a draft → hold the microphone key or △ → speak → release → move the caret or delete → confirm when ready. Your selected external input method, system SDK or speech API handles recognition. Releasing a dictation hold does not also click, confirm, or send.

Return can send or insert a newline depending on the target app. Check its preference before using confirmation on a real conversation. Application-specific shortcuts and support limits are in [Applications](applications.en.md).

## The command key

Command mode is on by default and takes effect once a model is set up; until then the keys below do not exist. After that there is a hold-to-speak command key: a long press of the VibeKey dial that you keep holding (the model entry moves to a long press of OK), L2 on a controller, and right ⌘ held on its own on the keyboard. On release the sentence goes to command mode and is not typed into any field. When it needs a choice or a confirmation from you it asks on the overlay: turning chooses, the confirm button confirms and the back button stops, and none of these reach the app in front at that time. By default only actions such as deleting and sending need confirming. See [Command mode](command-mode.en.md).

## Timing and customization

VibeKey uses a 0.28-second double-press window and 0.55-second long press; Controller and Remote use 0.32 and 0.65 seconds. A single press waits when a double-press action exists. Hold actions take priority over click gestures. Hold-and-turn is specific to the VibeKey dial.

Disconnecting, sleeping, changing templates/configuration/modes, or quitting cancels pending actions and releases held Fn and app-switch modifiers. To remap a control or adjust timing, see [Settings](settings.en.md). For verification history, see [native controller records](controller-input.md) and [AU05 records](direct-device-plan.md).

## Several devices at once

From 0.7.0, a connected VibeKey and controller both listen. Press any button on the other device and it becomes current: the overlay shows its artwork, buttons follow its own layout, and the press that caused the switch still acts. If the current device disconnects for a few seconds, the one still connected takes over. Editing a layout under Settings → Devices is not interrupted by other devices, and "Follow the device in use" turns the behaviour off entirely.

A Bluetooth controller powers itself off after roughly ten idle minutes. With Settings → General → Keep the controller awake, VibeWand rewrites the light bar every 40 seconds (no visible change), at the cost of a little controller battery.
