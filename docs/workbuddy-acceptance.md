# WorkBuddy acceptance / WorkBuddy 验收

[Application support / 应用适配](applications.md) · [Development / 开发](development.md)

On 2026-10-05, VibeWand 0.8.1 was tested against the installed WorkBuddy **5.6.2** (`com.tencent.workbuddy.mac`) on an Apple Silicon Mac running **macOS 27.0 beta, build 26A5378j**. The app's English interface was exercised; Chinese metadata has fixture coverage.

2026-10-05，在 Apple Silicon Mac、**macOS 27.0 beta（26A5378j）**上，对本机 WorkBuddy **5.6.2**（`com.tencent.workbuddy.mac`）完成 0.8.1 适配验收。实机使用英文界面，中文元数据由样例测试覆盖。

The test invokes the production adapter and checks the real app's accessibility state after input. A dispatched key alone is not a pass. It does not send a chat message or use speech-provider credentials. User drafts are refused at entry, model selection is restored, test text is removed and clipboard restoration is checked.

测试调用生产适配器，并在输入后读取真实应用的辅助功能状态；仅发送按键不算通过。测试不发送聊天消息、不使用语音服务凭证；开始时拒绝已有草稿，恢复模型选择，清理测试文字并检查剪贴板恢复。

| Check / 项目 | Observed result / 观察结果 |
| --- | --- |
| Search / 搜索 | Sidebar Search opens Global search. The test enters a query, chooses Tasks, observes two task results, and verifies that turning changes the selected result. / 侧栏搜索打开全局搜索；输入关键词、选择任务分类后，读取到两个任务结果，并验证转动改变选中条目。 |
| Open / 打开 | Confirm opens a task; the Home view disappears and the task composer becomes available. The test returns to Home, then reopens and cancels search. / 确认打开任务，首页消失且任务输入框可用；随后返回首页，再打开并取消搜索。 |
| Model / 模型 | Eight model candidates and one selected model are observed. Choosing another changes the model-control value; choosing the original restores it. / 识别到八个候选和一个选中模型；选择另一模型后回读控件值变化，选回原模型后回读一致。 |
| Editing / 编辑 | Paste is read back, left/right input changes the caret range, Backspace removes the expected character, and test text is cleared. / 回读粘贴结果、左右光标位置、删除后的文字，并清理测试草稿。 |
| Dictation delivery / 听写写入 | `Runtime → DictationSession → TextInserter` is exercised with deterministic transcript replay. Partial previews leave the test draft unchanged; final text appends to it, and the clipboard returns to its original data. / 转录回放经过完整写入链路；中间结果不改草稿，结束后追加文字，剪贴板恢复原数据。 |
| Empty composer / 空输入框 | The 77-character accessibility value is a known placeholder with inline spacing, not a user draft. 0.8.1 recognises it as empty. / 77 字符的辅助功能值是带行内空格的已知占位提示；0.8.1 正确识别为空输入框。 |

The run found and fixed two 0.8.0 defects: the model trigger is exposed as `AXComboBox`, and WorkBuddy's unlabelled rich-text composer exposes its placeholder as `AXValue`. Recognition remains scoped to the exact WorkBuddy bundle and known placeholder strings.

验收发现并修复 0.8.0 的两处问题：模型入口实际为 `AXComboBox`，无辅助功能标签的富文本输入框会把占位提示公开为 `AXValue`。新增识别仍限定在 WorkBuddy 的准确应用标识与已知占位文字中。

## Reproduce / 复现

Open WorkBuddy on its **empty Home composer**, with at least two existing task results matching the test query `a`. The test requires native Accessibility access and an explicit opt-in; the normal suite skips it.

打开 WorkBuddy 的**空首页输入框**，并保证至少两个现有任务能匹配测试关键词 `a`。该测试需要原生辅助功能访问与显式启用；普通测试会跳过实机用例。

```sh
VIBEWAND_WORKBUDDY_LIVE=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --filter WorkBuddyLiveTests
```

Source: [WorkBuddyLiveTests.swift](../Tests/VibeWandBridgeTests/WorkBuddyLiveTests.swift). Local acceptance logs are kept under ignored `output/workbuddy-live-acceptance/` and `output/release-v0.8.1/`; they contain test status and counts, not private task titles, drafts or clipboard data.

代码见上述链接；本地日志保存在被忽略的 `output/` 目录，只记录状态和数量，不输出私人任务标题、草稿或剪贴板内容。

Audio recognition, microphone hardware and physical controller button input were outside this app-adapter run. The 0.8.0 Applications-page images remain historical renderings of VibeWand's settings; they are not WorkBuddy screenshots or evidence for this run.

本轮应用适配验收不包含音频识别、麦克风硬件或物理手柄按键。应用指南中保留的 0.8.0 设置图片属于历史界面渲染，不是 WorkBuddy 截图或本轮验收证据。
