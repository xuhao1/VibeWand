import AppKit
import SpeechInput

/// The keyboard's command key: a right-hand modifier held on its own.
enum CommandHotkey: String, CaseIterable {
    case none, rightOption, rightCommand, rightControl, rightShift
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

/// Command mode preferences. The mode is off until the user turns it on, because
/// turning it on is what lets instructions and window titles leave this Mac for
/// the model they configured. The model key lives in the Keychain, apart from speech keys.
@MainActor
final class CommandSettings: ObservableObject {
    nonisolated static let service = "org.vibekey.bridge.command-model"
    private static let account = "deepseek-official"
    private let defaults: UserDefaults
    private let credentials: any SpeechCredentialStore
    @Published private(set) var enabled: Bool
    @Published private(set) var hotkey: CommandHotkey
    @Published private(set) var model: String
    /// Asked of the Keychain when needed, so merely starting the app does not touch it.
    var keySaved: Bool { credentials.contains(account: Self.account) }
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         credentials: any SpeechCredentialStore = KeychainSpeechCredentials(service: CommandSettings.service)) {
        self.defaults = defaults; self.credentials = credentials
        enabled = defaults.bool(forKey: "commandModeEnabled")
        hotkey = defaults.string(forKey: "commandHotkey").flatMap(CommandHotkey.init(rawValue:)) ?? .rightOption
        model = defaults.string(forKey: "commandModel") ?? ""
    }

    func setEnabled(_ value: Bool) { enabled = value; defaults.set(value, forKey: "commandModeEnabled"); onChange?() }
    func setHotkey(_ value: CommandHotkey) { hotkey = value; defaults.set(value.rawValue, forKey: "commandHotkey"); onChange?() }
    func setModel(_ value: String) {
        model = value.trimmingCharacters(in: .whitespacesAndNewlines); defaults.set(model, forKey: "commandModel"); onChange?()
    }
    func saveKey(_ key: String) throws { try credentials.save(key, account: Self.account); objectWillChange.send(); onChange?() }
    func removeKey() throws { try credentials.remove(account: Self.account); objectWillChange.send(); onChange?() }
    func readKey() async -> String? { (try? await credentials.readAsync(account: Self.account)) ?? nil }
}
