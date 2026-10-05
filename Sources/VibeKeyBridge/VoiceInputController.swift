import Foundation
import Combine
import SpeechInput
import WandAgent

/// App-level orchestration. Views observe preferences and state, while Runtime
/// owns the focus token and AccessibilityAdapter owns text delivery.
@MainActor
final class VoiceInputController: ObservableObject {
    @Published private(set) var configuration: SpeechConfiguration
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var message = ""
    @Published private(set) var testTranscript = ""
    @Published private(set) var liveTranscript = ""
    @Published private(set) var processingNotice: SpeechInputError?
    private var previewTimer: Timer?
    private var testing = false
    /// The recording is a spoken command: it goes to the coordinator, never into a text field.
    private var commanding = false
    var onChange: (() -> Void)?
    var onTranscript: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onCommandTranscript: ((String) -> Void)?
    var onCancel: (() -> Void)?
    /// Chooses the recording device for each session; nil is the macOS default input.
    var microphone: (() -> String?)?
    private let preferences: SpeechPreferences
    private let credentials: any SpeechCredentialStore
    private let session: DictationSession
    /// The recogniser that runs on this Mac, and the state of its models for the settings to show.
    let senseVoice: SenseVoice

    init(preferences: SpeechPreferences = SpeechPreferences(), credentials: any SpeechCredentialStore = KeychainSpeechCredentials(),
         senseVoice: SenseVoice? = nil, engineFactory: ((SpeechConfiguration) throws -> any DictationEngine)? = nil) {
        self.preferences = preferences; self.credentials = credentials
        configuration = preferences.load()
        let local = senseVoice ?? .shipped()
        self.senseVoice = local
        session = DictationSession(credentials: credentials, factory: engineFactory ?? { configuration in
            switch configuration.provider {
            case .system:
                // Apple recommends a short list; the speaker's own terms lead it.
                return SystemDictationEngine(locale: configuration.locale,
                    vocabulary: Array(configuration.effectiveVocabulary.allTerms.prefix(100)))
            // A recording is recognised here in a fraction of its length, so the preview keeps up with the speaker.
            case .senseVoice: return APIDictationEngine(configuration: configuration, credentials: credentials, client: local, previewSeconds: 1)
            case .qwenRealtime, .transcriptionAPI: return APIDictationEngine(configuration: configuration, credentials: credentials)
            }
        })
        local.onChange = { [weak self] in self?.objectWillChange.send() }
        session.onState = { [weak self] state in
            guard let self else { return }
            self.state = state; self.message = ""; self.onChange?()
        }
        session.onPartialTranscript = { [weak self] text in
            guard let self else { return }
            self.liveTranscript = text
            if !self.testing, !self.commanding, !text.isEmpty { self.onPartialTranscript?(text) }
            self.onChange?()
        }
        session.onNotice = { [weak self] notice in self?.processingNotice = notice; self?.onChange?() }
        session.onTranscript = { [weak self] text in
            guard let self else { return }
            if self.testing { self.testTranscript = text; self.testing = false }
            else if self.commanding { self.commanding = false; self.onCommandTranscript?(text) }
            else { self.onTranscript?(text) }
            self.previewTimer?.invalidate()
            self.previewTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.liveTranscript = ""; self?.onChange?() }
            }
        }
    }
    func update(_ value: SpeechConfiguration) throws {
        try preferences.save(value)
        cancel(); configuration = value; onChange?()
    }
    func begin() { resetPreview(); testing = false; commanding = false; message = ""; record(configuration) }
    func beginTest() { cancel(); resetPreview(); testing = true; testTranscript = ""; record(configuration) }
    /// A command is taken down as spoken: polishing could change what was asked for.
    func beginCommand() {
        cancel(); resetPreview(); commanding = true; message = ""
        var verbatim = configuration; verbatim.textStyle = .verbatim
        record(verbatim)
    }
    private func record(_ configuration: SpeechConfiguration) { SpeechAudioInput.deviceUID = microphone?(); session.begin(configuration) }
    func end() { session.end() }
    func cancel() { onCancel?(); testing = false; commanding = false; resetPreview(); session.cancel() }
    private func resetPreview() { previewTimer?.invalidate(); previewTimer = nil; liveTranscript = ""; processingNotice = nil }
    func setTextStyle(_ style: DictationTextStyle) throws {
        guard state != .transcribing && state != .polishing else { return }
        var value = configuration; value.textStyle = style
        try preferences.save(value); configuration = value; session.textStyle = style; onChange?()
    }
    func toggleTextStyle() throws { try setTextStyle(configuration.effectiveTextStyle == .verbatim ? .polished : .verbatim) }
    func report(_ text: String) { message = text; onChange?() }
    var displayMessage: String { processingNotice?.displayMessage ?? (message.isEmpty ? state.title : message) }
    func refreshLanguage() { message = ""; onChange?() }
    var keySaved: Bool { credentials.contains(for: configuration) }
    func hasKey(for value: SpeechConfiguration) -> Bool { credentials.contains(for: value) }
    func saveKey(_ key: String) throws { try credentials.save(key, for: configuration); onChange?() }
    func removeKey() throws { cancel(); try credentials.remove(for: configuration); onChange?() }
    func savePolishingKey(_ key: String) throws {
        guard let settings = configuration.effectivePolishing else { throw SpeechInputError.polishingUnavailable }
        try credentials.save(key, for: settings); onChange?()
    }
    func hasPolishingKey(for value: SpeechConfiguration) -> Bool {
        guard let settings = value.effectivePolishing else { return false }
        return credentials.contains(for: settings)
    }
    func export() throws -> Data { try preferences.export(configuration) }
    func importConfiguration(_ data: Data) throws { try update(preferences.decodeImport(data)) }
}

extension SpeechProvider {
    var title: String {
        switch self {
        case .system: return L10n.tr("macOS 系统听写", "macOS dictation")
        case .senseVoice: return L10n.tr("SenseVoice（本机）", "SenseVoice (on this Mac)")
        case .qwenRealtime: return L10n.tr("阿里 Qwen 实时语音", "Alibaba Qwen Realtime")
        case .transcriptionAPI: return L10n.tr("兼容语音转文字 API", "Compatible transcription API")
        }
    }
}
extension DictationState {
    var title: String {
        switch self {
        case .idle: return L10n.tr("按住说话，松开结束", "Hold to speak. Release to finish.")
        case .preparing: return L10n.tr("正在准备麦克风与权限…", "Preparing microphone and permissions…")
        case .recording: return L10n.tr("正在听写 · 松开结束", "Listening · release to finish")
        case .transcribing: return L10n.tr("正在识别语音…", "Transcribing…")
        case .polishing: return L10n.tr("正在自动整理…", "Polishing…")
        case .completed: return L10n.tr("听写完成", "Dictation complete")
        case .failed(let error): return error.displayMessage
        }
    }
}
extension SpeechInputError {
    var displayMessage: String {
        let zh: String
        switch self {
        case .invalidEndpoint: zh = "请使用 HTTPS / WSS 地址，不要在地址中附带密钥、查询参数或用户名。"
        case .invalidConfiguration: zh = "语音配置无效。"
        case .missingAPIKey: zh = "请先为此服务地址保存 API Key。"
        case .microphoneDenied: zh = "请在 macOS 隐私与安全性中开启麦克风权限。"
        case .speechDenied: zh = "请在 macOS 隐私与安全性中开启语音识别权限。"
        case .unavailable: zh = "此语言的系统语音识别暂不可用，请稍后重试或切换语音服务。"
        case .recordingFailed: zh = "无法启动麦克风，请检查 macOS 的声音输入设置。"
        case .tooLong: zh = "单次听写最多两分钟，请松开后重新开始。"
        case .noSpeech: zh = "未识别到语音。"
        case .emptyAudio: zh = "录音太短，请按住说话后再松开。"
        case .timedOut: zh = "语音识别超时，请重试。"
        case .protocolRejected: zh = "语音服务未接受请求，请检查接口协议、模型和密钥。"
        case .polishingUnavailable: zh = "自动整理暂不可用，已保留原词；请配置整理服务和密钥。"
        case .modelMissing: zh = "SenseVoice 的模型还没有下载，请到“语音输入”里下载。"
        case .http(let code): zh = "语音服务返回 HTTP \(code)，请检查地址、模型和密钥。"
        case .keychain(let code): zh = "钥匙串操作失败（\(code)）。"
        }
        return L10n.tr(zh, localizedDescription)
    }
}

extension DictationTextStyle {
    var title: String { self == .verbatim ? L10n.tr("原词", "Verbatim") : L10n.tr("自动整理", "Polish") }
}

extension SenseVoice {
    /// The recogniser VibeWand ships, with the models kept the way a harness keeps them: in the home of a DeepSeek
    /// Harness the user installed, where that harness's own voice input finds them too, and otherwise in VibeWand's
    /// own folder, beside the built-in harness's home rather than in it, so that clearing command mode's records
    /// leaves them alone.
    static func shipped() -> SenseVoice {
        let own = Harness.speechData(in: CommandController.applicationSupport)
        let installed = CommandSettings.locate(.harness)?.home.map(Harness.speechData(in:))
        return SenseVoice(runtime: CommandSettings.locate(.builtIn)?.speech.map {
            Runtime(node: $0.node, worker: $0.worker, assets: $0.assets, stores: [installed, own].compactMap { $0 })
        })
    }
    /// Whether the models are kept in an installed harness's home rather than VibeWand's own.
    var sharesHarnessHome: Bool { store.map { !$0.path.hasPrefix(CommandController.applicationSupport.path) } ?? false }
}
