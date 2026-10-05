# Command mode

[中文](command-mode.md) · [Computer use](computer-use.en.md) · [Documentation](README.md)

Hold the command key and say what you want. When you release it, VibeWand finds the app, chat or control for you. It finds, opens, presses and puts text in place; the work itself is still done by the software you chose.

**This page describes the current source. It has not shipped in the 0.8.4 download, and it needs macOS 26.**

## Turn it on

Settings → Command mode:

1. Turn the switch on. Before it turns on, it lists what will be sent to the model service; see [What is sent](#what-is-sent).
2. Save a DeepSeek API key. It is kept in this Mac's Keychain and handed to the command kernel only when the kernel starts. Usage is billed to your DeepSeek account.
3. Leave the model name empty for the default (`deepseek-v4-flash`).

A command is recognised by the built-in recogniser: macOS dictation, or the speech API configured under Voice input. Whether you dictate through an external input method makes no difference to it, and it is always taken down verbatim, without polishing.

## The command key

Hold to speak, release to run.

| Input | Default |
| --- | --- |
| VibeKey | Long-press the dial and keep holding; release when done. While command mode is on, the model entry is a long press of OK |
| Controller | Hold L2 |
| Keyboard | Hold right ⌥ on its own for about 0.2 s; Settings offers the other right-hand modifiers, or none |
| Remote | No default; bind one yourself |

Under Devices & inputs you can bind “Command (hold to speak)” to any button, and a binding you made yourself takes precedence over these defaults. On a button that cannot be held, one press starts and the next press ends. When command mode is turned off these defaults go away, and a long press of the VibeKey dial opens the model entry again.

Right ⌥ pressed together with another key is an ordinary modifier and is not taken as a command.

## What you can say

- **Find a chat.** “Switch to the Codex chat about the microphone.” Codex is asked for its own chat list and the chat is opened directly; when several fit, the overlay lists them.
- **Find a chat in other apps.** Claude, DeepSeek Harness, WorkBuddy, Feishu and WeChat have no list to query: VibeWand brings the app forward, opens its own search and types the keywords, and you pick with the dial as usual.
- **Switch apps, open a file or a URL.** “Open Notes.”
- **Operate the window in front.** “Open the Runtime.swift tab.” VibeWand reads that window's controls, then presses one, sends a shortcut, chooses a menu item, or puts text into a field.
- **Correct it.** Press the command key again and say “not that one, the next”. Commands within five minutes belong to one conversation.

Speaking a new command interrupts the previous one at once.

## While it runs

The overlay's speech bar shows what was heard, the step in progress, and any question waiting for you. If you keep the overlay hidden, it comes out for the duration of a command and goes away afterwards.

| When needed | Device | Keyboard |
| --- | --- | --- |
| Choose | Dial, stick or R1 / R2 | ↑ ↓ |
| Confirm | Confirm button | Return |
| Stop | Back button (ESC on VibeKey) | Esc |

On the keyboard, the arrows and Return go to the command only while a question waits for your answer; while it is acting, only Esc is taken. A question left unanswered for 45 seconds counts as cancelled. One command runs for at most 24 steps and 120 seconds.

## What it does not do

- **It never sends or submits.** Text it types stays in the field; sending is yours.
- **Deleting and sending always wait for you:** buttons and menu items whose name contains delete, discard, don't save, send, submit, pay and the like; Return in a multi-line field; and ⌘Return, ⌘⌫ and ⌘Q.
- **It operates one app:** the one in front when you pressed the command key, or the one it brought forward for you. Once you move elsewhere, what follows is dropped.
- **No screenshots and no coordinate clicks.** Interfaces whose controls cannot be read, such as canvases and custom-drawn content, are out of reach.
- **It does not read what fields and documents contain,** only whether a field is empty, and it never types into a password field.
- **No shell and no file access.** The model can call 13 tools and nothing else; see the [development guide](development.md).

## What is sent

While command mode is on, the model service you configured receives:

- the words of your command;
- app names, window titles, chat titles, project folder names, and the names of running apps;
- when the interface is operated, the labels of controls in the front window: button names, tab titles, menu items.

It does not receive the contents of fields and documents, selected text, the clipboard, or screenshots. Audio is handled as set under Voice input and does not pass through the model service.

With command mode off, VibeWand behaves as before and reads none of this.

**Records on this Mac.** The words of each command and the steps taken are kept in `~/Library/Application Support/VibeWand/tasks/`, without anything read from windows, and deleted after 14 days. The kernel's own conversation log is under `kernel/` in the same folder and is kept only for its latest start. Settings → Command mode → Clear all records removes both.

**The kernel.** Command mode ships DeepSeek Harness as its kernel, reduced to a model, a session and the tools VibeWand provides: none of its own shell, file, web, skill or subagent tools, and without the two components that attach the session log and the plugin list to model requests. It uses a folder of its own and does not touch a DeepSeek Harness you run yourself. It creates a random installation identifier in that folder and sends it with model requests; clearing the records replaces it.

## What has been verified

Covered by automated tests and by runs against the real model: the kernel process and tool channel, cancellation, choosing and stopping, the command key bindings, and the start-up of the bundled kernel.

Not yet observed in the real apps, so watch for these in use:

- whether Codex's `codex://threads/…` link lands on the chat it names;
- whether the tabs and controls of apps such as VS Code can all be read;
- whether holding right ⌥ conflicts with your input method or other software;
- typing the keywords into each app's own search.

## Not implemented yet

Handing selected content to another tool, and relays of the kind “run it in one tool, hand the result to another”; see the [design document](VibeWand_Computer_Use_设计方案.md) (Chinese).
