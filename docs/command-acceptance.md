# Command mode acceptance / 命令模式验收

[Command mode / 命令模式](command-mode.md) · [Computer use](computer-use.md) · [Development / 开发](development.md)

On 2026-10-05, command mode in the current source was run against real apps on an Apple Silicon Mac with **macOS 27.0 beta, build 26A5378j**: Codex desktop **26.930.31730** (its CLI 0.160.0), Visual Studio Code **1.140.0**, Claude desktop **2.19675.0**, Feishu (build 7727.149), TextEdit **1.21** and Calculator. The kernel was the assembled DeepSeek Harness **0.2.0-rc.2** on Node.js 24.21.0 with the default model. The Doubao input method **1.0.1** was installed.

2026-10-05，在 Apple Silicon Mac、**macOS 27.0 beta（26A5378j）**上，用当前源码的命令模式对真实应用做了验收：Codex 桌面版 **26.930.31730**（自带 CLI 0.160.0）、Visual Studio Code **1.140.0**、Claude 桌面版 **2.19675.0**、飞书（构建 7727.149）、文本编辑 **1.21** 和计算器。内核是组装出的 DeepSeek Harness **0.2.0-rc.2**（Node.js 24.21.0）与默认模型。本机装有豆包输入法 **1.0.1**。

The test (`CommandLiveTests`, opt-in) runs the production runtime, controller and tools with the real kernel and model. Spoken words are replayed as transcripts; nothing is recorded. Each scenario opens a window of its own, waits until keyboard and mouse have been idle for a few seconds, speaks from that window, and reads the result back from the target app: a title, a selection, which app is in front. A tool that merely returned success is not a pass. Results were also looked at on screen. Whatever the test opened it closed, and Codex was returned to the chat it had been showing.

测试（`CommandLiveTests`，需显式开启）用的是生产运行时、控制器和工具，加上真实的内核与模型。说的话以转录回放，不录音。每个场景自己开一个窗口，等键盘和鼠标空闲几秒，从这个窗口“说话”，再从目标应用读回结果：标题、选区、谁在前台。工具只是返回成功不算通过。结果同时在屏幕上看过。测试打开的东西由它自己关掉，Codex 回到了原先显示的会话。

| Said / 说的话 | Tools the model used / 模型用的工具 | Read back / 读回的结果 |
| --- | --- | --- |
| 输入 hello from vibewand（TextEdit） | `ui_type` | The words are in the document / 文档里有这句话 |
| 按一下回车键 | `ui_key`, after asking / 先询问 | Confirmed: one more line / 确认后多一行 |
| 再按一次回车键 | `ui_key`, after asking / 先询问 | Refused: the document is unchanged / 拒绝后文档不变 |
| 用菜单把全部文字选中 | `ui_menu` | The selection covers the whole text / 选区覆盖全文 |
| 打开计算器 | `activate_app` | Calculator is in front; the spoken name was Chinese, the app is `Calculator` / 计算器在前台 |
| 切回文本编辑 | `activate_app` | The document is in front again / 文档回到前台 |
| 打开 wand beta 那个标签页（VS Code） | `ui_snapshot` → `ui_press` | The window's title is that file / 窗口标题变为该文件 |
| 不是这个，换成 gamma 那个 | `ui_snapshot` → `ui_press` | The same, for the other tab; the correction used the earlier turn / 同上，纠正沿用了上一句 |
| 切到 Codex 里「…」那个会话 | `find_sessions` → `open_session` | The window's title strip shows the named chat / 窗口顶部显示的是这个会话 |
| 点一下窗口左上角的后退按钮（Codex） | `ui_snapshot` → `ui_press` | The earlier chat is shown again / 回到原先的会话 |
| 切到 Codex 里关于 VibeWand 的那个会话 | `find_sessions` → `choose` → `open_session` | The question came up with the candidates and the answer went on to `open_session`; where it landed was not read in this run / 出现了候选提问，作答后继续执行 `open_session`；这一次没有读回落点 |
| 在 Codex 里搜一下 zzqx | `find_sessions` (no match) → `search_in_app` | `⌘K` is open with the word in it; turning selects, back closes it / `⌘K` 已打开并有这个词，转动可选，返回键关闭 |
| 在 Claude 里搜一下 vibewand | `search_in_app` | The same / 同上 |
| 在飞书里搜一下 vibewand | `search_in_app` | The same, in Feishu's search window / 同上，在飞书的搜索窗口里 |
| Right ⌘ held alone, then ↓ and Return / 单独按住右 ⌘，再按 ↓ 和回车 | scripted, no model / 脚本内核 | Listening starts; the arrow moves the selection; Return answers; none of the keys reach the document / 开始听取，方向键移动候选，回车作答，按键没有进入文档 |

An instruction took about three to six seconds from release to result. In the VS Code window the test's gateway offered the model only reading and pressing; keys, menus and typing were not sent to an editor by a test.

一句话从松开到出结果约三到六秒。在 VS Code 的窗口里，测试的网关只给模型“读”和“按”两类工具；测试不向编辑器发送按键、菜单和文字。

## What the run found / 发现的问题

All of these are fixed in the source.

以下问题均已在源码中修复。

- **Right ⌥ never arrived.** The Doubao input method uses a held right ⌥ for voice and takes the key-down before any other listener sees it; holding the key brought up Doubao's voice bar, and VibeWand heard nothing. Right ⌘, ⌃ and ⇧ pass through. The keyboard's default command key is now right ⌘, and Settings says what to do when a key does nothing. / **右 ⌥ 收不到。**豆包输入法用按住右 ⌥ 做语音键，按下事件在其他监听者之前就被它取走：按住时出现的是豆包的语音条，VibeWand 什么也没收到。右 ⌘、⌃、⇧ 可以通过。键盘的默认命令键改为右 ⌘，设置里写明了按住没反应时该怎么办。
- **Keywords reported as typed that were not.** Feishu's search ignores a paste that comes along the keyboard's path and takes one addressed to the app; the search stayed empty while the overlay said the words were in. Typing is now checked by the field's character count and caret, never by its contents; a paste that changes nothing is sent again addressed to the app, and if that fails too the user is told to type. `ui_type` has the same check. / **没填进去的关键词被报告为已填。**飞书的搜索不接受沿键盘路径来的粘贴，只接受发给应用的；搜索框是空的，浮层却说已经填好。现在用输入框的字数和光标位置核对（不读内容）：粘贴后没有变化就改为发给应用再试一次，仍然失败则告诉用户自己输入。`ui_type` 用同样的核对。
- **An app arriving from another Space missed its shortcut.** It is frontmost about 0.4 s before its window is on the Space in front; a shortcut sent in between was lost, or its search opened unrecognised. Tools that bring an app forward now wait for the window. / **从另一个桌面空间切来的应用收不到快捷键。**它成为前台应用比窗口到位早约 0.4 秒，这期间发出的快捷键会丢失，或搜索打开了却没被认出。把应用带到前台的工具现在等窗口到位。
- **Detours.** The model re-activated the app the user was already in, and for Codex it rebuilt the search out of interface tools because the tool's description reserved `search_in_app` for apps without a list. The prompt and descriptions now say what is already in front and when the app's own search is the route. Typing a short text went from six tool calls to three. / **绕路。**模型会把用户已经在用的应用再切一次；对 Codex，它用界面工具自己拼搜索，因为工具说明把 `search_in_app` 限定给了没有列表的应用。提示词和说明现在写清了什么已经在前台、何时该用应用自带的搜索。输入一小段文字从六次工具调用降到三次。
- **Leftover search words.** A search that still held the previous words got the new ones appended. They are now replaced. / **残留的搜索词。**搜索框里留着上次的词时，新词会接在后面。现在是替换。

## Seen and left as it is / 观察到但没有改的

- **Codex's list holds this Mac's chats only.** A chat that lives on a remote machine is in Codex's window but not in the list Codex's own interface returns. When nothing matches, the model is told to use Codex's `⌘K` search, which covers them. / **Codex 的列表只有本机的会话。**在远程机器上运行的会话出现在 Codex 窗口里，但不在它接口返回的列表中。没有匹配时，模型会被告知改用 Codex 的 `⌘K` 搜索，那里搜得到。
- **VS Code takes the reading for a screen reader.** Asking an Electron app for its controls turns on its accessibility tree. VS Code then offers “screen reader optimized” mode and shows it in the status bar. Answer No, or set `editor.accessibilitySupport` to `off`; the tabs are expected to stay readable, which was not checked with the setting off. / **VS Code 把读取当成屏幕阅读器。**向 Electron 应用要控件会打开它的辅助功能树，VS Code 随即询问是否启用“为屏幕阅读器优化”，并在状态栏显示。选“否”，或把 `editor.accessibilitySupport` 设为 `off`；预计标签页仍然读得到，但关闭后的情况没有验证。
- **Opening a Codex chat is still reported as unchecked.** The app does not read back where the link landed, so the overlay adds “result not verified”. The test read the window's title strip, and in each of its runs the link had landed on the named chat. / **打开 Codex 会话仍然标为未核对。**应用不读回链接落在哪里，所以浮层会加一句“结果未能核对”。测试读了窗口顶部的标题，每次运行链接都落在指定的会话上。

## Not run / 没有测的

- A microphone and a human voice: transcripts were replayed. / 麦克风和真人语音：用的是转录回放。
- Physical keys and buttons. The keyboard key was a synthetic event, and a key that another program takes first has to be pressed by hand. / 实体按键。键盘命令键用的是合成事件；被其他程序先取走的键只能用手按来验证。
- The app bundle's own overlay and settings window while a command runs. / 应用包自己的悬浮面板和设置窗口在命令执行时的表现。
- DeepSeek Harness, WorkBuddy and WeChat as search targets: they were not running. / 以 DeepSeek Harness、WorkBuddy、微信为目标的搜索：当时没有运行。
- Keys, menus and typing in VS Code. / VS Code 里的按键、菜单和输入文字。
