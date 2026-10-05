# 语音输入 / Voice input

「设置 → 语音输入」提供外置和内置模式。首次安装默认沿用外置模式：按住／释放 Fn，Typeless、豆包等输入法处理录音与识别。内置模式默认使用按下听写键的那个设备自带的麦克风（没有时用 macOS 默认输入，也可固定为系统声音输入），边录边识别，实时预览并同步写入原输入框；识别修正和松开后的整理只替换本次听写范围，不自动发送草稿。单次录音最多两分钟，音频只保留在内存中。设置页的测试按钮只展示结果，不向其他应用输入。

Settings → Voice input offers external and built-in modes. New installations keep the external Fn trigger. Built-in mode records from the microphone of the device whose dictation key you hold (falling back to the macOS default input, which can also be selected permanently) and transcribes live into the original editor. Revisions and optional polishing replace only the owned dictation range, without submitting. Audio stays in memory and recordings are limited to two minutes. Settings tests only display their result.

## 服务 / Providers

| 服务 | 配置与行为 |
| --- | --- |
| macOS 系统听写 | Apple Speech SDK；填写 `zh-CN`、`en-US` 等语言。支持时优先本机识别，其他语言可能依赖 Apple 在线服务。首次使用请求麦克风与语音识别权限。 |
| 阿里 Qwen 实时语音 | 配置 Realtime WebSocket 地址；PCM 16 kHz、16 bit、单声道。识别直接连接同一地址上的 `qwen3-asr-flash-realtime`，不指定语种，词表经 `input_audio_transcription.corpus.text` 传入；使用 `conversation.item.input_audio_transcription.text` 的 `text + stash` 实时预览，最终采用 `completed.transcript`。配置的模型（默认 omni）只用于自动整理；填写名称含 `asr` 的模型时改用它识别。 |
| 兼容语音转文字 API | `POST /audio/transcriptions`，multipart WAV，字段 `model`、`language`、`response_format=json`，读取 JSON `text`。适用于实现该协议的云服务或本地 Whisper / SenseVoice 网关。 |

Qwen 通用地址为 `wss://dashscope.aliyuncs.com/api-ws/v1/realtime`。新版业务空间使用 `wss://<workspace>.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime`。填写该空间的 HTTPS `/compatible-mode/v1` 或 `/api/v1` 基础地址时，Qwen 适配器转换为对应 Realtime 地址。模型由客户端添加为查询参数，配置地址本身不附查询参数。

兼容接口可以填写 HTTPS 基础地址，例如 `https://speech.example/v1`，也可填写完整 `/audio/transcriptions` 地址。本机 `http://localhost:8080/v1` 可不配置密钥。远端服务需要密钥；服务必须提供音频识别能力，纯文本聊天 API 无法代替语音转写。

Apple recognition uses the Speech SDK and prefers on-device recognition when supported. Qwen recognition connects to `qwen3-asr-flash-realtime` on the configured endpoint, passes the vocabulary as `corpus.text`, streams previews (confirmed text + tentative stash) and accepts the completed transcript; the configured model serves polishing only. Compatible HTTP providers must implement multipart `/audio/transcriptions` and return JSON `text`.

## 0.8.2：麦克风与词表 / Microphone and vocabulary

「语音输入 → 麦克风」有两个选项。**跟随设备**（默认）：每次按下听写键时，查找与该设备 USB 厂商／产品 ID 相同的 Core Audio 输入并只为本次录音选用它，不改动系统默认输入；VibeKey 接收器（`FFF1:00DD`）自带 48 kHz 输入，开启手柄蓝牙语音的 DualSense 使用其实验麦克风，导入的 HID 配置按自身的厂商／产品 ID 查找。设备没有麦克风时使用 macOS 默认输入。**系统声音输入**：始终使用 macOS 默认输入。

「词表与领域」包含三部分：内置软件开发词汇（默认开启，约 140 个常被听错的术语）、一句领域提示（例如“新能源汽车、机器人、照顾婴儿”）和自己的词汇（每行一个，或用逗号、顿号分隔；领域提示与词汇合计不超过 4000 字）。它们的去向：

| 环节 | 用法 |
| --- | --- |
| Qwen 识别 | 作为 `corpus.text` 上下文增强 |
| macOS 系统听写 | 前 100 个词作为 `contextualStrings`，自己的词汇优先 |
| 兼容语音转文字 API | 作为 multipart 的 `prompt` 字段，自己的词汇放在末尾 |
| 自动整理 | 附在整理指令后，用来改正同音、近音错词；稿中没有说到的词不添加 |

Settings → Voice input → Microphone defaults to **Follow the device**: each dictation looks up the Core Audio input sharing the pressed device's USB vendor/product ID and uses it for that recording only, without touching the macOS default input. Devices without a microphone fall back to the default input; **System sound input** always uses it. **Vocabulary and subject** combines built-in software-development terms, a one-line subject hint and your own terms. They are sent as Qwen `corpus.text`, Apple `contextualStrings` (first 100, yours first), the compatible API's `prompt`, and are appended to the polishing instructions to repair misheard words.

2026-10-05 验证：本机 Core Audio 列出 AU05 输入（型号 `AU05:FFF1:00DD`，USB，48 kHz 双声道），与 HID 厂商／产品 ID 一致；当时系统默认输入为蓝牙耳机。使用本机配置的百炼业务空间和 macOS 合成语音（非真人）通过 `SpeechAPICheck --stream` 验证专用 ASR 会话：15.1 秒中英混合音频松开前收到 54 次预览。同一段音频不带词表时得到“vibe want the dual sense 麦克风”，带内置词表时得到“VibeWand 的 DualSense 麦克风”。自动整理带词表时把“Vibe Wand”改为“VibeWand”，纯中文句子（够了、日志、超时、分支）保持原样。发布前作者手动试用了这一版本；设备麦克风的拾音电平、声道布局和真人识别准确率没有量化的验收记录，可在设置页的测试听写中自行确认。

Verified on 2026-10-05 with synthetic macOS speech, not a human voice: the dedicated ASR session streamed 54 previews before release for a 15.1 s mixed Chinese/English clip; the built-in vocabulary turned "vibe want the dual sense" into "VibeWand 的 DualSense", and polishing with the vocabulary repaired "Vibe Wand" while leaving plain Chinese sentences unchanged. The author tried this build by hand before release; there is no measured acceptance record for device-microphone levels, channel layout or human-voice accuracy, so confirm them with the Settings dictation test.

## 配置与密钥 / Preferences and credentials

分享 JSON 包含版本、输入方式、服务类型、语言、地址、模型、麦克风来源和词表（领域提示与词汇），存于本机 `vibeWand.speech.v1` 偏好。API Key 使用独立 Keychain 条目，service 为 `org.vibekey.bridge.speech-api`，account 是规范化目标地址的 SHA-256。密钥只供当前 Mac 使用，不同步，不导出。

更换地址或导入另一地址的配置不会把旧密钥用于新目标。地址不能带用户名、密码、查询参数或片段；请求拒绝 HTTP 重定向，避免携带密钥的录音上传被转发。诊断不包含音频、识别文字或原始服务错误。密钥框默认空白，保存后立即清空。

Preferences, including the microphone source and vocabulary, have no credential fields. Keys stay in local Keychain items bound to the normalized destination. Credential-bearing URLs and HTTP redirects are rejected. Provider error bodies and transcripts are excluded from diagnostics.

## 工程边界 / Engineering boundaries

`SpeechInput` 是独立 SwiftPM library，不导入 AppKit 或 SwiftUI。`DictationEngine` 定义开始、结束和取消，`DictationSession` 处理状态与并发取消；`SystemDictationEngine`、`APIDictationEngine`、`SpeechTranscribing`、`SpeechCredentialStore` 分离识别、协议和凭证。UI 只观察 `VoiceInputController` 并修改配置。

`BridgeRuntime` 将手势路由到外置 Fn 或内置会话，保留开始时的目标。`DictationDelivery` 验证应用、窗口、焦点及输入框状态，`AccessibilityAdapter` 负责 Unicode 文字输入。权限弹窗期间松开按键、设备断线、配置变化、切换应用或退出会取消会话；旧会话的迟到结果不传给新会话。

## 验证记录 / Verification

2026-10-04 使用本机配置的百炼北京业务空间和 `qwen3.8-omni-flash-realtime`，以 macOS 合成语音生成 5.6 秒中文音频，通过实际应用共用的 API 客户端转写，两次分别约 1.6 秒、1.1 秒返回：“这是语音输入测试，请帮我检查代码，并保留我的草稿。”密钥仅存钥匙串，不在配置、文档或仓库中。兼容 HTTP 模式另经本机服务验证 multipart WAV 上传与 JSON 转写响应。全量 155 项测试通过，图形化应用构建和签名验证成功。此测试验证协议、鉴权、音频格式与转写；麦克风权限、真实说话和目标输入仍需通过设置页及实际按键确认。

可重复测试已有音频文件，命令不接受密钥参数，只从相同地址的 Keychain 条目读取：

```sh
swift run SpeechAPICheck qwenRealtime \
  wss://dashscope.aliyuncs.com/api-ws/v1/realtime \
  qwen3.8-omni-flash-realtime /path/to/test.wav
```

`--stream` 按实时节奏发送并打印预览，`--polish` 追加自动整理，`--no-vocabulary` 关闭内置词汇，`--terms "词一,词二"` 加入自己的词汇，便于对比词表效果。

DeepSeek Harness 官方可选 Voice Input bundle 默认使用本地 `sensevoice-local`，通过统一语音服务注册识别器。当前没有将其 ONNX 运行时打包进 VibeWand；可通过兼容 HTTP 网关接入本地识别。

参考：[Apple Speech](https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio)、[阿里 Realtime](https://www.alibabacloud.com/help/zh/model-studio/realtime)、[阿里客户端事件](https://www.alibabacloud.com/help/zh/model-studio/client-events)、[DeepSeek Harness 官方 Voice Input bundle](https://github.com/deepseek-ai/deepseek-harness/tree/master/packages/experimental/voice-input-bundle)。

## 实时输入、大小模式和自动整理 / Live input and polishing

- 大小模式：完整设备面板或输入法式小条。小条闲置约 390 × 48 pt，听写中展开显示文字。两种模式都有原词／自动整理开关，模式切换不抢输入焦点。显示／隐藏仍独立于尺寸及内置听写开关。
- 实时文字：Apple Speech SDK 开启 partial results；Qwen 边录边传并接收真实中间结果。文件上传式 API 每约 2.5 秒加一次请求耗时上传当前录音用于预览，松开后做最终转写，因此会产生额外请求。不会偷偷启用另一识别服务。
- 原词：保留 ASR 返回文字，不加额外改写。自动整理：松开后去掉口头填充及重复，采用明确自我修正后的说法，修复标点、分段及列表，保留原意、事实和代码标识符。Qwen 默认复用语音模型及密钥；其他模式可单独设置 Qwen 或兼容 chat/completions 的整理服务。整理失败保留原词。
- 范围保护：捕获初始选区，仅替换本次文字。每次修正前核对整个草稿及选区，用户手动修改或切走时停止替换。已有草稿只用于本机校验，不加入整理请求。不通过 Return 提交消息；安全换行优先通过可访问性文本属性处理。

新增 `QwenRealtimeStream`、`SpeechTranscriptBuffer`、`SpeechTextProcessor` 保持语音传输、中间结果合并和文字整理独立；`DictationTargetAdapter` 与应用导航适配独立，`LiveDictationDraft` 单独负责范围所有权和插入，`SpeechOverlayHost` 只组合完整设备组件和共用语音小条。密钥状态查询只读取钥匙串元数据，实际读取在后台等待授权，避免设置界面卡住。

实际流式验证：5.6 秒中文合成音频约 1.8 秒开始收到预览，松开前 14 次更新。原生测试输入框已看到文字逐步出现，最终保留完整转写且只插入一份，原有草稿保留。焦点被切走的重放也按设计停止后续修改。

最后一轮共 169 项测试通过，包含实时预览修正、整理失败保留原词、已有草稿和选区保护、换行不触发提交、隐藏状态与大小切换、原生悬浮窗渲染。口误重放“十点，不对，是十一点”最终写入“十一点”，去除填充词及重复，原有草稿保留且未重复追加。实际真人麦克风仍可用设置页的听写测试验证。

### Codex 编辑器兼容修复

Codex 的 ProseMirror 编辑器使用正常粘贴事件接收文字，临时剪贴板内容仅在本机内存中保存；写入确认后恢复原有全部剪贴板格式。如果期间用户复制了新内容，不覆盖用户新复制的数据。Chrome 等已可工作的输入框沿用原有文本写入途径。

预览正常增长时只追加新后缀，识别修正只替换变化尾部。写入先等待 AX 文字和光标确认，允许分开更新及短暂缓存，不在每个预览到达时立即整段重写。焦点绑定到编辑器本身，内部段落节点变化不视为切换；已拥有的文字仍受草稿和选区校验保护。未收到写入确认会显示单独的错误，不再全部归为用户修改草稿。

兼容粘贴路径已在独立 Chromium contenteditable 页面实测，连续写入“测试语音输入连续出现文字。”，触发真实 input 事件并保留原有草稿，标题随输入变化也未中断。桌面自动操作工具禁止直接控制 Codex 自身界面，因此 Codex 本体需要用户复测。

## 0.7.0：文字如何写入 / How text is inserted

内置听写不再要求目标应用支持逐字改写。原生输入框（TextEdit、备忘录等）仍然边说边写，通过辅助功能直接改动本次听写的那一段。其余应用（Claude、Codex、DeepSeek Harness、浏览器、终端等）在松开后粘贴一次：剪贴板先暂存，粘贴完成后恢复，并带上剪贴板管理器约定的“临时内容”标记。某个应用的输入框不理会辅助功能写入时，本次运行期间会记住它，下次直接粘贴。密码框不接收听写。读不到输入框的应用（例如微信）同样会在光标处粘贴，只是无法回读确认。

“设置 → 语音输入 → 写入方式”可以改成“始终粘贴”或“模拟键入”。

Built-in dictation no longer needs the target app to support in-place edits. Native fields still fill in as you speak through accessibility writes limited to the dictated range. Every other app gets one paste on release: the clipboard is saved, restored afterwards, and marked as transient for clipboard managers. An app whose field ignores accessibility writes is remembered until quit and pasted into directly next time. Password fields never receive dictation. Apps that expose no readable editor are pasted into at the caret as well, without read-back confirmation. "Settings → Voice input → How text is inserted" can force paste or simulated typing.
