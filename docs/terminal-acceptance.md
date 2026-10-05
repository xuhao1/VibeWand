# Terminal acceptance / 终端验收

[Application support / 应用适配](applications.md) · [Development / 开发](development.md)

On 2026-10-05, VibeWand 0.8.4 was tested in the installed iTerm2 **3.7.3** on an Apple Silicon Mac running **macOS 27.0 beta, build 26A5378j**, against Codex CLI **0.160.0**, Claude Code **2.1.289** (classic and fullscreen renderers) and OpenCode **1.18.34**, each the latest release that day. The selected input source was a third-party Chinese input method (Doubao Pinyin).

2026-10-05，在 Apple Silicon Mac、**macOS 27.0 beta（26A5378j）**上，用本机 iTerm2 **3.7.3** 对 Codex CLI **0.160.0**、Claude Code **2.1.289**（经典与全屏两种渲染）、OpenCode **1.18.34** 完成 0.8.4 终端适配验收，三者都是当天的最新版本。系统当前输入法是第三方中文输入法（豆包拼音）。

The test opens an iTerm2 window of its own, waits until keyboard and mouse have been idle for a few seconds, brings that window forward, and feeds the production runtime with button presses and replayed transcripts. After every step it reads the terminal's prompt row back; a key that was merely sent is not a pass. It stops as soon as another window, tab or app takes the keyboard. No message is sent to a model, no chat or model is confirmed, and the clipboard is put back.

测试自己新开一个 iTerm2 窗口，等键盘和鼠标空闲几秒后把它切到前台，再把按键和转录回放交给生产运行时。每一步之后读回终端提示符那一行；只发出按键不算通过。别的窗口、标签页或应用一拿到键盘，测试立即停止。测试不向模型发送消息，不确认任何会话或模型，剪贴板会恢复。

| Check / 项目 | Codex | Claude Code | OpenCode |
| --- | --- | --- | --- |
| Empty prompt recognised / 识别空提示符 | ✓ | ✓ both renderers / 两种渲染 | ✓ start screen and inside a chat / 首页与会话内 |
| Dictation pasted, draft recognised / 听写粘贴并识别为草稿 | ✓ | ✓ | ✓ |
| ESC press deletes one character / ESC 单击删除一个字符 | ✓ | ✓ | ✓ |
| ESC hold keeps deleting / 按住连续删除 | ✓ | ✓ | ✓ |
| Turning moves the cursor / 转动移动光标 | ✓ | ✓ | ✓ |
| Text behind the cursor stays a draft / 光标后的文字仍是草稿 | ✓ | ✓ | ✓ |
| No list opened over a draft / 有草稿时不打开列表 | ✓ | ✓ | ✓ |
| `/resume`: list shown, moved, left with ESC / 列表出现、移动、ESC 离开 | ✓ | ✓ | ✓ (`/sessions`) |
| `/model`: list shown, moved, left with ESC | ✓ and the effort list after it / 以及随后的强度列表 | ✓ | ✓ (`/models`) |
| Turning scrolls the conversation / 转动滚动对话 | ✓ own transcript / 自身对话 | ✓ fullscreen: own transcript; classic: iTerm2 scrollback / 全屏滚自身，经典滚回滚区 | ✓ a short chat moved by one row / 短会话移动了一行 |
| Agent working: delete, then Escape interrupts / 工作中删除，Escape 中断 | ✓ with `!sleep 8` | not run / 未测 | not run / 未测 |
| Controller layout: □ ○ × / 手柄模板 | ✓ | not run / 未测 | not run / 未测 |

The working-agent check needs a task that runs without a model call. Codex has one (`!` runs a local command); Claude Code and OpenCode would need a paid model turn, so it was not run for them. The fix it covers does not depend on the tool.

“工作中”这一项需要一个不调用模型就能运行的任务。Codex 有（`!` 执行本地命令）；Claude Code 和 OpenCode 需要一次付费的模型调用，所以没有测。这一项对应的修复与具体工具无关。

## What the run found / 发现的问题

The adapter that shipped in 0.8.2 and 0.8.3 had been checked against earlier versions in a background terminal only. Run through iTerm2 against the current tools, it had three defects, all fixed in 0.8.4:

0.8.2 和 0.8.3 里的适配只在后台终端里对照旧版本核对过。经 iTerm2 对当前版本实测，发现三处问题，0.8.4 均已修复：

- **Buttons dropped while the agent worked.** Codex and Claude Code animate the window title while they work, Codex about ten times a second. The title was part of the target identity compared between key-down and execution, so with Codex running a command, an ESC hold, an ESC press and OK all had no effect. A terminal's title is no longer part of that identity. / **工具工作时按键全部丢失。** Codex 和 Claude Code 工作时窗口标题在动，Codex 每秒约十次；标题是“按下”和“执行”之间比对的目标身份的一部分，于是 Codex 执行命令时，按住 ESC、单击 ESC 和 OK 都没有任何效果。终端的标题不再属于这个身份。
- **ESC never deleted on a press.** The prompt could not be read, so a press was always Escape and only a hold sent Backspace. The rows next to the cursor are now read: a draft at a recognised prompt is edited like any other composer. / **ESC 单击从不删除。** 当时读不到提示符，单击永远是 Escape，只有按住才退格。现在读取光标旁的几行：认识的提示符里有草稿时，和其他输入框一样编辑。
- **A list was assumed, and the draft was wiped.** After typing a command the adapter took a list to be open for 20 seconds, whatever the tool did, and it cleared the input line with `⌃U` first. A list now counts only while it is on screen, a command is typed only at an empty prompt, and Return follows only when the prompt holds that command alone. / **列表靠假定，草稿被清掉。** 输入命令后不管工具做了什么，都假定列表开着 20 秒；输入前还用 `⌃U` 清空输入行。现在列表只在屏幕上确实出现时才算，命令只在空提示符下输入，提示符只剩这条命令时才回车。

The tools had also changed since that check: Codex and Claude Code's fullscreen renderer now draw on the alternate screen and take the mouse wheel, Claude Code shows an argument hint after a typed command, and OpenCode folds long pastes. The guide describes each.

这几个工具在那之后也变了：Codex 和 Claude Code 的全屏渲染改用备用屏幕并接管鼠标滚轮，Claude Code 在输入的命令后面显示参数提示，OpenCode 会折叠较长的粘贴。使用指南里分别写明了。

## Reproduce / 复现

Run the tool once by hand in a scratch directory to answer its own first-run questions. The test then needs native Accessibility access, permission to script iTerm2, and an explicit opt-in; the normal suite skips it.

先在一个临时目录里手动运行一次工具，回答它自己的首次运行询问。之后测试需要原生辅助功能访问、控制 iTerm2 的自动化许可和显式启用；普通测试会跳过它。

```sh
VIBEWAND_TERMINAL_LIVE='cd ~/vibewand-live && exec codex' \
VIBEWAND_TERMINAL_BUSY='!sleep 8' \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --filter TerminalLiveTests
```

`VIBEWAND_TERMINAL_LIVE` is the command the new window runs: `exec claude` or `exec opencode` for the other tools. Prefix Claude Code with `CLAUDE_CODE_NO_FLICKER=0` or `1` to choose the classic or the fullscreen renderer. `VIBEWAND_TERMINAL_BUSY` is optional and names a draft that makes the agent work without a model. `VIBEWAND_TERMINAL_DEVICE=dualSense` runs the controller layout.

`VIBEWAND_TERMINAL_LIVE` 是新窗口里运行的命令；另外两个工具用 `exec claude` 或 `exec opencode`。Claude Code 前面加 `CLAUDE_CODE_NO_FLICKER=0` 或 `1` 选择经典或全屏渲染。`VIBEWAND_TERMINAL_BUSY` 可选，是一段不调用模型就能让工具工作的草稿。`VIBEWAND_TERMINAL_DEVICE=dualSense` 使用手柄模板。

Source: [TerminalLiveTests.swift](../Tests/VibeKeyBridgeTests/TerminalLiveTests.swift); prompt recognition is covered without a terminal by [TerminalScreenTests.swift](../Tests/VibeKeyBridgeTests/TerminalScreenTests.swift), whose screens are transcribed from these tools.

代码见上述链接；提示符识别另有不需要终端的样例测试，样例屏幕抄录自这几个工具。

Physical device buttons, audio recognition and microphones were outside this run: presses were injected where the runtime receives them, and transcripts were replayed. The screenshot in the applications guide is an actual window capture from this run, taken in a scratch directory.

本轮验收不包含实体设备按键、音频识别和麦克风：按键从运行时接收的位置注入，转录用回放。应用指南里的截图是本轮在临时目录下的实际窗口截图。
