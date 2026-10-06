# Supported-app icons

These PNGs are the icons of the applications VibeWand works with, shown in both READMEs and on the project site (`site/img/apps/` holds WebP conversions) to say which apps are supported. They are not VibeWand artwork: each icon and name belongs to its owner, is not covered by this repository's license, and is not copied into the application bundle.

Each file is the icon macOS shows in Finder for the app installed on the development Mac, rendered at 256 px through `NSWorkspace.shared.icon(forFile:)` on 2026-10-06 and scaled to 128 px with `sips`. Nothing was redrawn or retouched.

| File | Application | Version on that Mac |
| --- | --- | --- |
| `codex.png` | Codex desktop (`com.openai.codex`, installed as ChatGPT.app) | 26.930.31730 |
| `claude.png` | Claude desktop | 2.19675.0 |
| `deepseek-harness.png` | DeepSeek Harness | 0.2.0-rc.2 |
| `workbuddy.png` | WorkBuddy | 5.6.2 |
| `iterm2.png` | iTerm2 | 3.7.3 |
| `safari.png` | Safari | 27.0 |
| `chrome.png` | Google Chrome | 154.0.8037.98 |
| `wechat.png` | WeChat | 4.1.15 |
| `feishu.png` | Feishu (Lark.app, `com.electron.lark`) | 147.0.7727.149 |

Edge, Brave, Firefox, Opera and Vivaldi are supported too but were not installed on that Mac, so they are named in text and have no icon here.
