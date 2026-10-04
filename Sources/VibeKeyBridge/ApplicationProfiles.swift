import Foundation
import CoreGraphics

/// App identity is an allowlist, never a match against a window title or website.
/// `generic` deliberately receives no synthesized input.
enum ApplicationProfile: String, CaseIterable, Codable {
    case codex, claude, deepSeekHarness, browser, weChat, feishu, generic
    case customChat, customBrowser, custom

    static func resolve(bundleID: String?) -> ApplicationProfile {
        switch bundleID {
        case "com.openai.codex": return .codex
        case "com.anthropic.claudefordesktop": return .claude
        case "com.deepseek.dsh": return .deepSeekHarness
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview",
             "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
             "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox",
             "org.mozilla.firefoxdeveloperedition", "com.operasoftware.Opera", "com.vivaldi.Vivaldi": return .browser
        case "com.tencent.xinWeChat", "com.tencent.WeChat": return .weChat
        case "com.electron.lark", "com.bytedance.Lark", "com.larksuite.Lark": return .feishu
        default: return .generic
        }
    }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .deepSeekHarness: return "DeepSeek Harness"
        case .browser: return L10n.tr("浏览器", "Browser")
        case .weChat: return L10n.tr("微信", "WeChat")
        case .feishu: return L10n.tr("飞书 / Lark", "Feishu / Lark")
        case .generic: return L10n.tr("未适配应用", "Unsupported app")
        case .customChat: return L10n.tr("聊天工具", "Chat app")
        case .customBrowser: return L10n.tr("浏览器", "Browser")
        case .custom: return L10n.tr("自定义应用", "Custom app")
        }
    }

    var supportsAssistantPickers: Bool { self == .codex || self == .claude || self == .deepSeekHarness }
    var isMessaging: Bool { self == .weChat || self == .feishu || self == .customChat }
    var alwaysScrolls: Bool { self == .browser || self == .customBrowser }
    var isCustom: Bool { [.customChat, .customBrowser, .custom].contains(self) }
    var expectsSessionPicker: Bool { supportsAssistantPickers || isMessaging }

    var summary: String {
        switch self {
        case .codex: return L10n.tr("会话、模型与推理强度选择；草稿光标与阅读滚动。", "Chat, model and reasoning pickers; draft cursor movement and scrolling.")
        case .claude: return L10n.tr("⌘K 搜索会话；直接操作输入框旁的模型与强度按钮。", "⌘K searches chats; the model and effort buttons beside the composer are pressed directly.")
        case .deepSeekHarness: return L10n.tr("⌘K 搜索会话；按可访问性标签打开模型与推理等级菜单。", "⌘K searches chats; accessibility labels open model and reasoning menus.")
        case .browser: return L10n.tr("旋转滚动网页；单按切换下个标签页；设置键定位地址栏。", "Turn to scroll; press to switch to the next tab; the model action focuses the address bar.")
        case .weChat: return L10n.tr("⌘F 搜索聊天；旋转浏览结果或滚动；草稿中移动光标。", "⌘F searches chats; turn to browse results, scroll, or move the draft cursor.")
        case .feishu: return L10n.tr("⌘K 快速搜索；旋转浏览结果或滚动；草稿中移动光标。", "⌘K opens quick search; turn to browse results, scroll, or move the draft cursor.")
        case .generic: return L10n.tr("不发送应用操作；仍可使用应用切换器。", "App actions are disabled; the system app switcher remains available.")
        case .customChat: return L10n.tr("聊天搜索、候选导航和草稿编辑；快捷键由你设置。", "Chat search, result navigation and draft editing with your shortcuts.")
        case .customBrowser: return L10n.tr("始终滚动网页；标签页和地址栏快捷键由你设置。", "Always scroll pages; configure tab and address bar shortcuts.")
        case .custom: return L10n.tr("按应用单独设置快捷键；仅匹配指定的应用。", "Configure shortcuts for one explicitly selected app.")
        }
    }

    var verification: String {
        switch self {
        case .codex: return L10n.tr("原生选择器识别", "Native picker recognition")
        case .claude: return L10n.tr("已在本机 Claude 桌面版实测听写、会话搜索与模型菜单", "Dictation, chat search and the model menu were exercised on the local Claude desktop app")
        case .deepSeekHarness: return L10n.tr("已核对本机 0.2.0-rc.2 代码和会话 / 模型界面", "Checked against local 0.2.0-rc.2 code and chat / model interfaces")
        case .browser: return L10n.tr("系统标准快捷键；标签页顺序取决于浏览器设置", "Standard shortcuts; tab order follows your browser settings")
        case .weChat: return L10n.tr("⌘F 兼容映射；本机微信未提供可读的聊天控件", "⌘F compatibility mapping; local WeChat chat controls were not accessible")
        case .feishu: return L10n.tr("已核对本机 ⌘K 搜索界面；Enter 沿用飞书发送设置", "Local ⌘K search verified; Enter follows Feishu send settings")
        case .generic: return L10n.tr("未启用", "Disabled")
        case .customChat, .customBrowser, .custom: return L10n.tr("使用你的快捷键配置", "Uses your shortcut configuration")
        }
    }

    var primaryShortcut: KeyStroke? {
        switch self {
        case .codex, .claude, .deepSeekHarness, .feishu: return KeyStroke(code: 40, flags: .maskCommand) // K
        case .browser: return KeyStroke(code: 48, flags: .maskControl) // Tab
        case .weChat: return KeyStroke(code: 3, flags: .maskCommand) // F
        case .generic, .customChat, .customBrowser, .custom: return nil
        }
    }

    var secondaryShortcut: KeyStroke? {
        switch self {
        case .codex: return KeyStroke(code: 46, flags: [.maskControl, .maskShift])
        case .browser: return KeyStroke(code: 37, flags: .maskCommand) // L
        case .weChat, .feishu: return primaryShortcut
        case .claude, .deepSeekHarness, .generic, .customChat, .customBrowser, .custom: return nil
        }
    }

    /// Harness filters its sidebar instead of offering a keyboard-driven
    /// switcher, so its chats are chosen from the sidebar list itself.
    var picksSessionsFromSidebar: Bool { self == .deepSeekHarness }

    static func isSessionList(role: String, hint: String) -> Bool {
        guard ["AXOutline", "AXList", "AXTable"].contains(role) else { return false }
        let text = hint.lowercased()
        return ["会话", "session", "chat", "conversation"].contains { text.contains($0) }
    }

    /// These apps have no model shortcut; their composer exposes a labelled
    /// button instead, which is pressed through accessibility.
    var opensModelsWithButton: Bool { self == .codex || self == .claude || self == .deepSeekHarness }

    func isModelTrigger(role: String, hint: String) -> Bool {
        guard ["AXButton", "AXPopUpButton", "AXMenuButton"].contains(role) else { return false }
        let text = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .deepSeekHarness: return Self.isHarnessModelTrigger(role: role, hint: hint)
        case .codex: return Self.isCodexModelTrigger(hint: text)
        case .claude: return text.hasPrefix("model:") || text.hasPrefix("model ") || text.hasPrefix("模型：") || text.hasPrefix("模型:") || text == "model selector"
        default: return false
        }
    }

    /// Claude keeps reasoning effort in its own menu next to the model menu.
    func isEffortTrigger(role: String, hint: String) -> Bool {
        guard self == .claude, ["AXButton", "AXPopUpButton", "AXMenuButton"].contains(role) else { return false }
        let text = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.hasPrefix("effort:") || text.hasPrefix("effort ") || text.hasPrefix("强度：") || text.hasPrefix("推理强度")
    }

    func title(for effect: BridgeEffect) -> String {
        switch effect {
        case .openSessions:
            if alwaysScrolls { return L10n.tr("下一个浏览器标签页", "Next browser tab") }
            if isMessaging { return L10n.tr("搜索 / 切换聊天", "Search / switch chats") }
            if self == .custom { return L10n.tr("应用主操作", "Primary app action") }
        case .openModels:
            if alwaysScrolls { return L10n.tr("定位浏览器地址栏", "Focus browser address bar") }
            if isMessaging { return L10n.tr("搜索聊天", "Search chats") }
            if self == .custom { return L10n.tr("应用辅助操作", "Secondary app action") }
        default: break
        }
        return effect.title
    }

    func pickerKind(_ hint: String, focusedSearch: Bool = false) -> InteractionMode? {
        if supportsAssistantPickers { return AccessibilityHints.pickerKind(hint) }
        guard isMessaging else { return nil }
        if AccessibilityHints.pickerKind(hint) == .sessions { return .sessions }
        let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if self == .feishu, normalized.contains("search-command-bar") { return .sessions }
        // Only an actual text/search control in these native messaging apps may
        // turn their ordinary global search into up/down/confirm navigation.
        if focusedSearch, ["search", "搜索", "快速搜索", "快速切换", "quick switcher", "quick search"].contains(normalized) {
            return .sessions
        }
        return nil
    }

    /// Codex labels its model button with the model itself, e.g. "GPT-6.1 Sol High".
    static func isCodexModelTrigger(hint text: String) -> Bool {
        if text.contains("model") || text.contains("模型") { return true }
        let families = ["gpt", "codex", "chatgpt", "o1", "o3", "o4", "o5"]
        let efforts = [" minimal", " low", " medium", " high", " xhigh", " extra high", " max"]
        return families.contains { text.hasPrefix($0) } && (efforts.contains { text.hasSuffix($0) } || text.contains("-") || text.contains("."))
    }

    static func isHarnessModelTrigger(role: String, hint: String) -> Bool {
        guard ["AXButton", "AXPopUpButton", "AXMenuButton"].contains(role) else { return false }
        let text = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text == "select model" || text == "请选择模型" ||
            text.contains("select model, current ") || text.contains("选择模型，当前 ")
    }
}
