import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SpeechInput

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct SpeechSettings: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var voice: VoiceInputController
    @State private var draft: SpeechConfiguration
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var polishingKey = ""
    @State private var polishingKeySaved = false
    @State private var insertion = TextInserter.method
    /// The terms as typed; `draft` always holds their parsed form.
    @State private var terms: String
    init(model: SettingsModel, voice: VoiceInputController) {
        self.model = model; self.voice = voice
        _draft = State(initialValue: voice.configuration)
        _terms = State(initialValue: voice.configuration.effectiveVocabulary.terms.joined(separator: "\n"))
    }
    private var usesAPI: Bool { draft.mode == .builtIn && draft.provider != .system }
    var body: some View {
        StandardPage(title: tr("语音输入", "Voice input"), subtitle: tr("按住听写键说话，松开后检查文字，再自行发送。", "Hold your dictation button, release and review the text before sending.")) {
            SettingsCard(title: tr("输入方式", "Input method")) {
                Picker(tr("语音输入", "Voice input"), selection: Binding(get: { draft.mode }, set: { draft.mode = $0; commit() })) {
                    Text(tr("外置输入法", "External input method")).tag(SpeechInputMode.external)
                    Text(tr("内置语音输入", "Built-in voice input")).tag(SpeechInputMode.builtIn)
                }.pickerStyle(.segmented).labelsHidden()
                if draft.mode == .external {
                    SettingsNote(text: tr("继续使用 Typeless、豆包等输入法。VibeWand 按住／释放 Fn，触发方式和麦克风由外置输入法管理。", "Use Typeless, Doubao or another input method. VibeWand holds/releases Fn; the external app manages its shortcut and microphone."))
                } else {
                    HStack {
                        Text(tr("听写服务", "Recognition service"))
                        Spacer()
                        Picker(tr("听写服务", "Recognition service"), selection: Binding(get: { draft.provider }, set: { provider in
                            draft.selectProvider(provider)
                            commit()
                        })) {
                            ForEach(SpeechProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 310)
                    }
                    SettingsNote(text: draft.provider == .system ?
                        tr("使用 Apple Speech SDK，支持时优先在本机识别；其他语言可能使用 Apple 在线服务。首次使用会请求麦克风和语音识别权限。", "Uses Apple Speech SDK with on-device recognition when supported. Other languages may use Apple's online service. First use requests microphone and speech recognition access.") :
                        tr("录音保存在内存中，边录边转写。文件式 API 会定期上传当前录音生成预览。单次最多两分钟。", "Audio stays in memory and transcription appears while recording. File-upload APIs periodically upload the current recording for previews. Each recording is limited to two minutes."))
                    Divider()
                    Picker(tr("文字模式", "Text mode"), selection: Binding(get: { voice.configuration.effectiveTextStyle }, set: { style in
                        model.perform { try voice.setTextStyle(style) }
                    })) {
                        ForEach(DictationTextStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().disabled(voice.state == .transcribing || voice.state == .polishing)
                    SettingsNote(text: tr("原词保留识别结果；自动整理在松开后去掉口头填充和重复、修正标点并保留原意。悬浮窗也能快速切换。", "Verbatim keeps recognition output. Polish removes fillers and repetition and fixes punctuation after release, preserving your meaning. Both overlays offer the same quick switch."))
                }
            }
            if draft.mode == .builtIn {
                SettingsCard(title: tr("写入方式", "How text is inserted")) {
                    Picker(tr("写入方式", "How text is inserted"), selection: Binding(get: { insertion }, set: { insertion = $0; TextInserter.method = $0 })) {
                        ForEach(TextInsertionMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    SettingsNote(text: tr("自动：原生输入框边说边写；Claude、Codex、浏览器等网页类输入框在松开后一次粘贴，随后恢复剪贴板。应用不接受粘贴时可改用模拟键入。", "Automatic: native fields fill in as you speak; web-based editors such as Claude, Codex and browsers get one paste on release, after which your clipboard is restored. Use simulated typing for apps that refuse paste."))
                }
                microphoneSettings
                vocabularySettings
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        SettingsCard(title: usesAPI ? tr("服务配置", "Service settings") : tr("识别语言", "Recognition language")) {
                            if draft.provider != .qwenRealtime { field(tr("语言", "Language"), text: $draft.locale, placeholder: "zh-CN / en-US") }
                            if usesAPI {
                                field(tr("服务地址", "Endpoint"), text: $draft.endpoint, placeholder: "https://… / wss://…")
                                field(tr("模型", "Model"), text: $draft.model, placeholder: "Model ID")
                                SettingsNote(text: draft.provider == .qwenRealtime ?
                                    tr("支持百炼业务空间地址和完整 Realtime WebSocket 地址。这里的 Omni 模型负责识别和自动整理：词表和领域提示写进它的系统提示词，语种自动识别。", "Accepts a Model Studio workspace base URL or full Realtime WebSocket URL. The Omni model here both recognises and polishes: the vocabulary and subject hint go into its system prompt, and the language is detected.") :
                                    tr("兼容 POST /audio/transcriptions，上传 WAV 并读取 JSON 的 text 字段。支持本机 HTTP 服务。", "Uses POST /audio/transcriptions with a WAV upload and the JSON text field. Local HTTP services are supported."))
                            }
                            HStack { Spacer(); Button(tr("保存配置", "Save settings"), action: commit).disabled(voice.state.active) }
                        }
                        if usesAPI {
                            SettingsCard(title: "API Key") {
                                Label(keySaved ? tr("此地址的密钥已保存", "Key saved for this endpoint") : tr("此地址尚未保存密钥", "No key saved for this endpoint"), systemImage: keySaved ? "checkmark.shield" : "key")
                                    .font(.system(size: 14, weight: .medium))
                                SecureField(tr("输入新密钥", "Enter a new key"), text: $keyDraft).textFieldStyle(.roundedBorder)
                                HStack {
                                    Button(tr("保存密钥", "Save key")) {
                                        model.perform {
                                            try model.runtime.updateSpeechConfiguration(draft)
                                            try voice.saveKey(keyDraft); keyDraft = ""; keySaved = voice.keySaved
                                        }
                                    }.disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || voice.state.active)
                                    Button(tr("删除密钥", "Delete key")) { model.perform { try voice.removeKey(); keySaved = false; keyDraft = "" } }.disabled(!keySaved)
                                }
                                SettingsNote(text: tr("密钥单独保存在此 Mac 的钥匙串中。导出配置包含服务地址、模型、语言和词表，不含密钥。", "Keys are stored separately in this Mac's Keychain. Exported settings contain the endpoint, model, language and vocabulary, never keys."))
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(spacing: 16) {
                        polishingSettings
                        SettingsCard(title: tr("测试听写", "Test dictation")) {
                            Text(voice.displayMessage).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                if voice.state == .recording {
                                    Button(tr("结束并识别", "Stop and transcribe")) { voice.end() }.buttonStyle(.borderedProminent)
                                } else {
                                    Button(tr("开始测试", "Start test")) {
                                        model.perform { try model.runtime.updateSpeechConfiguration(draft); voice.beginTest() }
                                    }.disabled(voice.state.active).buttonStyle(.borderedProminent)
                                }
                                if voice.state.active { Button(tr("取消", "Cancel")) { voice.cancel() } }
                            }
                            if !voice.liveTranscript.isEmpty { Text(voice.liveTranscript).textSelection(.enabled).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true) }
                            else if !voice.testTranscript.isEmpty { Text(voice.testTranscript).textSelection(.enabled).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true) }
                            SettingsNote(text: tr("测试结果只显示在本页，使用上方选择的麦克风和词表。", "Test results appear here, using the microphone and vocabulary chosen above."))
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            HStack {
                Button(tr("导入配置…", "Import settings…"), action: importConfiguration)
                Button(tr("导出配置…", "Export settings…"), action: exportConfiguration)
                Spacer()
                Text(tr("不包含 API Key", "API keys are excluded")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .onAppear { keySaved = voice.keySaved; polishingKeySaved = voice.hasPolishingKey(for: voice.configuration) }
        .onDisappear { keyDraft = ""; polishingKey = ""; voice.cancel() }
        .onReceive(voice.$configuration) { configuration in
            draft = configuration; keySaved = voice.hasKey(for: configuration); polishingKeySaved = voice.hasPolishingKey(for: configuration)
            let saved = configuration.effectiveVocabulary.terms
            if SpeechVocabulary.terms(from: terms) != saved { terms = saved.joined(separator: "\n") }
        }
    }
    private var microphoneSettings: some View {
        SettingsCard(title: tr("麦克风", "Microphone")) {
            Picker(tr("麦克风", "Microphone"), selection: Binding(get: { draft.effectiveMicrophone }, set: { draft.microphone = $0; commit() })) {
                Text(tr("跟随设备", "Follow the device")).tag(SpeechMicrophone.device)
                Text(tr("系统声音输入", "System sound input")).tag(SpeechMicrophone.system)
            }.pickerStyle(.segmented).labelsHidden()
            if draft.effectiveMicrophone == .system {
                SettingsNote(text: tr("使用 macOS 当前默认输入设备，可在系统声音设置中更改。", "Uses the current macOS default input; change it in Sound settings."))
                Button(tr("打开声音设置…", "Open Sound settings…")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.sound")!) }
            } else {
                SettingsNote(text: tr("按下哪个设备的听写键，就用那个设备自带的麦克风，不改动系统默认输入。", "Dictation records from the microphone of the device whose key you hold, leaving the macOS default input alone.") + " " +
                    (model.runtime.deviceMicrophone != nil
                        ? tr("当前设备 \(model.runtime.deviceName) 的麦克风可用。", "The current device, \(model.runtime.deviceName), has a microphone.")
                        : tr("当前设备 \(model.runtime.deviceName) 没有可用的麦克风，使用 macOS 默认输入。", "The current device, \(model.runtime.deviceName), has no microphone available; the macOS default input is used.")))
            }
        }
    }
    private var vocabularySettings: some View {
        SettingsCard(title: tr("词表与领域", "Vocabulary and subject")) {
            Toggle(tr("默认 AI 编程词表", "Default AI coding vocabulary"), isOn: Binding(get: { draft.effectiveVocabulary.computing },
                set: { enabled in vocabulary { $0.computing = enabled }; commit() }))
            field(tr("领域提示", "Subject hint"), text: Binding(get: { draft.effectiveVocabulary.domain }, set: { text in vocabulary { $0.domain = text } }),
                  placeholder: tr("例如：新能源汽车、机器人、照顾婴儿", "e.g. electric vehicles, robotics, baby care"))
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("我的词汇", "My terms")).font(.system(size: 13, weight: .medium))
                TextEditor(text: Binding(get: { terms }, set: { text in
                    terms = text; vocabulary { $0.terms = SpeechVocabulary.terms(from: text) }
                })).font(.system(size: 13)).frame(height: 92)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }
            HStack {
                SettingsNote(text: tr("每行一个词，也可用逗号、顿号分隔：人名、产品名、项目名、缩写等。", "One term per line, or separated by commas: names, products, projects, abbreviations."))
                Spacer()
                Button(tr("保存词表", "Save vocabulary"), action: commit).disabled(voice.state.active)
            }
            SettingsNote(text: tr("默认词表收录 \(SpeechVocabulary.defaultTerms.count) 个 AI 编程常用词：模型与编程工具、智能体概念、Git 和工程术语。词表和领域提示随每次听写发给所选语音服务，让识别偏向这些写法；自动整理也据此纠正同音错词。", "The default vocabulary holds \(SpeechVocabulary.defaultTerms.count) AI coding terms: models and coding tools, agent concepts, Git and engineering words. The vocabulary and subject hint are sent to the selected speech service with each dictation to bias recognition; polishing also uses them to repair misheard words."))
        }
    }
    private func vocabulary(_ change: (inout SpeechVocabulary) -> Void) {
        var value = draft.effectiveVocabulary; change(&value); draft.vocabulary = value
    }
    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
    private var polishingSettings: some View {
        SettingsCard(title: tr("自动整理服务", "Polishing service")) {
            SettingsNote(text: tr("阿里 Qwen 可沿用语音服务的地址、模型和密钥。系统听写或其他语音 API 也可以单独配置整理服务。整理失败时保留原词。", "Qwen can reuse your recognition endpoint, model and key. System dictation and other speech APIs can use a separate polishing service. If polishing fails, the original text is kept."))
            Toggle(tr("单独配置整理服务", "Use a separate polishing service"), isOn: Binding(get: { draft.polishing != nil }, set: { enabled in
                draft.polishing = enabled ? (draft.effectivePolishing ?? SpeechPolishingConfiguration(provider: .chatCompletions,
                    endpoint: "https://your-service.example/v1", model: "qwen-plus")) : nil
                commit()
            })).disabled(voice.state.active)
            if let settings = draft.polishing {
                Picker(tr("服务类型", "Protocol"), selection: Binding(get: { settings.provider }, set: { provider in
                    draft.polishing?.provider = provider
                })) {
                    Text("Qwen Realtime").tag(SpeechPolishingProvider.qwenRealtime)
                    Text(tr("兼容文本 API", "Compatible text API")).tag(SpeechPolishingProvider.chatCompletions)
                }
                field(tr("服务地址", "Endpoint"), text: Binding(get: { draft.polishing?.endpoint ?? "" }, set: { draft.polishing?.endpoint = $0 }), placeholder: "https://… / wss://…")
                field(tr("整理模型", "Polishing model"), text: Binding(get: { draft.polishing?.model ?? "" }, set: { draft.polishing?.model = $0 }), placeholder: "Model ID")
                Button(tr("保存整理配置", "Save polishing settings"), action: commit).disabled(voice.state.active)
                Label(polishingKeySaved ? tr("整理密钥已保存", "Polishing key saved") : tr("尚未保存整理密钥", "No polishing key saved"), systemImage: "key")
                    .font(.system(size: 13))
                SecureField(tr("整理服务的 API Key", "Polishing API key"), text: $polishingKey).textFieldStyle(.roundedBorder)
                Button(tr("保存整理密钥", "Save polishing key")) {
                    model.perform {
                        try model.runtime.updateSpeechConfiguration(draft)
                        try voice.savePolishingKey(polishingKey); polishingKey = ""; polishingKeySaved = true
                    }
                }.disabled(polishingKey.isEmpty || voice.state.active)
            }
        }
    }
    private func commit() {
        model.perform { try model.runtime.updateSpeechConfiguration(draft); keySaved = voice.keySaved }
    }
    private func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform {
            let data = try Data(contentsOf: url)
            let value = try SpeechPreferences().decodeImport(data)
            try model.runtime.updateSpeechConfiguration(value); keyDraft = ""
        }
    }
    private func exportConfiguration() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "VibeWand-Voice.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform { try voice.export().write(to: url, options: .atomic) }
    }
}
