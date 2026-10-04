# Application support

[简体中文](applications.md) · [Documentation](README.md)

Settings → Applications lets you enable or disable each adapter, with settings saved locally. Unsupported or disabled apps receive no business-action keystrokes. App actions apply to the foreground target. Delayed actions do not continue in an unrelated app or window after focus changes. Recognized input-method candidates and unknown dialogs take precedence and receive native confirm / cancel behavior.

## Codex

The adapter supports conversations, draft editing, models, and reasoning effort. Conversation entry uses native `⌘K`; model entry uses native `⌃⇧M`. VibeWand reads available model and effort options from the actual UI instead of maintaining its own model catalog.

A picker must be observed before picker-specific navigation and confirmation are allowed. Sending a shortcut is not proof that a picker opened. Where possible, the adapter locates accessibility candidates and performs their native actions; it can fall back to a candidate's position or standard keyboard events. Effort controls are handled according to their exposed control type.

## DeepSeek Harness

A separate application identity and control lookup reuse the reading, editing, conversation, and model workflow. The local client inspected for this implementation is `0.2.0-rc.2`, bundle identifier `com.deepseek.dsh`.

`⌘K` focuses “Search conversation name.” Model entry performs the accessibility action on a positively identified “Select model, current …” button, opening “Model and reasoning effort.” The adapter does not assume Codex's model shortcut or insert a guessed command into the draft. These UI entry points were inspected locally; the full physical-controller workflow still needs validation and should be retested after app updates.

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
