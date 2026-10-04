import AppKit
import ApplicationServices

enum TextInsertionMethod: String, CaseIterable, Codable {
    case automatic, paste, keystrokes
    var title: String {
        switch self {
        case .automatic: return L10n.tr("自动（推荐）", "Automatic (recommended)")
        case .paste: return L10n.tr("始终粘贴", "Always paste")
        case .keystrokes: return L10n.tr("模拟键入", "Simulated typing")
        }
    }
}

enum TextInsertionOutcome: Equatable {
    /// `verified` means the field's value was read back and contains the change.
    case inserted(via: String, verified: Bool)
    case failed
}

/// Places a finished transcript at the caret of whatever the user is typing
/// into. Native fields take an accessibility write; everything else gets one
/// paste, the same edit a person would make, with the clipboard put back.
@MainActor
final class TextInserter {
    static let methodKey = "dictationInsertionMethod"
    /// Apps whose fields ignored an accessibility write. Remembered until quit
    /// so a second dictation does not pay for the same failed attempt.
    private(set) static var pasteOnlyApps: Set<String> = []
    static func supportsDirectWrites(_ bundleID: String) -> Bool {
        method == .automatic && !pasteOnlyApps.contains(bundleID)
    }
    static func markPasteOnly(_ bundleID: String) { if !bundleID.isEmpty { pasteOnlyApps.insert(bundleID) } }
    static var method: TextInsertionMethod {
        get { UserDefaults.standard.string(forKey: methodKey).flatMap(TextInsertionMethod.init(rawValue:)) ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: methodKey) }
    }

    private var clipboard: ClipboardTextDelivery?
    private var generation = 0

    func cancel() { generation += 1; clipboard?.restore(confirmed: true); clipboard = nil }

    func insert(_ text: String, pid: pid_t, bundleID: String, editor: AXUIElement?,
                completion: @escaping (TextInsertionOutcome) -> Void) {
        generation += 1
        let token = generation
        guard !text.isEmpty, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { completion(.failed); return }
        let field = editor.map { AccessibilityDictationField(element: $0, pid: pid) }
        let before = field?.read()
        if Self.method == .keystrokes {
            UnicodeTextDelivery.post(text, pid: pid)
            confirm(field, before: before, text: text, timeout: 1, token: token) { completion(.inserted(via: "keystrokes", verified: $0)) }
            return
        }
        if let field, let before, Self.supportsDirectWrites(bundleID) {
            let expected = (before.value as NSString).replacingCharacters(in: before.selection, with: text)
            if field.replace(before.selection, with: text, expectedValue: expected) {
                confirm(field, before: before, text: text, timeout: 0.35, token: token) { [weak self] written in
                    guard let self, token == self.generation else { return }
                    if written { completion(.inserted(via: "accessibility", verified: true)); return }
                    Self.markPasteOnly(bundleID)
                    self.paste(text, pid: pid, field: field, before: before, token: token, completion: completion)
                }
                return
            }
            Self.markPasteOnly(bundleID)
        }
        paste(text, pid: pid, field: field, before: before, token: token, completion: completion)
    }

    private func paste(_ text: String, pid: pid_t, field: AccessibilityDictationField?, before: DictationFieldState?,
                       token: Int, completion: @escaping (TextInsertionOutcome) -> Void) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { completion(.failed); return }
        let delivery = ClipboardTextDelivery(); clipboard = delivery
        delivery.post(text, pid: pid)
        // An unreadable field cannot be confirmed; give the app time to read the clipboard.
        confirm(field, before: before, text: text, timeout: before == nil ? 0.45 : 1.2, token: token) { [weak self] written in
            delivery.restore(confirmed: true)
            if self?.clipboard === delivery { self?.clipboard = nil }
            completion(.inserted(via: "paste", verified: written))
        }
    }

    /// Polls the field until its value shows the inserted text, or time runs out.
    private func confirm(_ field: AccessibilityDictationField?, before: DictationFieldState?, text: String,
                         timeout: TimeInterval, token: Int, completion: @escaping (Bool) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        func check() {
            guard token == generation else { return }
            // Editors may normalise line breaks, so match on the opening words only.
            let opening = String((text.split(whereSeparator: \.isNewline).first ?? "").prefix(12))
            if let field, let before, let now = field.read(), now.value != before.value, now.value.contains(opening) {
                completion(true); return
            }
            if ProcessInfo.processInfo.systemUptime >= deadline { completion(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { MainActor.assumeIsolated { check() } }
        }
        check()
    }
}
