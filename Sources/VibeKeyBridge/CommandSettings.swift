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
    /// The one VibeWand ships, with the model set up on its page.
    case builtIn
    /// One the user installed, running VibeWand's coordinator as a plugin: its models, its sign-ins, its session list.
    case harness
    /// VibeWand's own folder for the harness of this mode. For the shipped one it is the harness's home.
    var folder: String { self == .harness ? "harness" : "kernel" }
}

/// The conversation the next command may carry on: the runtime's name for it and how far it has got.
struct CommandConversation: Codable, Equatable {
    var session: String
    /// When its latest command ended.
    var last: Date
    var turns: Int
    var used: Int?
    var size: Int?
    var usage: (used: Int, size: Int)? { if let used, let size, size > 0 { return (used, size) } else { return nil } }
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
        case .ask: return L10n.tr("切换应用、打开会话、按下或点击控件、发送按键、输入文字，每一步都先显示要做什么，等你按确认键。读取界面和查找不用确认。",
                                  "Switching apps, opening a chat, pressing or clicking a control, sending keys and typing each show what is about to happen and wait for your confirm key. Reading and searching do not.")
        case .risky: return L10n.tr("导航和输入直接执行。删除、发送、提交这类控件、按键和点击，每次等你按确认键。",
                                    "Navigation and typing run at once. Controls, keys and clicks that delete, send or submit wait for your confirm key every time.")
        case .bypass: return L10n.tr("什么都不问，包括删除、发送和提交。模型认错控件或听错话时，这些操作也会直接执行。",
                                     "Nothing is asked, deleting, sending and submitting included. When the model picks the wrong control or mishears you, those happen too.")
        }
    }
    /// What the mode means for a harness's own tools, which run inside the harness's sandbox.
    var harnessSummary: String {
        switch self {
        case .ask: return L10n.tr("Harness 自己的工具按“只读”运行：读文件、查资料直接做，写文件或改动系统的每一步都先问你。",
                                  "The harness's own tools run read-only: reading and looking things up go ahead; every step that writes a file or changes the system asks you first.")
        case .risky: return L10n.tr("Harness 自己的工具按“工作区可写”运行：只能写 VibeWand 的临时目录，写到别处或需要更大权限的命令先问你。",
                                    "The harness's own tools run workspace-write: they may write only to VibeWand's scratch folder; writing elsewhere, or a command that needs more, asks you first.")
        case .bypass: return L10n.tr("Harness 自己的工具按“完全访问”运行：命令和文件改动都直接执行，不问。",
                                     "The harness's own tools run with full access: commands and file changes go ahead unasked.")
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
    /// Minutes without a command after which the next one starts a new conversation. 0 starts every command afresh;
    /// a negative value keeps a conversation until it is nearly full or the user ends it.
    @Published private(set) var historyMinutes: Int
    /// Seconds one command may act for, questions included.
    @Published private(set) var timeLimit: Int
    /// Tool calls one command may make.
    @Published private(set) var stepLimit: Int
    /// The user's own notes for the coordinator, added after its rules.
    @Published private(set) var instructions: String
    @Published private(set) var kernelMode: CommandKernelMode
    /// The model picked for plugin mode. nil follows the default the user's harness is set to.
    @Published private(set) var harnessModel: Harness.Model?
    @Published private(set) var harnessReasoning: ModelRoute.Reasoning
    /// The user chose to run on a harness version the plugin has not been verified with.
    @Published private(set) var harnessUnverified: Bool
    /// How much the model may reach for on an installed harness: VibeWand's tools, or the harness's own as well.
    @Published private(set) var harnessTools: Harness.Tools
    /// The model may ask for a picture of the window it is operating, and click where it points in it.
    /// Off until the user turns it on: what the window shows then leaves this Mac.
    @Published private(set) var sight: Bool
    /// What that switch is called, in Settings and wherever the user is pointed to it.
    nonisolated static var sightTitle: String { L10n.tr("让模型看窗口截图并点击", "Let the model see the window and click in it") }
    private var remembered: [String: CommandModel]
    private let locate: (CommandKernelMode) -> Harness?
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         credentials: any SpeechCredentialStore = KeychainSpeechCredentials(service: CommandSettings.service),
         harness: @escaping (CommandKernelMode) -> Harness? = CommandSettings.locate) {
        self.defaults = defaults; self.credentials = credentials; locate = harness
        kernelMode = defaults.string(forKey: "commandKernelMode").flatMap(CommandKernelMode.init(rawValue:)) ?? .builtIn
        harnessModel = defaults.data(forKey: "commandHarnessModel").flatMap { try? JSONDecoder().decode(Harness.Model.self, from: $0) }
        harnessReasoning = defaults.string(forKey: "commandHarnessReasoning").flatMap(ModelRoute.Reasoning.init(rawValue:)) ?? .automatic
        harnessUnverified = defaults.bool(forKey: "commandHarnessUnverified")
        harnessTools = defaults.string(forKey: "commandHarnessTools").flatMap(Harness.Tools.init(rawValue:)) ?? .own
        sight = defaults.bool(forKey: "commandSight")
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
    /// The harness of a mode, when this Mac and this build have it: the one inside the app, or one the user installed.
    func harness(_ mode: CommandKernelMode) -> Harness? { locate(mode) }
    /// The harness of the mode in force.
    var harness: Harness? { locate(kernelMode) }
    nonisolated static func locate(_ mode: CommandKernelMode) -> Harness? {
        // A direct SwiftPM run has no bundle: the bundles are then the ones in the checkout, and an assembled kernel is named.
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        switch mode {
        case .builtIn:
            let named = ProcessInfo.processInfo.environment["VIBEWAND_KERNEL_RESOURCES"].map(URL.init(fileURLWithPath:))
            return [Bundle.main.resourceURL, named].lazy.compactMap { $0 }.compactMap { Harness.shipped(resources: $0) }.first
        case .harness:
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh")
            return [Bundle.main.resourceURL?.appendingPathComponent("harness"), checkout.appendingPathComponent("kernel")].lazy.compactMap { $0 }
                .compactMap { Harness.installed(desktopApp: app, bundles: $0) }.first
        }
    }
    /// The tools the model is given on the harness in force. The shipped harness has none of its own to add.
    var tools: Harness.Tools { kernelMode == .harness ? harnessTools : .own }
    /// Enough is set to run a command. On the shipped harness: an address, a model, and a key where one is needed.
    /// On an installed one the models and keys are its own, so it is enough that it is there.
    var usable: Bool {
        kernelMode == .harness ? harness != nil : model.origin != nil && !model.model.isEmpty && (model.keyOptional || keySaved)
    }
    /// The model a command runs on, as the overlay names it.
    var modelName: String { kernelMode == .harness ? (harnessModel ?? harness?.defaultModel)?.model ?? "" : model.model }
    /// The command key is live. Until then the device's keys keep what they did without command mode.
    var active: Bool { enabled && usable }
    /// The conversation the next command may carry on, kept across restarts. It is state, not a preference:
    /// writing it notifies nobody.
    var conversation: CommandConversation? {
        get { defaults.data(forKey: "commandConversation").flatMap { try? JSONDecoder().decode(CommandConversation.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "commandConversation") }
    }

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
    func setHarnessModel(_ value: Harness.Model?) {
        harnessModel = value; defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: "commandHarnessModel"); onChange?()
    }
    func setHarnessTools(_ value: Harness.Tools) { harnessTools = value; defaults.set(value.rawValue, forKey: "commandHarnessTools"); onChange?() }
    func setSight(_ value: Bool) { sight = value; defaults.set(value, forKey: "commandSight"); onChange?() }
    func setHarnessReasoning(_ value: ModelRoute.Reasoning) { harnessReasoning = value; defaults.set(value.rawValue, forKey: "commandHarnessReasoning"); onChange?() }
    func setHarnessUnverified(_ value: Bool) { harnessUnverified = value; defaults.set(value, forKey: "commandHarnessUnverified"); onChange?() }
    func setPermission(_ value: PermissionMode) { permission = value; defaults.set(value.rawValue, forKey: "commandPermission"); onChange?() }
    func setHistoryMinutes(_ value: Int) { historyMinutes = max(-1, value); defaults.set(historyMinutes, forKey: "commandHistoryMinutes"); onChange?() }
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
    /// Where the model of the mode in force comes from: the route set up here, with its key, or the harness's own
    /// settings with the model picked from them. nil until enough is set.
    func models() async -> Harness.Models? {
        guard usable else { return nil }
        if kernelMode == .harness { return .harness(harnessModel, reasoning: harnessReasoning) }
        return .route(ModelRoute(wire: model.wire, baseURL: model.baseURL, model: model.model, key: await readKey(for: model),
                                 contextWindow: model.contextWindow > 0 ? model.contextWindow : nil, reasoning: model.reasoning,
                                 images: sight, extra: model.extraSettings ?? [:]))
    }
}
