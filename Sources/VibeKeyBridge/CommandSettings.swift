import AppKit
import SpeechInput
import WandAgent

/// The keyboard's command key: a right-hand modifier held on its own.
enum CommandHotkey: String, CaseIterable {
    case none, rightCommand, rightOption, rightControl, rightShift
    var title: String {
        switch self {
        case .none: return L10n.tr("不使用键盘", "No keyboard key")
        case .rightOption: return L10n.tr("右 ⌥ Option", "Right ⌥ Option")
        case .rightCommand: return L10n.tr("右 ⌘ Command", "Right ⌘ Command")
        case .rightControl: return L10n.tr("右 ⌃ Control", "Right ⌃ Control")
        case .rightShift: return L10n.tr("右 ⇧ Shift", "Right ⇧ Shift")
        }
    }
    var keyCode: Int64? {
        switch self {
        case .none: return nil
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .none: return []
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        }
    }
}

/// A service the coordinator's model can be served from: an address and the protocol spoken there.
/// The last entry takes whatever address the user types.
struct CommandEndpoint: Identifiable {
    let id: String
    private let names: (zh: String, en: String)
    let wire: ModelRoute.Wire
    let baseURL: String
    /// Filled in where the service's model names are stable enough to ship.
    let model: String
    var title: String { L10n.tr(names.zh, names.en) }

    static let custom = "custom"
    static let all: [CommandEndpoint] = [
        .init("deepseek", "DeepSeek", "DeepSeek", .openAIChat, "https://api.deepseek.com", model: "deepseek-flash"),
        .init("openai", "OpenAI", "OpenAI", .openAIChat, "https://api.openai.com/v1"),
        .init("anthropic", "Anthropic", "Anthropic", .anthropic, "https://api.anthropic.com"),
        .init("openrouter", "OpenRouter", "OpenRouter", .openAIChat, "https://openrouter.ai/api/v1"),
        .init("gemini", "Google Gemini", "Google Gemini", .openAIChat, "https://generativelanguage.googleapis.com/v1beta/openai"),
        .init("dashscope", "阿里云百炼（通义千问）", "Alibaba Model Studio (Qwen)", .openAIChat, "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        .init("moonshot", "Moonshot（Kimi）", "Moonshot (Kimi)", .openAIChat, "https://api.moonshot.cn/v1"),
        .init("zhipu", "智谱", "Zhipu", .openAIChat, "https://open.bigmodel.cn/api/paas/v4"),
        .init("ark", "火山方舟（豆包）", "Volcengine Ark (Doubao)", .openAIChat, "https://ark.cn-beijing.volces.com/api/v3"),
        .init("siliconflow", "硅基流动", "SiliconFlow", .openAIChat, "https://api.siliconflow.cn/v1"),
        .init("ollama", "Ollama（本机）", "Ollama (this Mac)", .openAIChat, "http://127.0.0.1:11434/v1"),
        .init("lmstudio", "LM Studio（本机）", "LM Studio (this Mac)", .openAIChat, "http://127.0.0.1:1234/v1"),
        .init("omlx", "oMLX（本机）", "oMLX (this Mac)", .openAIChat, "http://127.0.0.1:8000/v1"),
        .init(custom, "自定义地址", "Custom address", .openAIChat, "")
    ]
    private init(_ id: String, _ zh: String, _ en: String, _ wire: ModelRoute.Wire, _ baseURL: String, model: String = "") {
        self.id = id; names = (zh, en); self.wire = wire; self.baseURL = baseURL; self.model = model
    }
}

/// The model command mode runs on: an endpoint, the model picked on it and how it is driven.
struct CommandModel: Codable, Equatable {
    var endpoint: String
    var baseURL: String
    var wire: ModelRoute.Wire
    var model: String
    /// Tokens the model's context holds. 0 leaves the kernel's own assumption.
    var contextWindow = 0
    var reasoning = ModelRoute.Reasoning.automatic
    /// Further provider settings for the kernel as a JSON object, or empty.
    var extra = ""

    init(_ endpoint: CommandEndpoint) {
        self.endpoint = endpoint.id; baseURL = endpoint.baseURL; wire = endpoint.wire; model = endpoint.model
    }

    /// The address without its path: what a saved key is bound to.
    var origin: String? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }
    /// A server on this Mac, or one the user described themselves, may ask for no key.
    var keyOptional: Bool {
        endpoint == CommandEndpoint.custom || ["localhost", "127.0.0.1", "::1"].contains(URL(string: baseURL)?.host?.lowercased() ?? "")
    }
    var extraSettings: [String: JSONValue]? {
        let text = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [:] }
        guard case .object(let members)? = JSONValue(data: Data(text.utf8)) else { return nil }
        return members
    }
}

/// Which DeepSeek Harness runs the coordinator.
enum CommandKernelMode: String, CaseIterable {
    /// The one VibeWand ships, set up on the page below.
    case builtIn
    /// One the user installed, running VibeWand's coordinator as a plugin: its models, its sign-ins, its session list.
    case harness
}

enum CommandSettingsError: LocalizedError {
    case address, extra
    var errorDescription: String? {
        switch self {
        case .address: return L10n.tr("服务地址需要是 http:// 或 https:// 开头的完整地址", "The address must be a full http:// or https:// URL.")
        case .extra: return L10n.tr("附加参数需要是一个 JSON 对象，例如 {\"timeoutMs\": 60000}", "Extra settings must be a JSON object, such as {\"timeoutMs\": 60000}.")
        }
    }
}

extension PermissionMode {
    var title: String {
        switch self {
        case .ask: return L10n.tr("每步确认", "Ask every time")
        case .risky: return L10n.tr("只确认有风险的", "Ask when risky")
        case .bypass: return L10n.tr("跳过全部确认", "Bypass all")
        }
    }
    var summary: String {
        switch self {
        case .ask: return L10n.tr("切换应用、打开会话、按下控件、发送按键、输入文字，每一步都先显示要做什么，等你按确认键。读取界面和查找不用确认。",
                                  "Switching apps, opening a chat, pressing a control, sending keys and typing each show what is about to happen and wait for your confirm key. Reading and searching do not.")
        case .risky: return L10n.tr("导航和输入直接执行。删除、发送、提交这类控件和按键，每次等你按确认键。",
                                    "Navigation and typing run at once. Controls and keys that delete, send or submit wait for your confirm key every time.")
        case .bypass: return L10n.tr("什么都不问，包括删除、发送和提交。模型认错控件或听错话时，这些操作也会直接执行。",
                                     "Nothing is asked, deleting, sending and submitting included. When the model picks the wrong control or mishears you, those happen too.")
        }
    }
}

/// Command mode preferences. The switch is on from the start and the mode is live
/// once a model is set up: nothing leaves this Mac until the user has chosen where
/// it goes. Each model key lives in the Keychain, apart from speech keys and bound
/// to the address it was saved for.
@MainActor
final class CommandSettings: ObservableObject {
    nonisolated static let service = "org.vibekey.bridge.command-model"
    private let defaults: UserDefaults
    private let credentials: any SpeechCredentialStore
    @Published private(set) var enabled: Bool
    @Published private(set) var hotkey: CommandHotkey
    @Published private(set) var model: CommandModel
    @Published private(set) var permission: PermissionMode
    /// Minutes without a command after which the next one starts a new conversation. 0 starts every command afresh.
    @Published private(set) var historyMinutes: Int
    /// Seconds one command may act for, questions included.
    @Published private(set) var timeLimit: Int
    /// Tool calls one command may make.
    @Published private(set) var stepLimit: Int
    /// The user's own notes for the coordinator, added after its rules.
    @Published private(set) var instructions: String
    @Published private(set) var kernelMode: CommandKernelMode
    /// The model picked for plugin mode. nil follows the default the user's harness is set to.
    @Published private(set) var harnessModel: HarnessPlugin.Model?
    @Published private(set) var harnessReasoning: ModelRoute.Reasoning
    /// The user chose to run on a harness version the plugin has not been verified with.
    @Published private(set) var harnessUnverified: Bool
    private var remembered: [String: CommandModel]
    private let locateHarness: () -> HarnessPlugin?
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         credentials: any SpeechCredentialStore = KeychainSpeechCredentials(service: CommandSettings.service),
         harness: @escaping () -> HarnessPlugin? = CommandSettings.installedHarness) {
        self.defaults = defaults; self.credentials = credentials; locateHarness = harness
        kernelMode = defaults.string(forKey: "commandKernelMode").flatMap(CommandKernelMode.init(rawValue:)) ?? .builtIn
        harnessModel = defaults.data(forKey: "commandHarnessModel").flatMap { try? JSONDecoder().decode(HarnessPlugin.Model.self, from: $0) }
        harnessReasoning = defaults.string(forKey: "commandHarnessReasoning").flatMap(ModelRoute.Reasoning.init(rawValue:)) ?? .automatic
        harnessUnverified = defaults.bool(forKey: "commandHarnessUnverified")
        enabled = defaults.object(forKey: "commandModeEnabled") as? Bool ?? true
        // Right Option is the voice key of some input methods, which take it before any other listener sees it.
        hotkey = defaults.string(forKey: "commandHotkey").flatMap(CommandHotkey.init(rawValue:)) ?? .rightCommand
        remembered = defaults.data(forKey: "commandModels").flatMap { try? JSONDecoder().decode([String: CommandModel].self, from: $0) } ?? [:]
        let endpoint = defaults.string(forKey: "commandEndpoint") ?? CommandEndpoint.all[0].id
        model = remembered[endpoint] ?? CommandModel(CommandEndpoint.all.first { $0.id == endpoint } ?? CommandEndpoint.all[0])
        permission = defaults.string(forKey: "commandPermission").flatMap(PermissionMode.init(rawValue:)) ?? .risky
        historyMinutes = defaults.object(forKey: "commandHistoryMinutes") as? Int ?? 5
        timeLimit = defaults.object(forKey: "commandTimeLimit") as? Int ?? 120
        stepLimit = defaults.object(forKey: "commandStepLimit") as? Int ?? Gateway.stepLimit
        instructions = defaults.string(forKey: "commandInstructions") ?? ""
    }

    /// What an endpoint was last set to, or how it starts out.
    func configuration(for endpoint: String) -> CommandModel {
        remembered[endpoint] ?? CommandModel(CommandEndpoint.all.first { $0.id == endpoint } ?? CommandEndpoint.all[0])
    }
    /// A key is kept per address, so pointing an endpoint somewhere else never sends a key there.
    private func account(_ model: CommandModel) -> String? {
        // DeepSeek's key keeps the account it was saved under before endpoints could be chosen.
        model.origin.map { $0 == "https://api.deepseek.com" ? "deepseek-official" : $0 }
    }
    func keySaved(for model: CommandModel) -> Bool { account(model).map(credentials.contains(account:)) ?? false }
    var keySaved: Bool { keySaved(for: model) }
    /// The user's own DeepSeek Harness, when one is installed and this build carries the plugin for it.
    var harness: HarnessPlugin? { locateHarness() }
    nonisolated static func installedHarness() -> HarnessPlugin? {
        // A direct SwiftPM run has no bundle: the plugin is then the one in the checkout.
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundles = [Bundle.main.resourceURL?.appendingPathComponent("harness-plugin"), checkout.appendingPathComponent("kernel/plugin")]
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh")
        return bundles.lazy.compactMap { $0 }.compactMap { HarnessPlugin.locate(desktopApp: app, bundle: $0) }.first
    }
    /// Enough is set to run a command. On the built-in kernel: an address, a model, and a key where one is needed.
    /// In plugin mode the models and keys are the harness's, so it is enough that one is installed.
    var usable: Bool {
        kernelMode == .harness ? harness != nil : model.origin != nil && !model.model.isEmpty && (model.keyOptional || keySaved)
    }
    /// The model a command runs on, as the overlay names it.
    var modelName: String { kernelMode == .harness ? (harnessModel ?? harness?.defaultModel)?.model ?? "" : model.model }
    /// The command key is live. Until then the device's keys keep what they did without command mode.
    var active: Bool { enabled && usable }

    func setEnabled(_ value: Bool) { enabled = value; defaults.set(value, forKey: "commandModeEnabled"); onChange?() }
    func setHotkey(_ value: CommandHotkey) { hotkey = value; defaults.set(value.rawValue, forKey: "commandHotkey"); onChange?() }
    func setModel(_ value: CommandModel) throws {
        var value = value
        value.baseURL = value.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = value.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.origin != nil else { throw CommandSettingsError.address }
        guard value.extraSettings != nil else { throw CommandSettingsError.extra }
        value.contextWindow = max(0, value.contextWindow)
        model = value; remembered[value.endpoint] = value
        defaults.set(value.endpoint, forKey: "commandEndpoint")
        defaults.set(try? JSONEncoder().encode(remembered), forKey: "commandModels")
        onChange?()
    }
    func setKernelMode(_ value: CommandKernelMode) { kernelMode = value; defaults.set(value.rawValue, forKey: "commandKernelMode"); onChange?() }
    func setHarnessModel(_ value: HarnessPlugin.Model?) {
        harnessModel = value; defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: "commandHarnessModel"); onChange?()
    }
    func setHarnessReasoning(_ value: ModelRoute.Reasoning) { harnessReasoning = value; defaults.set(value.rawValue, forKey: "commandHarnessReasoning"); onChange?() }
    func setHarnessUnverified(_ value: Bool) { harnessUnverified = value; defaults.set(value, forKey: "commandHarnessUnverified"); onChange?() }
    func setPermission(_ value: PermissionMode) { permission = value; defaults.set(value.rawValue, forKey: "commandPermission"); onChange?() }
    func setHistoryMinutes(_ value: Int) { historyMinutes = max(0, value); defaults.set(historyMinutes, forKey: "commandHistoryMinutes"); onChange?() }
    func setTimeLimit(_ value: Int) { timeLimit = max(30, value); defaults.set(timeLimit, forKey: "commandTimeLimit"); onChange?() }
    func setStepLimit(_ value: Int) { stepLimit = max(4, value); defaults.set(stepLimit, forKey: "commandStepLimit"); onChange?() }
    func setInstructions(_ value: String) {
        instructions = value.trimmingCharacters(in: .whitespacesAndNewlines); defaults.set(instructions, forKey: "commandInstructions"); onChange?()
    }

    func saveKey(_ key: String) throws {
        guard let account = account(model) else { throw CommandSettingsError.address }
        try credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account); objectWillChange.send(); onChange?()
    }
    func removeKey() throws {
        guard let account = account(model) else { return }
        try credentials.remove(account: account); objectWillChange.send(); onChange?()
    }
    func readKey(for model: CommandModel) async -> String? {
        guard let account = account(model) else { return nil }
        return (try? await credentials.readAsync(account: account)) ?? nil
    }
    /// The model as the built-in kernel is told about it, with its key. nil until enough is set.
    func route() async -> ModelRoute? {
        guard kernelMode == .builtIn, usable else { return nil }
        return ModelRoute(wire: model.wire, baseURL: model.baseURL, model: model.model, key: await readKey(for: model),
                          contextWindow: model.contextWindow > 0 ? model.contextWindow : nil, reasoning: model.reasoning,
                          extra: model.extraSettings ?? [:])
    }
}
