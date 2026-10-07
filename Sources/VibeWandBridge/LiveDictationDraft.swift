import Foundation
import AppKit
import ApplicationServices

struct DictationFieldState: Equatable {
    var value: String
    var selection: NSRange
}

protocol DictationEditableField: AnyObject {
    func read() -> DictationFieldState?
    func replace(_ range: NSRange, with text: String, expectedValue: String) -> Bool
    func finishWrite(confirmed: Bool)
}
extension DictationEditableField { func finishWrite(confirmed: Bool) {} }

enum DictationDraftWrite { case applied, pending, conflict, unavailable }

/// Own only the original selection. Full-field comparisons prevent ASR
/// revisions and polishing from overwriting manual edits or another draft.
final class LiveDictationDraft {
    private let field: any DictationEditableField
    private let original: DictationFieldState
    private(set) var written = ""
    private var applied = false
    private struct PendingWrite {
        var before: DictationFieldState
        var range: NSRange
        var replacement: String
        var text: String
        var value: String
        var selection: NSRange
        var started: TimeInterval
    }
    private var pending: PendingWrite?
    private let now: () -> TimeInterval
    private let settlementTimeout: TimeInterval
    private(set) var failureReason = ""
    var hasWritten: Bool { !written.isEmpty }
    var ownsWrite: Bool { applied || pending != nil }
    init?(field: any DictationEditableField, settlementTimeout: TimeInterval = 1.5,
          now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        guard let original = field.read(), original.selection.location != NSNotFound,
              original.selection.location >= 0, original.selection.length >= 0,
              original.selection.location <= original.value.utf16.count,
              original.selection.length <= original.value.utf16.count - original.selection.location else { return nil }
        self.field = field; self.original = original
        self.now = now; self.settlementTimeout = settlementTimeout
    }
    deinit { field.finishWrite(confirmed: false) }
    private var ownedRange: NSRange {
        NSRange(location: original.selection.location, length: applied ? written.utf16.count : original.selection.length)
    }
    private var expectedValue: String {
        if !applied { return original.value }
        return (original.value as NSString).replacingCharacters(in: original.selection, with: written)
    }
    func update(_ text: String) -> DictationDraftWrite {
        guard text.utf16.count <= 16000, let current = field.read() else { failureReason = "field-unreadable"; return .unavailable }
        if let pending {
            let result = settle(pending, current: current)
            guard result == .applied else { return result }
        }
        guard current.value == expectedValue else {
            failureReason = "value-changed"; return .conflict
        }
        let expectedSelection = !applied ? original.selection : NSRange(location: original.selection.location + written.utf16.count, length: 0)
        guard current.selection == expectedSelection else { failureReason = "selection-changed"; return .conflict }
        if text == written { return .applied }
        // Grow the preview by inserting its new suffix. Only an ASR revision or
        // polishing replaces an existing tail, rather than retyping all words.
        let prefix = applied ? Self.commonPrefix(written, text) : ""
        let range = applied ? NSRange(location: original.selection.location + prefix.utf16.count,
            length: written.utf16.count - prefix.utf16.count) : original.selection
        let replacement = String(text.dropFirst(prefix.count))
        let nextValue = (original.value as NSString).replacingCharacters(in: original.selection, with: text)
        guard field.replace(range, with: replacement, expectedValue: nextValue) else { failureReason = "replace-unavailable"; return .unavailable }
        let write = PendingWrite(before: current, range: range, replacement: replacement, text: text,
            value: nextValue, selection: NSRange(location: original.selection.location + text.utf16.count, length: 0), started: now())
        pending = write
        guard let updated = field.read() else { return .pending }
        return settle(write, current: updated)
    }
    private func settle(_ write: PendingWrite, current: DictationFieldState) -> DictationDraftWrite {
        if current.value == write.value, current.selection == write.selection {
            written = write.text; applied = true; pending = nil; field.finishWrite(confirmed: true); return .applied
        }
        let elapsed = now() - write.started
        if elapsed < settlementTimeout {
            if current.value == write.value || current.value == write.before.value { return .pending }
            // A browser may expose character-by-character progress while a
            // paste/AX write is still settling. Only our replacement can vary.
            let base = write.before.value as NSString
            let prefix = base.substring(to: write.range.location)
            let suffix = base.substring(from: NSMaxRange(write.range))
            if current.value.hasPrefix(prefix), current.value.hasSuffix(suffix),
               current.value.utf16.count >= prefix.utf16.count + suffix.utf16.count {
                let length = current.value.utf16.count - prefix.utf16.count - suffix.utf16.count
                let middle = (current.value as NSString).substring(with: NSRange(location: prefix.utf16.count, length: length))
                if write.replacement.hasPrefix(middle) { return .pending }
            }
        }
        field.finishWrite(confirmed: false); pending = nil
        failureReason = current.value == write.value ? "selection-unconfirmed" :
            (elapsed >= settlementTimeout && current.value == write.before.value ? "write-unconfirmed" : "value-changed")
        return .conflict
    }
    private static func commonPrefix(_ a: String, _ b: String) -> String {
        String(zip(a, b).prefix { $0.0 == $0.1 }.map { $0.0 })
    }
    func rollback() -> Bool {
        if let pending {
            guard let current = field.read(), settle(pending, current: current) == .applied else { field.finishWrite(confirmed: false); return false }
        }
        guard applied, let current = field.read(), current.value == expectedValue,
              current.selection == NSRange(location: original.selection.location + written.utf16.count, length: 0) else { return false }
        let selected = (original.value as NSString).substring(with: original.selection)
        let restored = field.replace(ownedRange, with: selected, expectedValue: original.value)
        if restored { written = ""; applied = false }
        field.finishWrite(confirmed: false)
        return restored
    }
}

/// Small AX surface behind the draft policy; no recognizer or settings logic.
/// It writes through accessibility only: no key events and no clipboard, so a
/// field that ignores the write is simply left untouched.
final class AccessibilityDictationField: DictationEditableField {
    private let element: AXUIElement
    private let pid: pid_t
    init(element: AXUIElement, pid: pid_t) {
        self.element = element; self.pid = pid
        AXUIElementSetMessagingTimeout(element, 0.08)
    }
    private func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func settable(_ name: String) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }
    func read() -> DictationFieldState? {
        guard let text = attribute(kAXValueAttribute) as? String, let selection = attribute(kAXSelectedTextRangeAttribute),
              CFGetTypeID(selection) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(selection, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0,
              text.utf16.count <= 1_000_000 else { return nil }
        return DictationFieldState(value: text, selection: NSRange(location: range.location, length: range.length))
    }
    func replace(_ range: NSRange, with text: String, expectedValue: String) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              settable(kAXSelectedTextRangeAttribute), settable(kAXSelectedTextAttribute) else { return false }
        var selected = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &selected),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        setCaret(range.location + text.utf16.count)
        return true
    }
    private func setCaret(_ location: Int) {
        var range = CFRange(location: location, length: 0)
        if let value = AXValueCreate(.cfRange, &range) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }
}

enum UnicodeTextDelivery {
    static func safeCharacters(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\t", with: " ")
    }
    static func post(_ text: String, pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        var chunks: [String] = [], chunk = ""
        for character in safeCharacters(text) {
            if chunk.utf16.count + String(character).utf16.count > 20, !chunk.isEmpty { chunks.append(chunk); chunk = "" }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        for chunk in chunks {
            let units = Array(chunk.utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
                event.flags = []; event.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
                event.postToPid(pid)
            }
        }
    }
}
