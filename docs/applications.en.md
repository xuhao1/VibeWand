# Application support

[简体中文](applications.md) · [Computer use](computer-use.en.md) · [Documentation](README.md)

Settings → Applications lets you enable or disable each adapter, with settings saved locally. Unsupported or disabled apps receive no business-action keystrokes. App actions apply to the foreground target. Delayed actions do not continue in an unrelated app or window after focus changes. Recognized input-method candidates and unknown dialogs take precedence and receive native confirm / cancel behavior.

## Supported programs at a glance

Apps are recognised by their full bundle ID, never by a window title or a web address.

| Program | Bundle ID | Chats | Models | Verification |
| --- | --- | --- | --- | --- |
| [Codex](#codex) | `com.openai.codex` | `⌘K` palette | Effort slider; press again for the model list | Exercised on a real machine |
| [Claude](#claude) | `com.anthropic.claudefordesktop` | `⌘K` palette | Model menu, then the effort slider | Exercised on a real machine |
| [DeepSeek Harness](#deepseek-harness) | `com.deepseek.dsh` | Sidebar chat list | Two-level model menu | Exercised with 0.2.0-rc.2 |
| [WorkBuddy](#workbuddy) | `com.tencent.workbuddy.mac` | Sidebar search, `⌘K` fallback | Model menu | Accepted on 5.6.2 |
| [Claude Code, Codex and OpenCode in iTerm2](#claude-code-codex-and-opencode-in-a-terminal) | `com.googlecode.iterm2` | Types `/resume` at an empty prompt | Types `/model` at an empty prompt | Accepted in iTerm2 3.7.3; see the [acceptance record](terminal-acceptance.md) |
| [Browsers](#browsers): Safari, Chrome, Edge, Brave, Firefox, Opera, Vivaldi | Each browser's own bundle ID, including Safari Technology Preview, Chrome Beta / Canary and Firefox Developer Edition | `⌃Tab` for the next tab | `⌘L` for the address bar | Standard system shortcuts |
| [WeChat](#wechat-and-feishu) | `com.tencent.xinWeChat`, `com.tencent.WeChat` | `⌘F` | — | Compatibility mapping; chat controls in 4.1.15 cannot be read |
| [Feishu / Lark](#wechat-and-feishu) | `com.electron.lark`, `com.bytedance.Lark`, `com.larksuite.Lark` | `⌘K` | — | `⌘K` search checked on the local client |
| [Any other app](#add-a-custom-application) | The bundle ID you choose | The shortcut you assign | The shortcut you assign | Depends on the target app |

What VibeWand reads and presses in each app, and how command mode finds chats in each one, is in [Computer use](computer-use.en.md).

## Apps that are not on the list

An unsupported app receives no app actions such as chats, models or scrolling. Three things work regardless of the app:

- **Dictation.** It follows the keyboard focus. Native fields fill in as you speak; other apps get one paste on release, after which the clipboard is put back; an app whose field cannot be read is pasted into at the caret. Password fields never receive dictation.
- **App switching.** Double-press the dial or the controller's ×, turn to choose, confirm.
- **The pointer.** The controller's touchpad moves the pointer, and a tap clicks.

To make an app respond to the chat and model buttons as well, [add a custom rule](#add-a-custom-application). [Command mode](command-mode.en.md), which is in the source but not yet in the download, can also operate the front window of any app whose controls can be read.

## Codex

Chats open through the `⌘K` command palette: turn to choose, confirm to open.

The model button (the one labelled with the current model) is pressed through accessibility rather than a shortcut. Current Codex builds put effort and model in one popover: the first "model / effort" press opens the effort slider, which turning adjusts; pressing again inside the popover opens the model list, and confirming a model returns to effort. `⌃⇧M` is only the fallback when no button is found.

An empty composer's placeholder is not a draft, so turning still scrolls while the empty composer has focus.

## Claude

Claude desktop (`com.anthropic.claudefordesktop`). Chats open through the `⌘K` search palette. The model action presses the "Model: …" button beside the composer and turning moves through the menu; confirming a model continues to the "Effort" slider, which you can simply back out of. Dictation is pasted into the composer on release.

Exercised on a real machine: dictation, opening / moving / cancelling the chat palette, opening / moving / confirming in the model menu, and recognition of the effort popover.

## DeepSeek Harness

Harness is an Electron app and does not publish its web content to accessibility clients by default. VibeWand asks it to (`AXManualAccessibility`) the first time it sees the app; only then can the composer and buttons be recognised.

Its `⌘K` is a name filter for the sidebar, and arrow keys do not pick rows there, so chats are chosen from the sidebar's chat list itself: press once to enter, turning parks the pointer on each row, confirm opens it and back leaves everything untouched. It ends by itself after 20 idle seconds. Workspace rows are in the list too; confirming one expands or collapses it.

The model action presses the "Select model, current …" button. The menu has two levels: confirm the "Model" row, then choose in the submenu.

Exercised on a real machine with `0.2.0-rc.2`: dictation, switching chats and back, and entering / cancelling the two-level model menu.

## WorkBuddy

WorkBuddy desktop (`com.tencent.workbuddy.mac`) has a built-in integration from 0.8.0. Settings → Applications can disable it independently.

<p><img src="images/applications-v080-en.png" width="720" alt="VibeWand 0.8.0 application settings including WorkBuddy"></p>

This is a hidden-window rendering of the implemented 0.8.0 settings page, not a capture of live WorkBuddy operation.

The chat action first presses the sidebar's Search button. In 5.6.2, both this button and the default `⌘K` open Global search. Enter a query, choose the Tasks category if needed, turn to select a result, confirm to open, and back to cancel. With no recent searches, a query is needed first. If the sidebar is hidden or its button is unavailable, the action falls back to `⌘K`; expand the sidebar if the composer intercepts it. A custom integration can override a changed shortcut.

The model action presses the composer's button labelled `Select model`. Turn to choose a model, confirm to apply, and back to close the menu. Disabled models, the Max switch and settings actions are excluded from model candidates. Thinking toggles and finer reasoning settings remain in WorkBuddy's own model-detail menus.

Dictation is pasted once into the current composer on release, then the clipboard is restored; it does not send a message. Turning moves the caret and ESC deletes when a draft has text; an empty draft scrolls. On first contact, VibeWand asks Electron to publish its accessibility content.

0.8.1 passed live acceptance on the installed WorkBuddy **5.6.2** using native accessibility and key events. Checks read back search-result selection, confirmed task opening and return to Home, changed and restored the model, pasted text, moved the caret and deleted. The full dictation-delivery pipeline was exercised with transcript replay: it appended to an existing test draft, waited until completion to paste, and restored the clipboard. See the [acceptance record](workbuddy-acceptance.md).

The run fixed an unrecognised `AXComboBox` model trigger and an empty composer whose placeholder, including extra inline spacing, was exposed as draft text. Audio recognition and physical-device input were not retested in this adapter acceptance run.

## Claude Code, Codex and OpenCode in a terminal

Built for iTerm2 (`com.googlecode.iterm2`); it can be turned off under Settings → Applications. A terminal draws its whole interface as text and has no composer control to read, so VibeWand reads the few rows around the cursor and works out three things: whether the cursor sits on a prompt it knows, whether that prompt holds a draft, and whether a list is covering it. The prompts it knows are Codex's `›` and Claude Code's `❯`, both in the first column, and the `┃` to the left of OpenCode's input box.

| On screen | Turning | ESC | Dial press / long press | OK |
| --- | --- | --- | --- | --- |
| An empty prompt | Scrolls | Escape; while the agent is working this interrupts it | Types `/resume` / `/model` and Return | Return |
| A prompt with a draft | Moves the cursor left and right | Deletes the character before the cursor; hold to keep deleting | Leaves the draft alone and says to send or clear it first | Return, which sends |
| A list VibeWand opened | ↑ / ↓ | Esc: back or cancel | Return to confirm | Return |
| Anything else: a shell, a list opened from the keyboard, an approval question | Scrolls | Escape; hold for Backspace | Types nothing | Return |

Dictation is pasted at the prompt on release and nothing is sent for you. On the controller layout □ deletes, ○ confirms and × is Escape, following the same states.

<p><img src="images/terminal-v084-codex.jpg" width="560" alt="Codex CLI 0.160.0 in iTerm2 with its model list open and the third row selected"></p>

The image above is an actual window screenshot from the 0.8.4 acceptance run: after a long press typed `/model` and two steps of turning, Codex's model list rests on its third row.

Things to know:

- **How a command is typed.** Only at an empty prompt. The command is pasted, so an active Chinese input method cannot swallow its letters, and your clipboard is put back afterwards. Return is pressed once the prompt row holds that command and nothing else. If there is other text on the row, Return is not pressed and the command stays where it is; it is never sent together with a draft. The `⌃U` that 0.8.3 and earlier used to clear the input line is gone, so a draft is no longer wiped.
- **When a list counts as open.** VibeWand typed the command and a list really appeared: the prompt is gone and the screen shows a key hint for Esc. It ends the moment the prompt is back, instead of on a timer. The effort list Codex shows after a model is chosen, and the model list that Esc in the effort list returns to, are both followed. It also ends after 20 seconds without input; press ESC and open it again.
- **What counts as a draft.** Text before the cursor, or a draft that wraps or runs over several rows. Moving the cursor all the way to the start leaves it a draft: VibeWand remembers a fingerprint of the text, not the text.
- **Scrolling.** Codex, OpenCode and Claude Code's fullscreen renderer take over the mouse wheel and scroll their own transcript; Claude Code's classic renderer scrolls iTerm2's scrollback. With a draft at the prompt, turning moves the cursor instead, as in every other app.
- **While the agent is working.** Codex and Claude Code spin a mark in the window title while they work, Codex about ten times a second. 0.8.3 and earlier treated the title as part of "has the target changed", so once an agent was working, ESC, delete and OK were all dropped as aimed at a changed target. A terminal's title no longer takes part in that check.
- **What is read.** Only the text from at most 12 rows above the cursor to the end of the screen, never the scrollback. It is reduced in memory to the states above and dropped: not kept, logged or exported.

What each tool does on its own:

- In Claude Code's model list Return means "set as default"; "this session only" is `s` on the keyboard, and effort is `←` / `→` on the keyboard. Its fullscreen renderer shows an argument hint after a command (`/model [model]`), which VibeWand recognises.
- In Codex's effort list Return also sets the default. While a task is running Codex refuses `/resume` and `/model` itself; VibeWand does not take a list to be open.
- OpenCode completes `/resume` to `/sessions` and `/model` to `/models`. It folds a paste longer than 150 characters or 3 lines into `[Pasted ~1 lines]`, so a longer dictation is not readable in the box; add `"experimental": { "disable_paste_summary": true }` to `opencode.json` to see the text.

Known limits:

- In a tmux split, a prompt in a right-hand pane does not start its row and is not recognised.
- Codex's `!` shell mode and Claude Code's `!` and `#` modes change the mark at the start of the row and do not count as a prompt: ESC is Escape, and holding it sends Backspace.
- With the cursor at the very start of a draft VibeWand has not seen before, the draft looks like a placeholder. Pressing the dial then types the command, but Return is not pressed because the row holds other text.
- Lists opened from the keyboard and approval questions are not taken over by turning; OK confirms the current choice and ESC declines or cancels.
- A shell whose own prompt starts its row with `›` or `❯` (starship's default, for one) is taken for an agent's prompt: with a command typed, ESC deletes and turning moves the cursor; pressing the dial at an empty one types `/resume`, which the shell answers with a not-found error.
- Command-line tools without an adapter get scrolling, Escape, Return and pasted dictation only. Other terminals such as Terminal.app are not adapted.

0.8.4 passed live acceptance in the installed iTerm2 **3.7.3** against Codex CLI **0.160.0**, Claude Code **2.1.289** (classic and fullscreen renderers) and OpenCode **1.18.34**: pasted dictation, deleting by press and by hold, cursor movement, refusing to open a list over a draft, opening, moving in and cancelling the chat and model lists, and deleting and interrupting with Escape while Codex was working. Keys were sent by the production runtime and each step was checked by reading the terminal text back; physical device buttons were not pressed in this run. See the [acceptance record](terminal-acceptance.md).

## Browsers

The browser allowlist includes Safari, Chrome, Edge, Brave, Firefox, Opera, and Vivaldi. Default rotation scrolls the page. Pressing the dial sends `⌃Tab` for the next tab; the model-entry action maps to `⌘L` for the address bar.

A focused webpage input does not automatically turn default rotation into caret movement. Explicit caret actions remain configurable. Double-press still opens global application switching.

## WeChat and Feishu

These apps share reading, editing, search, confirm, and cancel behavior through keyboard mappings: `⌘F` for WeChat and `⌘K` for Feishu. A nonempty draft supports caret movement and deletion; reading / empty drafts scroll. Candidates and dialogs take priority. OK sends Return, whose send/newline meaning follows the application's own preference.

Feishu’s `⌘K` search dialog was checked on the local client. WeChat 4.1.15 did not expose readable chat controls to Accessibility, so `⌘F` remains a compatibility mapping and search-candidate / draft automation is unverified. Destructive editing is allowed only after observing an editable input.

This integration does not use Feishu cloud APIs, organization profiles, contact lists, or account credentials.

## Add a custom application

In Applications, add an app and choose its local `.app` bundle to read its name and full bundle ID, or enter them manually. Rules match that exact bundle ID; another app with the same display name does not match. Start with Chat app, Browser, or Custom, then assign a key and ⌘ / ⌥ / ⌃ / ⇧ modifiers to each operation. Rules can be edited, enabled / disabled, or removed and are saved locally.

| Preset | Primary: chats / tabs | Secondary: search / address bar | Context behavior |
| --- | --- | --- | --- |
| Chat app | `⌘K` | `⌘K` | Reading, draft editing, and observed search-candidate behavior |
| Browser | `⌃Tab` | `⌘L` | Default navigation scrolls even while a webpage input has focus |
| Custom | Unassigned | Unassigned | Uses configured shortcuts without assuming chat or model pickers |

All three presets provide Return confirmation, Escape cancellation, up / down candidates, left / right caret movement, and Backspace deletion; each shortcut is editable. Empty scroll bindings use native scrolling, or you can specify an app's own scroll shortcuts. Input-method candidates and unknown dialogs retain native Return / Escape, so a chat-send binding does not replace native confirmation.

A custom rule takes precedence over a built-in adapter for the same bundle ID. Disabling that rule disables adaptation for that app; removing it restores the built-in rule. Presets are editable starting points: the target app must support the chosen shortcuts. Sending a key is not evidence of an observed picker or universal compatibility with all chat apps and browsers.
