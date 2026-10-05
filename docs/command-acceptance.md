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

## Second round, for 0.8.5 / 第二轮：0.8.5

Later the same day the model became the user's to choose, permission modes were added, and the overlay and settings began to show what the agent is doing. The kernel's model adapter changed with that, from the harness's DeepSeek-only component to its multi-provider one (`dsh-llm-pi-ai` 0.2.0-rc.2), so the first round's scenarios were partly run again. The model was DeepSeek's `deepseek-flash` over its OpenAI-compatible protocol unless noted.

同一天晚些时候，模型改为由用户选择，加入了权限档位，悬浮窗和设置页开始显示 agent 在做什么。内核的模型适配随之从 Harness 的 DeepSeek 专用组件换成多服务组件（`dsh-llm-pi-ai` 0.2.0-rc.2），所以第一轮的场景复测了一部分。除另有说明外，模型是 DeepSeek 的 `deepseek-flash`，走它的 OpenAI 兼容接口。

| Mode and what was said / 档位与说的话 | What happened / 经过 | Read back / 读回的结果 |
| --- | --- | --- |
| Ask every time: 输入 asked first / 每步确认 | Asked “输入「asked first」？”, confirmed, `ui_type` / 先问，确认后输入 | The words are in the document. The overlay's line read `deepseek-flash · 上下文 4.3k/262.1k · 1% · 5 步` / 文档里有这句话；悬浮窗最下一行如左 |
| Ask every time: 输入 never typed | Asked, declined / 先问，拒绝 | The document is unchanged / 文档不变 |
| Ask every time: 打开计算器, 切回文本编辑 | Asked “切换到 Calculator？” and “切换到 TextEdit？”, both confirmed / 各问一次，都确认 | Calculator in front, then the document again. The second reply mentioned the typing that had been declined: the conversation carried over / 计算器到前台，再回到文档；第二句的回答提到了之前被拒绝的输入，说明对话延续 |
| Bypass all: 按一下回车键 / 跳过全部确认 | `ui_key`, no question / 没有提问 | One more line / 多一行 |
| Ask when risky: the six TextEdit instructions of round one / 只确认有风险的：第一轮文本编辑的六句话 | As in round one; Return asked about, navigation and typing not / 与第一轮相同：回车先问，导航和输入不问 | All read back; 24 s in total, 20 s with thinking turned off (one run each) / 全部读回；共 24 秒，关闭思考后 20 秒（各一次） |
| VS Code: the two tab instructions / 两句标签页 | `ui_snapshot` → `ui_press` | The window's title is the file named / 窗口标题变为所说的文件 |
| Codex: open a chat by title, then the Back button / 按标题打开会话，再按后退按钮 | `find_sessions` → `open_session`; `ui_snapshot` → `ui_press` | The named chat is shown, then the earlier one again / 显示指定会话，再回到原先的会话 |
| Keyboard: right ⌘, ↓, Return / 键盘 | scripted, no model / 脚本内核 | As in round one / 与第一轮相同 |

The kernel alone, with a stand-in for the desktop (`KernelLiveTests`): an instruction and a correction in one conversation; the same service over its Anthropic-compatible protocol with thinking off and a context length of 64000, where no thinking arrived and the kernel reported its context out of 64000; a wrong key, reported with the service's 401 and its own message; and a stop that interrupts a turn waiting on a tool.

单独的内核、假的桌面宿主（`KernelLiveTests`）：同一段对话里的一条命令和一次纠正；同一服务的 Anthropic 兼容接口，关闭思考、上下文长度设为 64000，结果没有思考内容到达，内核按 64000 报告上下文；错误的密钥，报出的是服务的 401 和它的原话；以及在等待工具时被停止打断的一轮。

The settings page and the records window were looked at as images rendered from hidden views in the test process, in Chinese and English; the overlay's command states likewise. Nobody has looked at them in the running app for this record.

设置页和记录窗口是在测试进程里用隐藏的视图渲染成图片后看的，中英文各一份；悬浮窗的各个命令状态也是这样。这份记录里没有人在运行中的应用里看过它们。

Not run again in this round: the Codex choice among several chats, the `⌘K` fallback, and the Claude and Feishu searches. Their tools are unchanged apart from where the confirmation is asked.

这一轮没有复测：Codex 里几个会话都像时的提问、`⌘K` 回退，以及 Claude 和飞书的搜索。除了“在哪里询问确认”之外，它们用到的工具没有改动。

## Third round, for 0.9.0: plugin mode / 第三轮：0.9.0 的插件模式

On 2026-10-06 the coordinator was given a second way to run: as a plugin of a DeepSeek Harness the user installed, instead of the kernel VibeWand ships. The harness was the one installed on the test Mac, **DeepSeek Harness desktop 0.2.0-rc.2**, started through the `dsh` command its app carries. Every run used a harness home of the test's own, never `~/.dsh`; its “desktop” profile held one model row of the kind the harness's apps write, reaching DeepSeek's `deepseek-flash`.

2026-10-06，协调器多了一种运行方式：作为用户已安装的 DeepSeek Harness 的插件，而不是 VibeWand 自带的内核。Harness 是测试机上装的 **DeepSeek Harness 桌面版 0.2.0-rc.2**，经它应用内自带的 `dsh` 命令启动。每次运行用的都是测试自己的 Harness 目录，从不使用 `~/.dsh`；其中的“desktop”配置里有一行模型服务，写法与 Harness 自己的应用相同，指向 DeepSeek 的 `deepseek-flash`。

| What was run / 跑了什么 | Result / 结果 |
| --- | --- |
| 输入 hello from the harness (TextEdit) | `ui_type`; the words are in the document. The overlay's line read `deepseek-flash · 上下文 2.5k/262.1k · 0% · 2 步` / 文档里有这句话；悬浮窗最下一行如左 |
| 打开计算器, 切回文本编辑 | `activate_app`; Calculator in front, then the document again / 计算器到前台，再回到文档 |
| Where the conversation went / 对话去了哪里 | One conversation for the three commands, in the harness's own session store under the folder named `VibeWand`, with a row in its session index / 三条命令是一段对话，存在 Harness 自己的会话库里名为 `VibeWand` 的目录下，并写入了它的会话索引 |
| The harness's standard web interface on the same home / 同一目录上的 Harness 标准网页界面 | A conversation made this way is listed under Ungrouped, titled with the command; opened, it shows the messages, usage, context percentage and the Trajectory view with the system prompt and each turn / 这样产生的对话列在“未分组”下，标题是命令原话；打开后有消息、用量、上下文百分比，以及含系统提示词和每一轮的 Trajectory 视图 |
| The app's own start path, with no key / 应用自己的启动路径（不带密钥） | The harness was asked its version, the profile was written, the bundle loaded and a conversation opened; the harness listed the profile's route beside its own DeepSeek route, then reported the missing key in its own words / 询问了 Harness 的版本、写入了配置、加载了 bundle 并打开了对话；Harness 列出了配置里的模型服务和它自带的 DeepSeek，随后用它自己的话报告缺少密钥 |
| A bundle declaring another harness version / 声明了别的版本的 bundle | Not loaded; the harness's log names the plugin, both versions and the exemption it would take / 没有被加载；Harness 的日志写明了插件、双方版本和所需的例外 |
| The model settings of the harness installed on the test Mac, copied to a test home / 测试机上那份 Harness 的模型配置，复制到测试目录 | Composed without a validation error; the harness listed the models of all four services in it and the profile's default model was among them. No model was called with the keys of that harness / 组合时没有校验错误；Harness 列出了其中四个模型服务的全部模型，配置里的默认模型也在其中。没有用那份 Harness 的密钥调用过模型 |

Two other changes went in with it, so the earlier scenarios were run again on the built-in kernel: the turn's message now leads with the command (a harness titles a conversation from its first words), and the default permission is “ask when risky” again. TextEdit's six instructions, the permission modes, the VS Code tabs, the Codex chat and Back button, the keyboard key and the model check all passed as before; typing a short text took two to four tool calls.

同时还有两处改动，所以前面的场景在内置内核上又跑了一遍：每一轮的消息改为以命令开头（Harness 用开头的字给对话起标题），默认权限改回“只确认有风险的”。文本编辑的六句话、权限档位、VS Code 标签页、Codex 会话与后退按钮、键盘命令键和模型检查都和之前一样通过；输入一小段文字用了两到四次工具调用。

Not run in this round: plugin mode on a real `~/.dsh`; a model service signed in to with OAuth or a DeepSeek account; the desktop app's own window, as opposed to the web interface it shares; a `dsh` installed for the terminal; the exemption for an unverified version, whose file was compared with the one the harness's own `allow-version` command writes but not exercised on a second harness version; the Claude and Feishu searches.

这一轮没有测：在真实的 `~/.dsh` 上运行插件模式；经 OAuth 或 DeepSeek 账号登录的模型服务；桌面版自己的窗口（看的是与它共用界面的网页版）；终端安装的 `dsh`；未验证版本的例外（文件内容与 Harness 自己的 `allow-version` 命令写出的一致，但没有在第二个 Harness 版本上实际用过）；Claude 和飞书的搜索。

## Fourth round, unreleased: one coordinator, pictures, a harness's tools, the keyboard / 第四轮（未发布）：一个协调器、截图、Harness 的工具、键盘

On 2026-10-06, after 0.9.0, the two kernels were put on one coordinator bundle and one code path, and four things were added: conversations that outlive the kernel process, a picture of the window the model may ask for, the harness's own tools in plugin mode, and the keyboard as a device. None of it is released. The runs used the working tree, the kernel assembled from it, DeepSeek's `deepseek-flash`, and for plugin mode the same **DeepSeek Harness desktop 0.2.0-rc.2** as round three, again with a harness home of the test's own.

2026-10-06，在 0.9.0 之后，两种内核改为共用一个协调器 bundle 和一条代码路径，并新增四项：比内核进程活得久的对话、模型可以要的窗口截图、插件模式下 Harness 自己的工具，以及把键盘当设备。这些都还没有发布。运行用的是工作区的代码和由它组装的内核，模型是 DeepSeek 的 `deepseek-flash`；插件模式用的仍是第三轮那份 **DeepSeek Harness 桌面版 0.2.0-rc.2**，同样在测试自己的 Harness 目录里。

In real windows the test opened (`CommandLiveTests`) / 在测试自己打开的真实窗口里：

| What was run / 跑了什么 | Result / 结果 |
| --- | --- |
| `textedit`, on the built-in kernel / 内置内核 | The six instructions of round one, as before / 第一轮的六句话，与之前相同 |
| `plugin`, on the installed harness / 安装的 Harness | Typing and switching apps, as in round three, now through the same start path as the built-in kernel / 输入与切换应用，与第三轮相同，现在与内置内核走同一条启动路径 |
| `resume`: 输入 wand-alpha-7, the kernel process let go, then “把我上一条让你输入的那个词，原样再输入一遍” | The second command ran in the same conversation, as its second command, and the word is in the document twice / 第二条命令在同一段对话里、作为它的第二条执行，这个词在文档里出现了两次 |
| `sight`: a document saying “the wand sees ZQ47 here”, “看一眼这个窗口，文档里写的那个四位编号是什么？” | `ui_screenshot` was called and the answer named ZQ47. The picture kept with the record is 1346×878 and shows that one window / 调用了 `ui_screenshot`，回答里是 ZQ47。随记录保存的那张图是 1346×878，只有这一个窗口 |
| `plugin-sight`: the same document and question on the installed harness / 同一份文档和问题，在安装的 Harness 上 | `ui_screenshot` was called and the answer quoted the line with ZQ47. The picture, 1346×878, is an object in the harness home's attachment store. With the harness's web interface started on a copy of that home, the conversation is listed under Ungrouped with its title, and in its Trajectory view the Result of the `ui_screenshot` step shows the picture; the Chat view shows that step's attachment record / 调用了 `ui_screenshot`，回答引用了含 ZQ47 的那一行。这张 1346×878 的图是 Harness 目录的附件库里的一个对象。在这份目录的副本上启动 Harness 网页界面：对话带着标题列在“未分组”下，Trajectory 视图里 `ui_screenshot` 那一步的 Result 显示了这张图；Chat 视图显示的是这一步的附件记录 |
| `plugin-tools`: “用 bash 工具运行 echo wand-$((40+2))，然后把它输出的那个词输入到这个文档里” | `bash`, then `ui_type`; “wand-42” is in the document. The context after it was 11.6k, against 2.4k for a comparable command with VibeWand's tools only / 先 `bash` 再 `ui_type`，文档里有“wand-42”。之后的上下文是 11.6k，只带 VibeWand 工具的同类命令是 2.4k |
| `keyboard-layout`, scripted, no model / 脚本内核，不用模型 | With ⌃K as the dictation combination: held, dictation started and the replayed words arrived in the document, and the line ⌃K would have cut is intact; a plain digit reached the document; ⌃⌘→ pressed while right ⌘ was held as the command key turned once and ended the listening / 把 ⌃K 设为听写组合键：按住后听写开始，回放的文字进了文档，而 ⌃K 本来会剪掉的那一行还在；普通的数字键进了文档；按住右 ⌘（命令键）时按 ⌃⌘→，转了一格并结束了听取 |
| `keyboard`, `probe`, `plugin-start` | As before / 与之前相同 |

The kernel alone, with a stand-in for the desktop (`KernelLiveTests`) / 单独的内核、替身桌面：

| What was run / 跑了什么 | Result / 结果 |
| --- | --- |
| A conversation taken up by a later process / 后来的进程接上同一段对话 | On the shipped harness the session was resumed and the others in its store were removed; on the installed one it was resumed and nothing else in the store was touched / 自带的那份接上了会话，并清掉了会话库里其余的；安装的那份接上了会话，库里别的没有动 |
| A picture a tool shows reaches the model, on the shipped harness / 工具给出的图片到达模型（自带的那份） | Shown a plain green picture and asked its colour, the model answered green / 给它一张纯绿色的图并问颜色，模型答的是绿色 |
| The whole harness, on the installed one, permission “ask when risky” / 全部工具（安装的那份），“只确认有风险的” | A command writing outside the working folder was put to the user through VibeWand's gateway: declined, the file was not written; allowed, it was / 一条要写到工作目录之外的命令经 VibeWand 的网关问用户：拒绝后文件没有写出，同意后写出了 |
| The title the harness lists a conversation under / Harness 给对话的标题 | “VibeWand · ” followed by the command; a long Chinese command is cut cleanly at 84 bytes / “VibeWand · ”加命令原话；很长的中文命令在 84 字节处整字截断 |
| A bundle declaring another harness version / 声明了别的版本的 bundle | Refused, as in round three / 与第三轮一样被拒绝 |

What was learnt about the harness's own apps, on the test's home with its standard web interface / 在测试目录上用 Harness 的标准网页界面观察到的：a running harness lists a conversation another process wrote only after its page is reloaded, and shows it as Untitled until it is opened; a conversation opened there is held by that harness, and VibeWand's attempt to resume it is refused, after which the next command starts a new one. / 运行中的 Harness 要刷新页面才会列出别的进程写入的对话，点开之前显示为“未命名”；在那里点开过的对话被那份 Harness 占住，VibeWand 再去接会被拒绝，下一条命令于是开始新对话。

The first-run guide (seven steps, Chinese and English, light and dark, with a device and with the keyboard), the overlay for all four layouts, the command settings page in both kernel modes and a marked picture were looked at as images rendered from hidden views in the test process. Liquid Glass does not draw off screen, so these show layout and wording only.

首次引导（七步，中英文、浅色深色、有设备和用键盘各一份）、四种布局的悬浮面板、两种内核下的命令模式设置页，以及一张带编号的截图，都是在测试进程里用隐藏的视图渲染成图片后看的。离屏渲染画不出 Liquid Glass，这些图只能看排版和文字。

Not run in this round: the guide, the keyboard layout and the new settings in the running app; a physical keyboard, and whether actions sent while its modifiers are physically held behave the same in every app; granting Screen Recording to the app bundle (the test process used a permission it already had); a model other than DeepSeek's looking at a picture; “View conversations in the browser” from the button to the page (the web app was only checked to start on a scratch home and report its address); the desktop app's own window after it is reopened; the harness's question on the real overlay rather than through the gateway; plugin mode on a real `~/.dsh`; the VS Code, Codex, Claude and Feishu scenarios, whose tools did not change.

这一轮没有测：运行中的应用里的引导、键盘布局和新设置；实体键盘，以及按住它的修饰键时 VibeWand 发出的动作在各个应用里是否都一样；给应用包授权屏幕录制（测试进程用的是它已有的权限）；DeepSeek 以外的模型看图；“在浏览器里查看对话”从按钮到页面的全过程（只核对过网页版能在临时目录上启动并报出地址）；桌面版重开后它自己的窗口；Harness 的询问出现在真实悬浮窗上的样子（核对的是经网关的那一段）；在真实的 `~/.dsh` 上运行插件模式；VS Code、Codex、Claude 和飞书的场景，它们用到的工具没有改动。

## Fifth round, unreleased: a menu that opens, any key of a keyboard, SenseVoice / 第五轮（未发布）：弹出的菜单、键盘上的任意键、SenseVoice

On 2026-10-06 the owner tried the development build and reported that in Codex a spoken command to change the model or its effort could not be carried out. The task records of those attempts show why. Codex's model button (in the app now named ChatGPT, **26.930.31730**) opens a popover whose four controls sit at the very end of a window of some 340, and a snapshot printed the first 150. The effort is no list of options: it is one row, “Power”, set with the left and right arrows, and where it stands is only announced, as “GPT-6 Astra Extra High, 4 of 5.”, in text a snapshot did not read. While the popover is open the button is named “Select effort”, so looking for it by its earlier name found nothing. The model pressed the right button each time, read the same list again, and gave up.

2026-10-06，作者试用开发版后反馈：在 Codex 里用说的命令换模型或强度，做不成。那几次的任务记录给出了原因。Codex 的模型按钮（应用现在叫 ChatGPT，**26.930.31730**）点开的是一个弹层，里面四个控件排在窗口三百四十来个控件的最末尾，而快照只打印前 150 个。强度不是一组选项，而是叫“Power”的一行，用左右方向键调，停在哪一档只以播报的形式给出（“GPT-6 Astra Extra High, 4 of 5.”），快照不读这种文字。弹层开着的时候按钮自己改名叫“Select effort”，按原来的名字找它就找不到。模型每次都按对了按钮，又读到同一份清单，于是放弃。

What changed: a snapshot leads with what is new or changed since the one before it; it reads what the app announces as a status line and the keys a control says it is worked with; the control the app's adapter presses for the dial is marked as the model picker; `ui_key` can be sent to one control, one press for each call, and answers with what the app then announced; and labels that hand out access wait for the user like those that send or destroy.

改动：快照把上一次之后新出现或变了的排在最前；读应用播报的状态行和控件自己声明的操作按键；适配里旋钮要按的那个控件被标成模型选择器；`ui_key` 可以发给指定的控件，一次一下，返回里带上应用随后播报的内容；交出权限的按钮和发送、删除的一样，先问用户。

In the real Codex window, which is the owner's own, after keyboard and mouse had been idle (`CommandLiveTests`, scenario `codex-model`, `deepseek-flash`, built-in kernel). The test read the model and the effort from the popover first and put both back at the end / 在真实的 Codex 窗口里（作者自己的那个窗口），等键盘和鼠标空闲后进行；测试先从弹层里读出模型和强度，结束时都还原：

| What was said / 说了什么 | Tools / 工具 | Result read back from the button / 从按钮读回的结果 |
| --- | --- | --- |
| 强度调到 low。 | `ui_snapshot` (filter “model”) → `ui_press` → `ui_snapshot` → `ui_key` ← ×3, answered “Extended, 3 of 5”, “Standard, 2 of 5”, “Light, 1 of 5” → `ui_key` escape → `ui_snapshot` → `finish`: 9 calls, 10 in a later run that began with `list_targets` / 9 次调用，后来一次多了开头的 `list_targets`，是 10 次 | “GPT-6 Astra Extra High” became “GPT-6 Astra Light”. Codex has no level called low; the model took the lowest and said so / 变成“GPT-6 Astra Light”。Codex 没有叫 low 的档位，模型取了最低一档并在结果里说明 |
| 把模型换成 GPT-6.1 Sol。 | Button, “Select model”, the list, the model, escape: 10 or 11 calls / 按钮、“Select model”、列表、选中、关闭：10 或 11 次调用 | “GPT-6.1 Sol Light” |
| 把模型换回 GPT-6 Astra，强度调回去，让按钮显示 GPT-6 Astra Extra High。 | 13 calls, three presses of → among them / 13 次调用，其中三下 → | “GPT-6 Astra Extra High”, as before the test / 与测试前相同 |

Runs of the same scenario while the change was being made / 改动过程中同一个场景的几次运行：

- The first run that passed took 24 calls for the effort alone, which is the step limit: nothing told the model where an assistant app keeps its effort, and it opened the mode switcher and the profile menu before the model button. The prompt now says where, and the snapshot marks the model picker. / 第一次通过时，光是调强度就用了 24 次调用，正好是步数上限：没有任何东西告诉模型这类应用把强度放在哪，它先去点了模式切换和个人菜单。现在提示词里写了，快照也把模型选择器标了出来。
- With a repeat count on `ui_key`, the model pressed → four times from “1 of 5” for a level it wrongly took to be the fifth, and reached Codex's top level, which brought up a dialog with “Use Full access”, “Continue” and “Close dialog”. It pressed “Close dialog”; the permission control beside the composer looked the same before and after. The repeat count was removed, so that each press is answered with the level before the next, and “full access”, “allow”, “grant”, “authorize” and “approve” were added to the labels that wait for the user. / `ui_key` 带重复次数时，模型从“1 of 5”连按了四下 →，它误以为目标是第五档，于是到了 Codex 的最高一档，弹出了一个有“Use Full access”“Continue”“Close dialog”的对话框。它按了“Close dialog”；输入框旁的权限控件前后看起来一样。重复次数已去掉，每按一下先读回档位再按下一下；“full access”、允许、授权、批准、同意也加进了必须先问用户的名单。
- One run stopped at its first press because another app had come to the front; nothing had been changed. / 有一次在第一下按键时停了，因为别的应用到了前台；什么都没改。

`textedit`, run again because every interface tool's answer changed / 因为界面工具的返回都变了，重跑了 `textedit`：the six instructions of round one passed. Of the first four runs, one ended three instructions in words without calling `finish`, so the overlay showed the model's last words as needing attention although the work was done; once a model does that in a conversation it tends to go on doing it. The prompt's last rule now says that a reply in words ends nothing and that the user is shown only what `finish` or `need_user` carries; four further runs ended every instruction with `finish`, and so did `codex-model` run after that. / 第一轮的六句话通过。头四次运行里有一次，三句话都是用一句话收尾而没有调用 `finish`，事情做完了，悬浮窗却把模型最后那句话当成需要注意显示出来；模型在一段对话里这样做过一次，后面往往接着这样做。提示词最后一条现在写明：用话回答不算结束，用户只看得到 `finish` 或 `need_user` 带的那一句。之后四次运行每一句都以 `finish` 结束，随后重跑的 `codex-model` 也是。

The keyboard, in a TextEdit window the test opened (`keyboard-layout`, scripted, no model) / 键盘，在测试自己打开的文本编辑窗口里（脚本内核，不用模型）：the number pad's 5, with no modifier, went into the document as usual; with a recording under way the next press of it was handed to the recorder and reached nothing else; set as a control's combination, it then stood for that control and did not reach the document. The earlier steps of the scenario passed as before. / 数字小键盘的 5，不带修饰键，先照常进了文档；开始录制后，再按它的那一下交给了录制，没有传给别处；设成一个键位的组合键以后，它代表这个键位，不再进文档。这个场景原有的几步与之前一样通过。

SenseVoice was run on recordings, not on a microphone: see [Voice input](voice-input.md#下一版尚未发布本机-sensevoice--sensevoice-on-this-mac). / SenseVoice 用录音文件跑过，没有用麦克风，见[语音输入](voice-input.md#下一版尚未发布本机-sensevoice--sensevoice-on-this-mac)。

Not run in this round: the model and effort controls of Claude, DeepSeek Harness and WorkBuddy by a spoken command; Codex while a turn is running; the “Use Full access” question on the real overlay (the labels are covered by a unit test); a physical keyboard, a custom keyboard with extra keys, and the recorder in the running app; dictation through SenseVoice with a microphone; the earlier scenarios other than `textedit` and `keyboard-layout` (`code`, `codex`, the searches and the plugin-mode ones), whose tools changed in what a snapshot lists and how a key is sent but were not run again.

这一轮没有测：用说的命令去调 Claude、DeepSeek Harness 和 WorkBuddy 的模型与强度；Codex 正在执行一轮任务时的情况；“Use Full access”在真实悬浮窗上的那一问（名单由单元测试覆盖）；实体键盘、带扩展键的自定义键盘，以及运行中的应用里的录制界面；用麦克风经 SenseVoice 听写；`textedit` 和 `keyboard-layout` 以外的原有场景（`code`、`codex`、几个搜索和插件模式的那些），它们用到的工具在“快照列什么”和“按键怎么发”上有改动，但没有重跑。

## Not run / 没有测的

- A microphone and a human voice: transcripts were replayed. / 麦克风和真人语音：用的是转录回放。
- Physical keys and buttons. The keyboard key was a synthetic event, and a key that another program takes first has to be pressed by hand. / 实体按键。键盘命令键用的是合成事件；被其他程序先取走的键只能用手按来验证。
- The app bundle's own overlay and settings window while a command runs. / 应用包自己的悬浮面板和设置窗口在命令执行时的表现。
- DeepSeek Harness, WorkBuddy and WeChat as search targets: they were not running. / 以 DeepSeek Harness、WorkBuddy、微信为目标的搜索：当时没有运行。
- Any model service other than DeepSeek, and any local model. For the other built-in services only the address was checked to exist; no key for them was at hand and no local server was running. / DeepSeek 以外的任何模型服务，以及本机模型。其余内置服务只核对了地址存在；手头没有它们的密钥，本机也没有模型服务在运行。
- The buttons of the settings page. What is behind them was run: listing DeepSeek's models (also with a wrong key, and at an address where nothing listens), and the model check behind “Save and test”, which answered in 2.5 s and reported a context of 262.1k. The buttons themselves were not pressed. / 设置页上的按钮。按钮背后的功能跑过：拉取 DeepSeek 的模型列表（也试了错误的密钥和一个没有服务的地址），以及“保存并测试”背后的模型检查，它在 2.5 秒内得到回答并报告上下文为 262.1k。按钮本身没有按过。
- Keys, menus and typing in VS Code. / VS Code 里的按键、菜单和输入文字。
