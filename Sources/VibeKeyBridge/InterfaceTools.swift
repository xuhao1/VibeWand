import AppKit
import ApplicationServices
import WandAgent

/// One control from the latest snapshot. Its id is its position in that snapshot.
struct InterfaceControl {
    let element: AXUIElement
    let kind: String
    let label: String
    var state = ""
    var secure = false
}

/// Reads and operates the front window of one app through its accessibility
/// tree, the same structure a screen reader is given. No screenshot is taken
/// and no coordinate is clicked. Field contents and document text are left
/// out: a field is reported as empty or not, never by what it holds.
final class InterfaceTools: @unchecked Sendable {
    static let shownLimit = 150
    private let worker = DispatchQueue(label: "vibewand.interface", qos: .userInitiated)
    // Both are touched on `worker` only.
    private var controls: [InterfaceControl] = []
    private var prepared: Set<pid_t> = []

    func snapshot(pid: pid_t, filter: String?) async -> ToolOutcome {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.4)
            // An Electron app publishes its web content to accessibility only when asked.
            let first = self.prepared.insert(pid).inserted
            if first { AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
            guard let window = Self.element(Self.attribute(application, kAXFocusedWindowAttribute))
                    ?? Self.element(Self.attribute(application, kAXMainWindowAttribute)) else {
                return .failure("This app has no window to read.")
            }
            var found = Self.walk(window)
            if first, found.controls.count < 4 {
                // The tree is built after the request; give it a moment once.
                Thread.sleep(forTimeInterval: 0.35)
                found = Self.walk(window)
            }
            self.controls = found.controls
            let title = Self.attribute(window, kAXTitleAttribute) as? String ?? ""
            return .ok(.string(Self.describe(found.controls, window: title, filter: filter, truncated: found.truncated)))
        }
    }

    func control(_ id: String) async -> InterfaceControl? {
        await run {
            guard id.hasPrefix("e"), let index = Int(id.dropFirst()), self.controls.indices.contains(index - 1) else { return nil }
            return self.controls[index - 1]
        }
    }

    func press(_ control: InterfaceControl) async -> ToolOutcome {
        await run {
            AXUIElementSetMessagingTimeout(control.element, 1)
            var result = AXUIElementPerformAction(control.element, kAXPressAction as CFString)
            if result != .success, result != .cannotComplete, Self.settable(control.element, kAXSelectedAttribute) {
                result = AXUIElementSetAttributeValue(control.element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            }
            switch result {
            case .success: return .ok(["pressed": .string(control.label)])
            // A press that opens a sheet may not answer in time although it took effect.
            case .cannotComplete: return .ok(["pressed": .string(control.label), "note": "no reply from the app; take a snapshot to check"], verified: false)
            default: return .failure("\(control.kind) \"\(control.label)\" cannot be pressed. Take a new snapshot or use a shortcut.")
            }
        }
    }

    /// Finds a menu bar item by its path of titles. On a miss, names what that level offers.
    func menuItem(pid: pid_t, path: [String]) async -> (control: InterfaceControl?, error: String) {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.6)
            guard var node = Self.element(Self.attribute(application, kAXMenuBarAttribute)) else { return (nil, "This app has no menu bar.") }
            var title = ""
            for wanted in path {
                var items = Self.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                // A menu bar item and a submenu item each hold one AXMenu with the entries.
                if items.count == 1, Self.attribute(items[0], kAXRoleAttribute) as? String == "AXMenu" {
                    items = Self.attribute(items[0], kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
                let titles = items.map { Self.attribute($0, kAXTitleAttribute) as? String ?? "" }
                guard let index = Self.match(wanted, in: titles) else {
                    let offered = titles.filter { !$0.isEmpty }.prefix(30).joined(separator: ", ")
                    return (nil, "No menu item \"\(wanted)\". Available here: \(offered)")
                }
                node = items[index]; title = titles[index]
            }
            guard Self.attribute(node, kAXEnabledAttribute) as? Bool != false else { return (nil, "Menu item \"\(title)\" is disabled.") }
            return (InterfaceControl(element: node, kind: "item", label: title), "")
        }
    }

    /// Role of the control that has keyboard focus, for deciding what Return would do.
    func focusedRole(pid: pid_t) async -> String {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            guard let focused = Self.element(Self.attribute(application, kAXFocusedUIElementAttribute)) else { return "" }
            return Self.attribute(focused, kAXRoleAttribute) as? String ?? ""
        }
    }

    /// Gives a control keyboard focus, or reports whether the focused one refuses text.
    func focusForTyping(pid: pid_t, control: InterfaceControl?) async -> String? {
        await run {
            if let control {
                guard !control.secure else { return "Password fields are never typed into." }
                AXUIElementSetMessagingTimeout(control.element, 0.6)
                guard AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
                    return "\(control.kind) \"\(control.label)\" does not take keyboard focus."
                }
                return nil
            }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            guard let focused = Self.element(Self.attribute(application, kAXFocusedUIElementAttribute)) else { return "Nothing has keyboard focus." }
            return Self.attribute(focused, kAXSubroleAttribute) as? String == "AXSecureTextField" ? "Password fields are never typed into." : nil
        }
    }

    private func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in worker.async { continuation.resume(returning: work()) } }
    }

    // MARK: Reading the tree

    private static let kinds: [String: String] = [
        "AXButton": "button", "AXRadioButton": "radio", "AXCheckBox": "checkbox", "AXPopUpButton": "menu", "AXMenuButton": "menu",
        "AXComboBox": "combo", "AXTextField": "field", "AXTextArea": "text", "AXLink": "link", "AXMenuItem": "item", "AXRow": "row",
        "AXCell": "cell", "AXSlider": "slider", "AXDisclosureTriangle": "disclosure", "AXIncrementor": "stepper", "AXSwitch": "switch"
    ]
    /// Nothing inside these is a control worth listing; skipping them keeps large windows fast.
    private static let leaves: Set<String> = ["AXStaticText", "AXImage", "AXScrollBar", "AXValueIndicator", "AXHeading", "AXSplitter", "AXRuler"]
    private static let batch = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute,
                                kAXSelectedAttribute, kAXChildrenAttribute, kAXNumberOfCharactersAttribute, "AXPlaceholderValue"] as [String]

    static func walk(_ root: AXUIElement, budget: TimeInterval = 1.5) -> (controls: [InterfaceControl], truncated: Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var found: [InterfaceControl] = [], stack = [root], visited = 0
        while let node = stack.popLast() {
            visited += 1
            if visited > 5000 || ProcessInfo.processInfo.systemUptime > deadline { return (found, true) }
            let values = read(node)
            guard let role = values[0] as? String, !leaves.contains(role) else { continue }
            let children = values[6] as? [AXUIElement] ?? []
            guard let kind = kinds[role] else { stack.append(contentsOf: children.reversed()); continue }
            let subrole = values[1] as? String ?? ""
            let isText = role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox"
            var label = [values[2], values[3], isText ? values[8] : nil].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            // Web buttons and list rows carry their name in a text child.
            if label.isEmpty, !isText { label = childText(children) }
            label = String(label.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces).prefix(80))
            guard !label.isEmpty || isText else {
                // An unnamed container row may still hold named controls.
                if role == "AXRow" || role == "AXCell" { stack.append(contentsOf: children.reversed()) }
                continue
            }
            var states: [String] = []
            if values[5] as? Bool == true { states.append("selected") }
            else if role == "AXRadioButton" || role == "AXCheckBox" || role == "AXSwitch",
                    (attribute(node, kAXValueAttribute) as? NSNumber)?.intValue == 1 { states.append(role == "AXRadioButton" ? "selected" : "on") }
            if values[4] as? Bool == false { states.append("disabled") }
            if isText { states.append((values[7] as? NSNumber)?.intValue ?? 0 > 0 ? "has text" : "empty") }
            found.append(InterfaceControl(element: node, kind: subrole == "AXTabButton" ? "tab" : subrole == "AXSearchField" ? "search" : kind,
                                          label: label.isEmpty ? "(unnamed)" : label, state: states.joined(separator: ", "),
                                          secure: subrole == "AXSecureTextField"))
        }
        return (found, false)
    }

    static func describe(_ controls: [InterfaceControl], window: String, filter: String?, truncated: Bool) -> String {
        let needle = filter?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let matching = controls.enumerated().filter { needle.isEmpty || $0.element.label.lowercased().contains(needle) || $0.element.kind == needle }
        var lines = ["window \"\(window)\""]
        for (index, control) in matching.prefix(shownLimit) {
            lines.append("e\(index + 1) \(control.kind) \"\(control.label)\"" + (control.state.isEmpty ? "" : " \(control.state)"))
        }
        if matching.isEmpty { lines.append(needle.isEmpty ? "(no controls readable in this window)" : "(no control matches \"\(needle)\")") }
        if matching.count > shownLimit { lines.append("(\(matching.count - shownLimit) more not shown; pass filter to narrow)") }
        if truncated { lines.append("(the window was too large to read completely; pass filter or use a shortcut)") }
        return lines.joined(separator: "\n")
    }

    /// Picks the menu title that the model most plausibly meant.
    static func match(_ wanted: String, in titles: [String]) -> Int? {
        func plain(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
        }
        let target = plain(wanted), candidates = titles.map(plain)
        guard !target.isEmpty else { return nil }
        return candidates.firstIndex(of: target) ?? candidates.firstIndex { !$0.isEmpty && $0.hasPrefix(target) }
            ?? candidates.firstIndex { $0.contains(target) }
    }

    private static func childText(_ children: [AXUIElement]) -> String {
        var texts: [String] = [], queue = Array(children.prefix(6)), seen = 0
        while !queue.isEmpty, texts.count < 2, seen < 12 {
            let node = queue.removeFirst(); seen += 1
            let values = read(node)
            if values[0] as? String == "AXStaticText" {
                let text = (attribute(node, kAXValueAttribute) as? String ?? values[2] as? String ?? "")
                if !text.isEmpty, text.count <= 80 { texts.append(text) }
            } else { queue.append(contentsOf: (values[6] as? [AXUIElement] ?? []).prefix(4)) }
        }
        return texts.joined(separator: " · ")
    }

    private static func read(_ node: AXUIElement) -> [Any?] {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, batch as CFArray, [], &values) == .success,
              let array = values as? [Any], array.count == batch.count else { return Array(repeating: nil, count: batch.count) }
        // A missing attribute comes back as an AXValue holding the error.
        return array.map { CFGetTypeID($0 as CFTypeRef) == AXValueGetTypeID() ? nil : $0 }
    }
    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func settable(_ node: AXUIElement, _ name: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(node, name as CFString, &result) == .success && result.boolValue
    }
}

extension KeyStroke {
    private static let named: [String: ApplicationKey] = [
        "return": .returnKey, "enter": .returnKey, "esc": .escape, "escape": .escape, "tab": .tab, "space": .space,
        "delete": .backspace, "backspace": .backspace, "forwarddelete": .forwardDelete, "up": .up, "down": .down, "left": .left,
        "right": .right, "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four, "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
        "-": .minus, "=": .equals, "[": .leftBracket, "]": .rightBracket, "\\": .backslash, ";": .semicolon, "'": .quote,
        ",": .comma, ".": .period, "/": .slash, "`": .grave
    ]
    var isReturn: Bool { code == 36 || code == 76 }

    /// Reads one chord such as "cmd+shift+p", "ctrl+tab" or "escape".
    static func parse(_ text: String) -> KeyStroke? {
        var flags: CGEventFlags = [], key: ApplicationKey?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default:
                guard key == nil, let parsed = named[part] ?? ApplicationKey(rawValue: part) else { return nil }
                key = parsed
            }
        }
        return key.map { KeyStroke(code: $0.keyCode, flags: flags) }
    }

    /// Delivered to one process, and marked so VibeWand's own keyboard listener ignores it.
    func post(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
            event.postToPid(pid)
        }
    }
}
