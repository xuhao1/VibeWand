import Foundation
import CoreGraphics

enum ApplicationTemplate: String, CaseIterable, Codable, Identifiable {
    case chat, browser, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: return L10n.tr("聊天工具", "Chat app")
        case .browser: return L10n.tr("浏览器", "Browser")
        case .custom: return L10n.tr("自定义", "Custom")
        }
    }
    var profile: ApplicationProfile {
        switch self {
        case .chat: return .customChat
        case .browser: return .customBrowser
        case .custom: return .custom
        }
    }
    var summary: String { profile.summary }
    var defaultShortcuts: [ApplicationCommand: ApplicationShortcut] {
        var result: [ApplicationCommand: ApplicationShortcut] = [
            .confirm: .init(key: .returnKey), .cancel: .init(key: .escape),
            .previous: .init(key: .up), .next: .init(key: .down),
            .cursorLeft: .init(key: .left), .cursorRight: .init(key: .right),
            .deleteBackward: .init(key: .backspace)
        ]
        switch self {
        case .chat:
            result[.primary] = .init(key: .k, command: true)
            result[.secondary] = .init(key: .k, command: true)
        case .browser:
            result[.primary] = .init(key: .tab, control: true)
            result[.secondary] = .init(key: .l, command: true)
        case .custom: break
        }
        return result
    }
}

enum ApplicationCommand: String, CaseIterable, Codable, Identifiable {
    case primary, secondary, confirm, cancel, previous, next, cursorLeft, cursorRight, deleteBackward
    case scrollUp, scrollDown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .primary: return L10n.tr("主操作 · 会话 / 标签页", "Primary · chats / tabs")
        case .secondary: return L10n.tr("辅助操作 · 搜索 / 地址栏", "Secondary · search / address bar")
        case .confirm: return L10n.tr("确认 / Enter", "Confirm / Enter")
        case .cancel: return L10n.tr("返回 / Escape", "Back / Escape")
        case .previous: return L10n.tr("上一个候选", "Previous result")
        case .next: return L10n.tr("下一个候选", "Next result")
        case .cursorLeft: return L10n.tr("光标向左", "Move cursor left")
        case .cursorRight: return L10n.tr("光标向右", "Move cursor right")
        case .deleteBackward: return L10n.tr("删除字符", "Delete backward")
        case .scrollUp: return L10n.tr("向上滚动", "Scroll up")
        case .scrollDown: return L10n.tr("向下滚动", "Scroll down")
        }
    }
    var emptyLabel: String {
        isScroll ? L10n.tr("系统滚屏", "Native scroll") : L10n.tr("不执行", "Unassigned")
    }
    var isScroll: Bool { self == .scrollUp || self == .scrollDown }
    static func forEffect(_ effect: BridgeEffect) -> ApplicationCommand? {
        switch effect {
        case .openSessions: return .primary
        case .openModels: return .secondary
        case .sendReturn, .confirmCandidate: return .confirm
        case .sendEscape, .cancelPicker: return .cancel
        case .moveCandidate(let direction): return direction < 0 ? .previous : .next
        case .moveCursor(let direction): return direction < 0 ? .cursorLeft : .cursorRight
        case .deleteBackward: return .deleteBackward
        case .scroll(let direction): return direction < 0 ? .scrollUp : .scrollDown
        case .none: return nil
        }
    }
}

/// A finite set of physical Mac keys. No shell commands, scripts or key strings
/// from an app are executed; a configured shortcut is exactly one key chord.
enum ApplicationKey: String, CaseIterable, Codable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero, one, two, three, four, five, six, seven, eight, nine
    case minus, equals, leftBracket, rightBracket, backslash, semicolon, quote, comma, period, slash, grave
    case returnKey, escape, tab, space, backspace, forwardDelete, left, right, up, down, home, end, pageUp, pageDown
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    var id: String { rawValue }
    var title: String {
        switch self {
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .minus: return "−"
        case .equals: return "="
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .backslash: return "\\"
        case .semicolon: return ";"
        case .quote: return "'"
        case .comma: return ","
        case .period: return "."
        case .slash: return "/"
        case .grave: return "`"
        case .returnKey: return "Return"
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .space: return "Space"
        case .backspace: return "Backspace"
        case .forwardDelete: return "Delete"
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        default: return rawValue.uppercased()
        }
    }
    var keyCode: CGKeyCode {
        switch self {
        case .a: return 0; case .s: return 1; case .d: return 2; case .f: return 3
        case .h: return 4; case .g: return 5; case .z: return 6; case .x: return 7
        case .c: return 8; case .v: return 9; case .b: return 11; case .q: return 12
        case .w: return 13; case .e: return 14; case .r: return 15; case .y: return 16
        case .t: return 17; case .one: return 18; case .two: return 19; case .three: return 20
        case .four: return 21; case .six: return 22; case .five: return 23; case .nine: return 25
        case .seven: return 26; case .eight: return 28; case .zero: return 29; case .o: return 31
        case .equals: return 24; case .minus: return 27; case .rightBracket: return 30
        case .leftBracket: return 33; case .quote: return 39; case .semicolon: return 41
        case .backslash: return 42; case .comma: return 43; case .slash: return 44
        case .period: return 47; case .grave: return 50
        case .u: return 32; case .i: return 34; case .p: return 35; case .returnKey: return 36
        case .l: return 37; case .j: return 38; case .k: return 40; case .n: return 45
        case .m: return 46; case .tab: return 48; case .space: return 49; case .backspace: return 51
        case .escape: return 53; case .f1: return 122; case .f2: return 120; case .f3: return 99
        case .f4: return 118; case .f5: return 96; case .f6: return 97; case .f7: return 98
        case .f8: return 100; case .f9: return 101; case .f10: return 109; case .f11: return 103
        case .f12: return 111; case .home: return 115; case .pageUp: return 116
        case .forwardDelete: return 117; case .end: return 119; case .pageDown: return 121
        case .left: return 123; case .right: return 124; case .down: return 125; case .up: return 126
        }
    }
}

struct ApplicationShortcut: Codable, Equatable {
    var key: ApplicationKey
    var command = false
    var option = false
    var control = false
    var shift = false

    var stroke: KeyStroke {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift { flags.insert(.maskShift) }
        return KeyStroke(code: key.keyCode, flags: flags)
    }
    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.title
    }
}

struct CustomApplicationProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var bundleID: String
    var template: ApplicationTemplate
    var enabled: Bool
    var shortcuts: [ApplicationCommand: ApplicationShortcut]

    init(id: UUID = UUID(), name: String = "", bundleID: String = "", template: ApplicationTemplate = .chat, enabled: Bool = true) {
        self.id = id; self.name = name; self.bundleID = bundleID
        self.template = template; self.enabled = enabled
        shortcuts = template.defaultShortcuts
    }

    mutating func applyTemplate(_ template: ApplicationTemplate) {
        self.template = template
        shortcuts = template.defaultShortcuts
    }

    func shortcut(for effect: BridgeEffect) -> ApplicationShortcut? {
        ApplicationCommand.forEffect(effect).flatMap { shortcuts[$0] }
    }

    func validated() throws -> CustomApplicationProfile {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.count <= 80 else { throw CustomApplicationError.invalidName }
        guard result.bundleID.count <= 200,
              result.bundleID.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#, options: .regularExpression) != nil else {
            throw CustomApplicationError.invalidBundleID
        }
        return result
    }
}

enum CustomApplicationError: LocalizedError {
    case invalidName, invalidBundleID, duplicateBundleID, tooManyProfiles
    var errorDescription: String? {
        switch self {
        case .invalidName: return L10n.tr("请输入 1–80 个字符的应用名称。", "Enter an app name with 1–80 characters.")
        case .invalidBundleID: return L10n.tr("请选择应用，或填写完整应用标识，例如 com.example.app。", "Choose an app, or enter its full bundle ID, such as com.example.app.")
        case .duplicateBundleID: return L10n.tr("这个应用已经有自定义配置，请编辑已有配置。", "This app already has a custom profile. Edit that profile instead.")
        case .tooManyProfiles: return L10n.tr("最多可保存 64 个自定义应用。", "You can save up to 64 custom apps.")
        }
    }
}

/// A profile is an explicit per-app allowlist entry. Disabled custom entries
/// intentionally shadow built-in profiles for that exact bundle ID.
final class CustomApplicationProfileStore {
    static let storageKey = "vibeWand.customApplicationProfiles.v1"
    private let preferences: UserDefaults
    private(set) var profiles: [CustomApplicationProfile]

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        var seen = Set<String>()
        profiles = (preferences.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([CustomApplicationProfile].self, from: $0) } ?? [])
            .prefix(64).compactMap { try? $0.validated() }
            .filter { seen.insert($0.bundleID).inserted }
    }

    func profile(bundleID: String?) -> CustomApplicationProfile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }
    }

    func save(_ profile: CustomApplicationProfile) throws {
        let validated = try profile.validated()
        guard !profiles.contains(where: { $0.id != validated.id && $0.bundleID == validated.bundleID }) else {
            throw CustomApplicationError.duplicateBundleID
        }
        if let index = profiles.firstIndex(where: { $0.id == validated.id }) { profiles[index] = validated }
        else {
            guard profiles.count < 64 else { throw CustomApplicationError.tooManyProfiles }
            profiles.append(validated)
        }
        persist()
    }

    func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].enabled = enabled
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { preferences.set(data, forKey: Self.storageKey) }
    }
}
