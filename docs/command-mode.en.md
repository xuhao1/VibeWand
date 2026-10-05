# Command mode

[中文](command-mode.md) · [Computer use](computer-use.en.md) · [Documentation](README.md)

Hold the command key and say what you want. When you release it, VibeWand finds the app, chat or control for you. It finds, opens, presses and puts text in place; the work itself is still done by the software you chose.

**Ships in 0.8.5. Needs macOS 26.**

## Set up a model

Command mode is on by default, and does nothing until a model is set up: the command key is inert, the device's keys keep what they did, and nothing leaves this Mac. Under Settings → Command mode → Model:

1. **Pick a service.** DeepSeek, OpenAI, Anthropic, OpenRouter, Google Gemini, Alibaba Model Studio, Moonshot, Zhipu, Volcengine Ark and SiliconFlow are built in, as are Ollama, LM Studio and oMLX on this Mac. For anything else choose Custom address, type the address and pick the protocol: OpenAI Chat Completions, OpenAI Responses or Anthropic Messages.
2. **Save the API key for that address.** It is kept in this Mac's Keychain per address and never carried to another one; the command kernel is handed it only when it starts. Usage is billed to your account with that service. A server on this Mac and a custom address may need none.
3. **Pick a model.** Fetch models asks the service for its list; when it offers none, type the model ID.
4. Press Save and test. The kernel asks the model for one word with these settings and tells you how long it took. A failure is shown in the service's own words, such as an invalid key or an unknown model.

Also adjustable:

| Setting | Meaning |
| --- | --- |
| Reasoning | Model default, off, low, medium or high. Model default sends no parameter. Commands are short, and turning it down or off usually makes them quicker |
| Context length | How many tokens the model holds. Filled in when you pick a model from a list that states it; left empty, the kernel assumes 262144. Give a local model its real size |
| Extra settings (JSON) | Merged as they are into the kernel's settings for this service, over the generated ones of the same name. For a local Qwen that should stop thinking: `{"compat": {"thinkingFormat": "qwen-chat-template"}}` |
| Notes for the model | Told to the model at the start of every conversation: what you call things, the apps you prefer, nicknames of projects. They add to the rules and cannot change them |

Of the built-in services, only DeepSeek has been run with a real key, once over each of its OpenAI-compatible and Anthropic-compatible protocols; for the others only the address was checked to exist. Signing in to an account with OAuth is not supported, only API keys.

A command is recognised by the built-in recogniser: macOS dictation, or the speech API configured under Voice input. Whether you dictate through an external input method makes no difference to it, and it is always taken down verbatim, without polishing.

## Permission

Settings → Command mode → Permission decides how much it asks before it acts:

| Mode | What happens |
| --- | --- |
| Ask every time (default) | Switching apps, opening a chat, pressing a control, sending keys and typing each show on the overlay what is about to happen and wait for your confirm key. Reading the window and searching do not |
| Ask when risky | Navigation and typing run at once. Buttons and menu items whose name contains delete, discard, don't save, send, submit, pay and the like, Return in a multi-line field, and ⌘Return, ⌘⌫ and ⌘Q wait for you every time |
| Bypass all | Nothing is asked, deleting, sending and submitting included. When the model picks the wrong control or mishears you, those happen too |

In every mode the back key stops at any moment, a choice between several candidates is still yours, and once you move to another app what follows is dropped.

## The command key

Hold to speak, release to run.

| Input | Default |
| --- | --- |
| VibeKey | Long-press the dial and keep holding; release when done. While command mode is usable, the model entry is a long press of OK |
| Controller | Hold L2 |
| Keyboard | Hold right ⌘ on its own for about 0.2 s; Settings offers the other right-hand modifiers, or none |
| Remote | No default; bind one yourself |

Under Devices & inputs you can bind “Command (hold to speak)” to any button, and a binding you made yourself takes precedence over these defaults. On a button that cannot be held, one press starts and the next press ends. With command mode turned off, or no model set up yet, these defaults do not exist and a long press of the VibeKey dial is still the model entry.

Right ⌘ pressed together with another key is an ordinary modifier and is not taken as a command. A key that an input method or another app has taken never reaches VibeWand: the Doubao input method, for one, uses a held right ⌥ for voice, which is why that key is not the default. If holding the key does nothing, pick another.

## What you can say

- **Find a chat.** “Switch to the Codex chat about the microphone.” Codex is asked for its own chat list and the chat is opened directly; when several fit, the overlay lists them. The list holds only the chats kept on this Mac; when nothing matches, Codex's own `⌘K` search is used.
- **Find a chat in other apps.** Claude, DeepSeek Harness, WorkBuddy, Feishu and WeChat have no list to query: VibeWand brings the app forward, opens its own search and types the keywords, and you pick with the dial as usual.
- **Switch apps, open a file or a URL.** “Open Notes.”
- **Operate the window in front.** “Open the Runtime.swift tab.” VibeWand reads that window's controls, then presses one, sends a shortcut, chooses a menu item, or puts text into a field.
- **Correct it.** Press the command key again and say “not that one, the next”. Commands in one conversation see each other; see [Conversation and context](#conversation-and-context).

Speaking a new command interrupts the previous one at once.

## While it runs

The overlay's speech bar shows what was heard, the step in progress, and any question waiting for you. Its last line is the state of this command: the model acting, how full its context is (used over total and a percentage, or “new conversation”), the step it is on, and the permission mode in force. If you keep the overlay hidden, it comes out for the duration of a command and goes away afterwards.

| When needed | Device | Keyboard |
| --- | --- | --- |
| Choose | Dial, stick or R1 / R2 | ↑ ↓ |
| Confirm | Confirm button | Return |
| Stop | Back button (ESC on VibeKey) | Esc |

On the keyboard, the arrows and Return go to the command only while a question waits for your answer; while it is acting, only Esc is taken. A question left unanswered for 45 seconds counts as cancelled.

## Conversation and context

Commands that follow one another belong to one conversation, which is why “not that one, the next” works. Settings → Command mode → Conversation and context changes:

| Setting | Default | Meaning |
| --- | --- | --- |
| Keep a conversation | 5 minutes | How long without a command before the next one starts a new conversation: every command afresh, 5 minutes, 30 minutes or 2 hours |
| Longest one command may run | 2 minutes | Waiting for your answers included. Raise it for a slow local model, up to 10 minutes |
| Most steps in one command | 24 | How many tools the model may call: 12, 24 or 48 |

Once a conversation has used four fifths of its context, the next command starts a new one. “Start a new conversation now” ends the current one at once, and so does changing any command-mode setting. The card says how many commands the current conversation holds and how much context it has used.

## Agent records

Settings → Command mode → Agent records → View records… lists recent commands by time. Pick one to see the words of the command and the app you were in, what the model thought, every tool call with its arguments and what it returned, which steps you confirmed or declined, the context in use after each reply, and the line you were told at the end.

The records are kept in `~/Library/Application Support/VibeWand/tasks/` and deleted after 14 days. They include what tools returned, that is, the titles of apps, windows and chats and the labels of controls, cut at 4000 characters each. The kernel's own conversation log is under `kernel/` in the same folder and is kept only for its latest start. Clear all records removes both.

## What it does not do

- **It does not send or submit on its own.** Text it types stays in the field. Only when your command says to send, submit or delete does it do so, and then it asks you first as the permission mode above requires; with Bypass all it no longer asks.
- **It operates one app:** the one in front when you pressed the command key, or the one it brought forward for you. Once you move elsewhere, what follows is dropped.
- **No screenshots and no coordinate clicks.** Interfaces whose controls cannot be read, such as canvases and custom-drawn content, are out of reach.
- **It does not read what fields and documents contain,** only whether a field is empty, how many characters it holds and where its caret is, to check that typed text arrived. It never types into a password field.
- **No shell and no file access.** The model can call 13 tools and nothing else; see the [development guide](development.md).

## What is sent

Once a model is set up, the model service you chose receives:

- the words of your command;
- app names, window titles, chat titles, project folder names, and the names of running apps;
- when the interface is operated, the labels of controls in the front window: button names, tab titles, menu items.

- the notes you wrote for the model.

It does not receive the contents of fields and documents, selected text, the clipboard, or screenshots. Audio is handled as set under Voice input and does not pass through the model service.

With command mode off, or no model set up, VibeWand behaves as before, reads none of this and contacts no model service.

**The kernel.** Command mode ships DeepSeek Harness as its kernel, reduced to a model, a session and the tools VibeWand provides: none of its own shell, file, web, skill or subagent tools, and without the two components that attach the session log and the plugin list to model requests. The model service is reached through its own multi-provider component; VibeWand hands it the address, model and settings at start, and the key lives only in its process environment, never on disk. It uses a folder of its own, does not touch a DeepSeek Harness you run yourself, and does not use the accounts you signed in to there. It creates a random installation identifier in that folder and sends it with model requests; clearing the records replaces it.

## What has been verified

On 2026-10-05 it was run against real apps in two rounds, with every result read back from the app; see the [acceptance record](command-acceptance.md):

- **TextEdit:** typing; a Return that needs confirmation, confirmed once and refused once; a menu item; opening an app by its Chinese name and switching back.
- **Permission modes:** under Ask every time, typing is asked about first, goes into the document when confirmed and stays out when declined; under Bypass all, Return runs without a question.
- **VS Code:** opening a tab by name, and “not that one, the other”.
- **Codex:** opening a chat by title, with the link landing on the chat it names; asking when several fit; falling back to the `⌘K` search when the list has no match; pressing the window's Back button.
- **Claude and Feishu:** opening the search with the keywords in it, then picking with the dial and closing with the back button.
- **Keyboard:** right ⌘ held on its own starts listening; while a question waits, the arrows and Return answer it and do not reach the app in front.

Worth knowing in use:

- **VS Code takes it for a screen reader.** After its controls are read for the first time, VS Code asks whether to turn on “screen reader optimized” mode and shows it in the status bar. Answer No, or set `editor.accessibilitySupport` to `off` in VS Code's settings.
- **Codex chats that live on a remote machine are not in the list** and are found only through the `⌘K` search.
- After a Codex chat is opened the overlay adds “result not verified”: the app cannot read back where the link landed.
- **Not every service takes a reasoning level.** When one is chosen and the service refuses it, Save and test reports the error; go back to Model default, or spell out the service's format under Extra settings.

Not verified: the whole experience with a microphone and a human voice (the runs replayed transcripts); physical keys (the keyboard key was a synthetic event); the app's own settings page and overlay as they look while running (only off-screen renders were checked); model services other than DeepSeek, and local models; searches aimed at DeepSeek Harness, WorkBuddy and WeChat; keys, menus and typing in VS Code.

## Not implemented yet

Handing selected content to another tool, and relays of the kind “run it in one tool, hand the result to another”; see the [design document](VibeWand_Computer_Use_设计方案.md) (Chinese).
