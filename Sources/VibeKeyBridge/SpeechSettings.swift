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
    /// The microphones connected when the page opened.
    @State private var inputs: [SpeechAudioInput.Input] = []
    init(model: SettingsModel, voice: VoiceInputController) {
        self.model = model; self.voice = voice
        _draft = State(initialValue: voice.configuration)
        _terms = State(initialValue: voice.configuration.effectiveVocabulary.terms.joined(separator: "\n"))
    }
    private var usesAPI: Bool { draft.mode == .builtIn && !draft.provider.isLocal }
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
                        draft.provider == .senseVoice ?
                        tr("在这台 Mac 上识别：录音不出本机，不用密钥，没有网络也能用。中文、英语、粤语、日语、韩语自动识别，中英混着说也行；说话时每秒更新一次预览，松开后很快出字。单次最多两分钟。", "Recognised on this Mac: the recording never leaves it, no key is needed, and it works without a network. Chinese, English, Cantonese, Japanese and Korean are detected, mixed speech included; a preview updates every second while you speak and the text follows the release at once. Each recording is limited to two minutes.") :
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
                    if insertion == .automatic {
                        Divider()
                        InputMethodSetting(model: model, input: model.runtime.inputMethod)
                    }
                }
                microphoneSettings
                vocabularySettings
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        if draft.provider == .senseVoice {
                            SettingsCard(title: tr("SenseVoice 模型", "SenseVoice models")) {
                                SenseVoiceModels(voice: voice)
                                SettingsNote(text: tr("识别程序就是 DeepSeek Harness 的 SenseVoice 插件里的那一个，随 VibeWand 自带。按住说话时启动，大约两秒，在你说话的同时完成；空闲 5 分钟后退出，运行时占用约 650 MB 内存。词表对它不起作用，专有名词靠“自动整理”纠正。", "The recogniser is the one in DeepSeek Harness's SenseVoice plug-in, and comes with VibeWand. It starts when you hold to speak, taking about two seconds while you talk, and exits after five idle minutes; while running it uses about 650 MB of memory. The vocabulary does not reach it: names are put right by Polish."))
                            }
                        } else {
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
                    (model.runtime.templates.selectedID == .keyboard ? ""
                        : model.runtime.deviceMicrophone != nil
                        ? tr("当前设备 \(model.runtime.deviceName) 的麦克风可用。", "The current device, \(model.runtime.deviceName), has a microphone.")
                        : tr("当前设备 \(model.runtime.deviceName) 没有可用的麦克风，使用 macOS 默认输入。", "The current device, \(model.runtime.deviceName), has no microphone available; the macOS default input is used.")))
                Divider()
                HStack {
                    Text(tr("键盘用的麦克风", "Microphone for the keyboard"))
                    Spacer()
                    Picker(tr("键盘用的麦克风", "Microphone for the keyboard"), selection: Binding(get: { draft.keyboardMicrophone }, set: { draft.keyboardMicrophone = $0; commit() })) {
                        Text(tr("Mac 内置麦克风", "This Mac's own microphone")).tag(String?.none)
                        ForEach(inputs.filter { !$0.builtIn }) { Text($0.name).tag(String?.some($0.uid)) }
                        // One that was chosen and is away now stays chosen.
                        if let chosen = draft.keyboardMicrophone, !inputs.contains(where: { $0.uid == chosen }) {
                            Text(tr("未连接的麦克风", "A microphone that is not connected")).tag(String?.some(chosen))
                        }
                    }.labelsHidden().frame(width: 310)
                }
                SettingsNote(text: tr("键盘没有自己的麦克风。用键盘的命令键或键盘布局说话时，自动换到这里选的麦克风；它没有连接时用 Mac 内置的。",
                                      "A keyboard has no microphone of its own. Speaking from the keyboard's command key or the keyboard layout switches to the one chosen here, and to this Mac's own while that one is not connected."))
            }
        }
        .onAppear { inputs = SpeechAudioInput.inputs() }
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

/// Where SenseVoice's models stand and the one thing to do about it. The settings show it in full; the guide,
/// which has a step's worth of room, shows it `compact`.
/// The switch for VibeWand's input method, and what switching it on puts on this Mac.
struct InputMethodSetting: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var input: InputMethod
    var body: some View {
        HStack(spacing: 12) {
            Label(state, systemImage: input.enabled ? "checkmark.seal.fill" : "character.cursor.ibeam")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(input.enabled ? Color.green : Color.primary)
            Spacer(minLength: 0)
            if input.enabled { Button(tr("关闭并移除", "Turn off and remove")) { input.remove() } }
            else { Button(tr("开启", "Turn on")) { model.perform { try input.install() } }.buttonStyle(.borderedProminent).disabled(!input.available || input.starting) }
        }
        SettingsNote(text: tr("开启后，文字在你说话时就一个字一个字出现在光标处，带下划线表示还会变；松开并整理完成后，整段换成最终文字。Codex、Claude、终端、浏览器等所有应用都一样，不经过剪贴板。这会在“资源库/Input Methods”里装一个 VibeWand 输入法组件，和 macOS 自带的听写是同一类：不替换你的键盘输入法，不接收任何按键，只把 VibeWand 的文字写进当前输入框。", "When on, text appears at the caret as you speak, a character at a time and underlined while it may still change; after you release and polishing finishes, the finished text replaces it in one step. It is the same in every app, Codex, Claude, terminals and browsers included, and the clipboard is not used. This installs a VibeWand input method in Library/Input Methods, of the kind macOS's own dictation is: it does not replace your keyboard input method, receives no keys, and only writes VibeWand's text into the focused field."))
    }
    private var state: String {
        if !input.available { return tr("这个版本没有带输入法组件", "This build does not carry the input method") }
        if input.starting { return tr("正在开启…", "Turning on…") }
        if input.failed { return tr("macOS 没有启用这个输入法组件，请再试一次", "macOS did not switch the input method on; try again") }
        if !input.enabled { return tr("在任何应用里边说边写：未开启", "Type as you speak in any app: off") }
        return input.connected ? tr("在任何应用里边说边写：已开启", "Type as you speak in any app: on")
            : tr("已开启，输入法组件会在需要时启动", "On; the input method starts when it is needed")
    }
}

struct SenseVoiceModels: View {
    @ObservedObject var voice: VoiceInputController
    var compact = false
    var body: some View {
        let local = voice.senseVoice
        let size = ByteCountFormatter.string(fromByteCount: local.downloadSize, countStyle: .file)
        let place = local.store.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
        let shared = local.sharesHarnessHome
            ? tr("这是 DeepSeek Harness 的目录，它自己的语音输入用的也是这一份。", "This is DeepSeek Harness's folder; its own voice input uses the same copy.")
            : tr("DeepSeek Harness 自己也准备过语音输入的话，VibeWand 会改用它那一份。", "Once DeepSeek Harness has prepared its own voice input, VibeWand uses that copy instead.")
        VStack(alignment: .leading, spacing: 9) {
            switch local.state {
            case .ready:
                Label(tr("模型已就绪", "The models are ready"), systemImage: "checkmark.seal.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(.green)
                if !compact { SettingsNote(text: tr("模型在 \(place)。", "The models are in \(place). ") + shared) }
            case .missing, .failed:
                let failed = local.state == .failed
                let fetch = Button(failed ? tr("继续下载", "Resume the download") : tr("下载并准备（\(size)）", "Download and prepare (\(size))")) { local.startDownload() }
                    .buttonStyle(.borderedProminent)
                HStack(spacing: 12) {
                    Label(failed ? tr("下载没有完成，已经下到的部分会接着用", "The download did not finish; what arrived is kept") : tr("需要先下载模型", "The models have to be downloaded first"),
                          systemImage: failed ? "exclamationmark.triangle" : "arrow.down.circle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(failed ? Color.orange : Color.primary)
                    if compact { Spacer(minLength: 0); fetch }
                }
                if !compact { fetch }
                SettingsNote(text: compact
                    ? tr("来自 Hugging Face，连不上时改用镜像 hf-mirror.com。下载在后台进行，可以先继续后面的步骤，下完再回来试。", "From Hugging Face, or the mirror hf-mirror.com when that cannot be reached. It downloads in the background: go on with the next steps and come back to try it.")
                    : tr("从 Hugging Face 下载插件指定的那几个文件，连不上时改用镜像 hf-mirror.com，下完逐个核对 SHA-256。保存到 \(place)。",
                         "The files the plug-in pins are fetched from Hugging Face, or from the mirror hf-mirror.com when that cannot be reached, and each is checked against its SHA-256. They are kept in \(place). ") + shared)
            case .downloading(let fraction):
                HStack(spacing: 12) {
                    ProgressView(value: fraction) {
                        Text(tr("正在下载模型 \(Int(fraction * 100))%", "Downloading the models, \(Int(fraction * 100))%")).font(.system(size: 14, weight: .medium)).monospacedDigit()
                    }
                    Button(tr("取消", "Cancel")) { local.cancelDownload() }
                }
            case .unavailable:
                Label(tr("这个构建不带 SenseVoice 的识别程序", "This build carries no SenseVoice recogniser"), systemImage: "xmark.octagon")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                SettingsNote(text: tr("识别程序随自带内核一起打包；跳过内核的构建里没有它。", "The recogniser is packaged with the built-in kernel; a build that skipped the kernel has none."))
            }
        }
        .onAppear { local.refresh() }
    }
}
