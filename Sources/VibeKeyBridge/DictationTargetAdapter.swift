import AppKit
import ApplicationServices

/// Dictation follows the keyboard focus in any app. Application navigation
/// profiles remain separate and still gate chat/model/scroll shortcuts. An app
/// that exposes no readable editor still gets an observation (without an
/// `editor`), so the transcript can be pasted at its caret.
@MainActor
final class DictationTargetAdapter {
    private let worker = DispatchQueue(label: "VibeWand.dictation-target", qos: .userInitiated)
    func requestRefresh(_ completion: @escaping (TargetObservation) -> Void) {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { completion(TargetObservation()); return }
        let pid = app.processIdentifier
        worker.async {
            let observation = Self.read(pid: pid)
            DispatchQueue.main.async {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { completion(TargetObservation()); return }
                completion(observation)
            }
        }
    }
    private nonisolated static func read(pid: pid_t) -> TargetObservation {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.03)
        func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        var result = TargetObservation(pid: pid)
        result.sampledAt = Date()
        result.context = InteractionContext(targetAvailable: true, editorFocused: false, modalOpen: false,
            compositionActive: false, picker: nil)
        let window = element(attribute(app, kAXFocusedWindowAttribute))
        result.window = window
        result.identity = TargetIdentity(pid: pid, windowHash: window.map(CFHash) ?? 0, windowTitle: "", focusedHash: 0, focusedIdentifier: "")
        guard let focus = element(attribute(app, kAXFocusedUIElementAttribute)) else { return result }
        result.focused = focus
        var editor: AXUIElement?
        var current: AXUIElement? = focus
        for _ in 0..<8 {
            guard let candidate = current else { break }
            AXUIElementSetMessagingTimeout(candidate, 0.02)
            let role = attribute(candidate, kAXRoleAttribute) as? String ?? ""
            let subrole = attribute(candidate, kAXSubroleAttribute) as? String ?? ""
            if subrole == "AXSecureTextField" { result.secureField = true; return result }
            if ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"].contains(role),
               attribute(candidate, kAXEnabledAttribute) as? Bool != false,
               attribute(candidate, "AXEditable") as? Bool != false {
                editor = candidate; break
            }
            current = element(attribute(candidate, kAXParentAttribute))
        }
        guard let editor else { return result }
        var composing = false
        if let marked = attribute(editor, "AXMarkedTextRange"), CFGetTypeID(marked) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(unsafeBitCast(marked, to: AXValue.self), .cfRange, &range) { composing = range.length > 0 }
        }
        result.editor = editor
        result.identity = TargetIdentity(pid: pid, windowHash: window.map(CFHash) ?? 0,
            windowTitle: window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? "",
            focusedHash: CFHash(editor), focusedIdentifier: attribute(editor, kAXIdentifierAttribute) as? String ?? "")
        result.context = InteractionContext(targetAvailable: true, editorFocused: true, modalOpen: false,
            compositionActive: composing, picker: nil)
        return result
    }
}
