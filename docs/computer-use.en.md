# Computer use

[简体中文](computer-use.md) · [Applications](applications.en.md) · [Command mode](command-mode.en.md) · [Documentation](README.md)

> **One wand to command them all.**
> You say what you want. VibeWand finds it, opens it, presses it and puts the text in place; the work is still done by the software you chose.

Every VibeWand feature comes down to operating an app on your Mac for you. This page covers how it looks at an interface, which actions it can take, which route each app uses, and what has been verified. For how to use it, see [Default controls](core-experience.en.md) and [Command mode](command-mode.en.md).

**Both parts ship in 0.9.0 and need macOS 26. Command mode does nothing until a model is set up.** New in 0.10.0: a picture of the window that can be turned on, the harness's own tools in plugin mode, and three changes to how command mode reads a window (a menu that just opened leads the list, what the app announces is read, and a key can be sent to one control).

## Two ways to drive it

| | Driven by buttons | Driven by a sentence (command mode) |
| --- | --- | --- |
| Way in | Dial, buttons, sticks | Hold the command key and speak |
| Who decides what happens | Fixed rules: a button plus the current context maps to one action; no model is involved | The model you configured, choosing step by step among 13 tools (not counting what you hand it yourself) |
| Good for | Frequent, definite actions: scrolling, moving the caret, picking a chat, changing the model, dictating | Things that are easy to say and awkward to press: “switch to the chat about the microphone”, “open the Runtime.swift tab” |
| Reach | The [supported apps](applications.en.md) and the rules you added | Any app whose controls can be read, one at a time |

Both use the same means: the control structure that macOS Accessibility provides, plus synthesized key, scroll and pointer events. They also hand over to each other: once a sentence has opened an app's own search, turning to choose and pressing to confirm is back on the buttons.

## How it looks at an interface

Computer use commonly means a model that looks at screenshots and outputs coordinates. VibeWand takes the other route: it reads only controls that have a name, and it presses that control itself. What it reads is the control tree an app publishes through macOS Accessibility, the same one a screen reader is given. That is why it needs your approval under System Settings → Privacy & Security → Accessibility. By default it needs no screen-recording permission and takes no screenshot.

A picture is something command mode can be given in addition, and it is off by default; see [Let the model see the window](command-mode.en.md#let-the-model-see-the-window). With it on, the model may ask for a picture of the window being operated, with the controls' ids marked on it: it recognises things by eye and still presses controls, never coordinates. The button-driven part is not affected by this setting and never takes a screenshot.

| What is read | What it is used for |
| --- | --- |
| The front app's bundle ID | Choosing the adapter; apps that are not on the list receive no app actions |
| The identity of the window and the focused control | Tying an action to the target that was there when you pressed |
| Whether focus is in an editable field, and whether the draft is empty | Deciding whether turning scrolls or moves the caret, and whether ESC cancels or deletes |
| Whether a chat, model or effort list is open, its rows and the selected one | Moving through candidates; the current row's title is shown only on the overlay |
| Named buttons beside the composer, and the sidebar's chat list | Pressing the model, effort and search buttons directly; choosing chats row by row in DeepSeek Harness |
| Whether an input method is composing, and whether an unknown dialog is open | In both cases only the native Return and Esc are sent |
| In a terminal, the few rows of text next to the cursor | Telling whether the cursor is at a recognised prompt, whether the prompt holds a draft, and whether a list covers the prompt |
| Command mode also reads: window titles, the kind, name and state of the controls in the front window, and the menu bar; a field's character count and caret before and after typing into it; the status line an app announces to a screen reader, and the keys a web control says it is worked with (since 0.10.0) | Letting the model find the control to press; checking that typed text arrived; knowing where a control that is set with keys stands, and which key sets it |

What is not read: conversation text, document contents, selected text. A field's content is reduced to “empty” or “has text”. The clipboard is only saved while something is pasted and then put back. Command mode's list of controls skips static text and images and keeps buttons, tabs, menu items, fields, list rows and the like. Since 0.10.0 there is one exception: the line an app marks as a status or an alert, which a screen reader would speak, is read too, such as Codex's “GPT-6 Astra Extra High, 4 of 5.” while its effort is being set. An announcement longer than 80 characters is not read.

A terminal is the one place where text is read. It draws its whole interface as text and has no composer control, so VibeWand reads from at most 12 rows above the cursor to the end of the screen, never the scrollback. In memory that is reduced to one of a few states (empty prompt, draft, open list, some other screen) and dropped; it is not stored, logged or exported.

Electron apps such as DeepSeek Harness and WorkBuddy do not publish their web content to Accessibility by default; VibeWand asks them to the first time it sees them.

## The actions it can take

When driven by buttons, one press maps to one of these:

| Action | How | Where it is used |
| --- | --- | --- |
| Press a control | The Accessibility “press” action; if a candidate row refuses it, a click at the row's centre instead | Model and effort buttons, WorkBuddy's search button, candidate rows |
| Adjust a slider | The Accessibility increment and decrement actions | Reasoning effort in Codex and Claude |
| Send keys | Synthesized keys delivered to the target app | `⌘K`, `⌃Tab`, `⌘L`, arrows, Return, Esc, Backspace |
| Scroll | A scroll-wheel event at the conversation's position; the pointer then returns to where it was | Reading replies |
| Move the pointer | Parked on the current candidate row and returned afterwards; the controller's touchpad moves the pointer directly and a tap clicks | Model lists and the Harness sidebar; the touchpad works in any app |
| Write text | Native fields are edited as you speak, limited to the dictated range; other apps get one paste on release, and the clipboard is put back | Dictation, in any app |
| Type a command | Paste `/resume` or `/model` at an empty prompt only, and press Return once the line holds that command alone | Claude Code, Codex and OpenCode in a terminal |
| Switch apps | Bring up the system app switcher, turn to choose, confirm | Any app |

## Command mode's 13 tools

By default this table is everything the model can do. There is no shell, no file access, no web access and no coordinate click. Two more things can be handed to it, and each has to be turned on by you: a fourteenth tool, `ui_screenshot`, which shows it a picture of the window being operated; and, in plugin mode, the shell, file, web and other tools of your own DeepSeek Harness. See [What the model can use](command-mode.en.md#what-the-model-can-use).

| Tool | What it does | Kind |
| --- | --- | --- |
| `list_targets` | Lists the apps that can be operated, whether they are running, and the app and window you were in when you spoke | Read |
| `find_sessions` | Queries an app's own chat list: title, project folder, last update. Codex only for now | Read |
| `open_session` | Opens one chat that was found and brings its app to the front | Navigate |
| `search_in_app` | Brings an app to the front, opens its own search and types the keywords; you then pick with the dial | Navigate |
| `activate_app` | Brings an app to the front, optionally opening a file or URL in it | Navigate |
| `ui_snapshot` | Lists the controls in the front window: id, kind, name, state. Since 0.10.0, what is new or changed since the snapshot before comes first, so a menu that a press opened is not buried at the end of a long window; an app's model picker is marked as such | Read |
| `ui_press` | Presses a control from the snapshot | Navigate |
| `ui_key` | Sends one shortcut, such as `cmd+p`, `ctrl+tab` or `escape`. Since 0.10.0 it can be addressed to one control, which takes keyboard focus first; that is how a control set with the arrow keys is changed. One press for each call, and the answer carries what the app announced in reply | Navigate |
| `ui_menu` | Chooses a menu bar item by its path of titles, such as File → Open Recent → notes.md | Navigate |
| `ui_type` | Types into a field without pressing Return | Write |
| `choose` | Lists up to six candidates on the overlay for you to pick with the dial | Asks you |
| `finish` | Ends the task and tells you the result in one line | Asks you |
| `need_user` | Stops when it cannot go on and says what is missing | Asks you |

One command runs for at most 24 steps and 120 seconds. A question left unanswered for 45 seconds counts as cancelled.

## Which route each app uses

| App | Driven by buttons (released) | Finding a chat in command mode |
| --- | --- | --- |
| Codex | `⌘K` palette; effort slider and model list | Codex's own chat list is queried, the latest 60 are filtered by title and project folder, and the chat is opened with `codex://threads/…`. The list holds this Mac's chats only; when nothing matches or the list is unavailable, the `⌘K` palette is opened with the keywords in it |
| Claude | `⌘K` palette; model menu, then the effort slider | Opens the `⌘K` search and types the keywords; you pick with the dial |
| DeepSeek Harness | Sidebar chat list; two-level model menu | Enters the sidebar chat list and you pick row by row; there is no search field to type into |
| WorkBuddy | Sidebar task search; model menu | Opens Global search and types the keywords |
| Feishu / Lark | `⌘K` to search and switch chats | Opens the `⌘K` search and types the keywords |
| WeChat | `⌘F` search, a compatibility mapping | Sends `⌘F`; keywords are typed only once the search is seen to be open |
| Claude Code, Codex and OpenCode in iTerm2 | `/resume` and `/model` typed at an empty prompt, then arrows, Return and Esc in the list; with a draft, caret movement and delete | No dedicated route |
| Browsers | Next tab, address bar, scrolling | No chats |
| Any other app | The shortcut rules you added; dictation and app switching | No chats |

In command mode, switching apps, opening a file or URL, and operating the front window do not depend on the app. Any window whose controls can be read is treated the same: `ui_snapshot` to look, then `ui_press`, `ui_key`, `ui_menu` or `ui_type` to act.

## The rules that do not change

These are enforced in code, not left to the model.

- **Nothing is sent for you.** Releasing the dictation key presses no Return, and text typed by command mode stays in the field as well, unless your command says in so many words to send it.
- **An action is tied to the target that was there when you pressed.** The app, window and focus are recorded at the press and checked again before acting; if they changed, the action is dropped. Command mode operates one app: the one in front when you spoke, or the one it brought forward for you. Once you move elsewhere, what follows is dropped.
- **Anything with consequences asks every time by default, and how much it asks is yours to set.** Command mode has three permission modes: confirm only what has consequences (the default), that is, buttons and menu items whose name contains delete, discard, don't save, send, submit, pay and the like (since 0.10.0 also those that hand out access: allow, grant, authorize, approve), Return in a multi-line field, and `⌘Return`, `⌘⌫` and `⌘Q`; confirm every step on the device; or ask nothing. The gateway does the asking, so the model cannot go around it. A harness's own tools, when the model has them, are held by the harness's sandbox at the same mode, and a step that would leave the sandbox is put to you through the gateway as well.
- **Password fields are never typed into,** by dictation or by command mode.
- **Input-method candidates and unknown dialogs get only the native Return and Esc,** never a “send” or “search” binding.
- **Apps are recognised from a list.** The full bundle ID must match exactly; window titles and web addresses are not considered. Apps that are unsupported, or that you turned off, receive no app actions.
- **The overlay never takes focus.** Candidates are chosen from the device, so the field and selection you came from stay as they were.
- **Configuration runs no scripts and holds no credentials.** Keys live in the Keychain.
- **You can always stop.** The back button cancels, and in command mode a new sentence interrupts the previous one at once.

What command mode sends to the model service is listed under [What is sent](command-mode.en.md#what-is-sent). With command mode off, or no model set up, VibeWand reads none of that and contacts no model service to decide an action. What it did at each step, and what the model was shown, can be read under [Agent records](command-mode.en.md#agent-records).

## What it cannot do

- Canvases, games and custom-drawn interfaces: there are no controls to read. With the picture turned on the model can see them, and still cannot press anything in them.
- In a terminal only the prompts of Codex, Claude Code and OpenCode are recognised, and iTerm2 is the reference. A prompt in a right-hand tmux pane, other terminals such as Terminal.app, and command-line tools without an adapter are not recognised; the remaining limits are in [Applications](applications.en.md#claude-code-codex-and-opencode-in-a-terminal).
- WeChat's chat controls cannot be read; it has only the `⌘F` compatibility mapping.
- Anything that needs looking at the picture to judge, unless you turned on command mode's picture of the window. The button-driven part does not look at the screen.
- Handing selected content to another tool, and relays of the kind “run it in one tool, hand the result to another”, are not implemented yet.

## What has been verified

| Capability | Status |
| --- | --- |
| Button-driven control of Codex, Claude, DeepSeek Harness and WorkBuddy | Exercised in the real apps on a local machine; versions and scope are in [Applications](applications.en.md) |
| Feishu's `⌘K` search | Checked on the local client |
| Claude Code, Codex and OpenCode in a terminal | Accepted in iTerm2 3.7.3 against Codex CLI 0.160.0, Claude Code 2.1.289 and OpenCode 1.18.34, with the terminal text read back after every step; presses came from the runtime, and physical device buttons were not pressed. See the [acceptance record](terminal-acceptance.md) |
| WeChat | Search candidates and draft editing are unverified |
| Command mode's kernel process, tool channel, cancellation, choosing, and command key | Covered by automated tests and by runs against the real model |
| Command mode's results in real apps | Read back item by item between 2026-10-05 and 10-06 in TextEdit, VS Code, Codex, Claude and Feishu, and the three permission modes and plugin mode in TextEdit; see the [acceptance record](command-acceptance.md). Not run: a microphone and a human voice, physical keys, model services other than DeepSeek and local models, plugin mode on a real harness home, searches aimed at DeepSeek Harness, WorkBuddy and WeChat, and keys, menus and typing in VS Code |
| The picture of the window, the harness's tools, and carrying a conversation on (0.10.0) | Each read back once in a real TextEdit window on the development build before the release, on DeepSeek's model; see the fourth round of the acceptance record. Not run: granting Screen Recording to the released app, and other models looking at a picture |

By this repository's convention, a capability whose result has not been observed in the real app does not count as supported. Keep in mind what the last row lists as not run.
