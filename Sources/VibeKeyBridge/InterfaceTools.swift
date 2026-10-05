import AppKit
import ApplicationServices
import ScreenCaptureKit
import WandAgent

/// The size of a text control's contents and its selection, never the contents themselves.
struct TextCaret: Equatable {
    var characters: Int
    var location: Int
    var selected: Int
}

/// One control from the latest snapshot. Its id is its position in that snapshot.
struct InterfaceControl {
    let element: AXUIElement
    let kind: String
    var label: String
    var state = ""
    var secure = false
    var role = ""
}

/// Reads and operates the front window of one app through its accessibility
/// tree, the same structure a screen reader is given. No coordinate is clicked.
/// Field contents and document text are left out of what is read: a field is
/// reported as empty or not, never by what it holds. The one text read that is
/// not a control's name is what the app itself announces to a screen reader,
/// such as the level a control stands at. A picture of the window is taken
/// only through `picture`, which is offered to the model only when the user
/// has let it see.
final class InterfaceTools: @unchecked Sendable {
    static let shownLimit = 150
    private let worker = DispatchQueue(label: "vibewand.interface", qos: .userInitiated)
    // All are touched on `worker` only.
    private var controls: [InterfaceControl] = []
    /// What the snapshot before this one held, to tell what an action brought or changed.
    private var known: Set<String> = []
    /// The positions the latest snapshot printed, for a picture to mark.
    private var shown: [Int] = []
    private var prepared: Set<pid_t> = []

    /// `landmark` names a control the app's adapter knows by more than its label, from its role and label.
    func snapshot(pid: pid_t, filter: String?, landmark: @escaping (String, String) -> String? = { _, _ in nil }) async -> ToolOutcome {
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
            var named: [String: [Int]] = [:]
            for index in found.controls.indices {
                if let name = landmark(found.controls[index].role, found.controls[index].label) { named[name, default: []].append(index) }
            }
            // A chat titled after a model looks like the model picker by its label; the one that opens a menu is it.
            for (name, places) in named {
                for index in places where places.count == 1 || ["AXPopUpButton", "AXMenuButton"].contains(found.controls[index].role) {
                    found.controls[index].state = [found.controls[index].state, name].filter { !$0.isEmpty }.joined(separator: ", ")
                }
            }
            let marks = found.controls.map(Self.mark)
            let fresh = Set(marks.indices.filter { !self.known.isEmpty && !self.known.contains(marks[$0]) })
            self.controls = found.controls; self.known = Set(marks)
            let title = Self.attribute(window, kAXTitleAttribute) as? String ?? ""
            let listing = Self.describe(found.controls, window: title, filter: filter, truncated: found.truncated, fresh: fresh)
            self.shown = listing.shown
            return .ok(.string(listing.text))
        }
    }

    /// A picture of the app's front window, with the ids of the latest snapshot marked on the controls they
    /// name. Nothing but that one window is in it.
    func picture(pid: pid_t) async -> ToolOutcome {
        guard CGPreflightScreenCaptureAccess() else {
            return .failure("VibeWand is not allowed to record the screen. The user can allow it in System Settings, under Privacy & Security, Screen & System Audio Recording.")
        }
        guard let layout = await run({ self.layout(pid: pid) }) else { return .failure("This app has no window to look at.") }
        func apart(_ frame: CGRect) -> CGFloat {
            abs(frame.minX - layout.frame.minX) + abs(frame.minY - layout.frame.minY) + abs(frame.width - layout.frame.width) + abs(frame.height - layout.frame.height)
        }
        // The window server's record of the window the tree described: same app, same place.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.filter({ $0.owningApplication?.processID == pid && $0.windowLayer == 0 }).min(by: { apart($0.frame) < apart($1.frame) }),
              apart(window.frame) < 40 else { return .failure("The window could not be found on screen.") }
        // Sharp enough to read, small enough to send: at most 1600 pixels along the longer side.
        let scale = min(2, 1600 / max(layout.frame.width, layout.frame.height))
        let configuration = SCStreamConfiguration()
        configuration.width = Int(layout.frame.width * scale); configuration.height = Int(layout.frame.height * scale)
        configuration.showsCursor = false; configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration),
              let picture = Self.mark(image, layout: layout) else { return .failure("The window could not be captured.") }
        let marked = layout.marks.isEmpty ? "no snapshot to mark yet" : "\(layout.marks.count) controls of the latest snapshot marked with their ids"
        return ToolOutcome(text: "window \"\(layout.title)\", \(image.width)×\(image.height) px, \(marked)", image: picture)
    }

    /// Where a window is and where the controls of the latest snapshot are in it, in screen points from the top left.
    struct Layout {
        var title: String
        var frame: CGRect
        var marks: [(id: String, frame: CGRect)]
    }
    private func layout(pid: pid_t) -> Layout? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        guard let window = Self.element(Self.attribute(application, kAXFocusedWindowAttribute)) ?? Self.element(Self.attribute(application, kAXMainWindowAttribute)),
              let frame = Self.frame(window), frame.width > 1, frame.height > 1 else { return nil }
        let marks = shown.compactMap { index in
            Self.frame(controls[index].element).flatMap { $0.width > 2 && $0.height > 2 && frame.intersects($0) ? (id: "e\(index + 1)", frame: $0) : nil }
        }
        return Layout(title: Self.attribute(window, kAXTitleAttribute) as? String ?? "", frame: frame, marks: marks)
    }

    /// Draws each control's outline and id over the picture and returns it as a JPEG.
    static func mark(_ image: CGImage, layout: Layout) -> Data? {
        let size = CGSize(width: image.width, height: image.height), scale = size.width / layout.frame.width
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        // Controls are placed from the window's top left; the picture is drawn from its bottom left.
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let font = NSFont.monospacedSystemFont(ofSize: 10 * max(1, scale), weight: .bold)
        for mark in layout.marks {
            let box = CGRect(x: (mark.frame.minX - layout.frame.minX) * scale, y: (mark.frame.minY - layout.frame.minY) * scale,
                             width: mark.frame.width * scale, height: mark.frame.height * scale)
            NSColor.systemPink.setStroke()
            let outline = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); outline.lineWidth = 1; outline.stroke()
            let text = NSAttributedString(string: mark.id, attributes: [.font: font, .foregroundColor: NSColor.white])
            let extent = text.size()
            let tag = CGRect(x: box.minX, y: box.minY, width: extent.width + 4, height: extent.height)
            NSColor.systemPink.setFill(); tag.fill()
            text.draw(at: CGPoint(x: tag.minX + 2, y: tag.minY))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) }
    }

    /// What the app has announced since the latest snapshot or the last call: the status lines that now say something else.
    func announced() async -> [String] {
        await run {
            guard self.controls.contains(where: { $0.kind == "status" }) else { return [] }
            // An app announces a moment after the key that caused it.
            Thread.sleep(forTimeInterval: 0.25)
            var said: [String] = []
            for index in self.controls.indices where self.controls[index].kind == "status" {
                let now = Self.childText(Self.attribute(self.controls[index].element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                guard !now.isEmpty, now != self.controls[index].label else { continue }
                self.controls[index].label = now
                said.append(now)
            }
            // The next snapshot compares with what the model has now been told.
            self.known.formUnion(self.controls.map(Self.mark))
            return said
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

    /// Whether the app has a window on the Space in front. An app sliding in from another Space is
    /// already frontmost while it still has none, and keys sent to it then can be lost.
    func hasWindowHere(pid: pid_t) async -> Bool {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            return !(Self.attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []).isEmpty
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

    /// How much the focused text control holds and where its caret is: enough to tell whether typed text
    /// arrived, without reading what the control contains. nil when no readable text control has the keyboard.
    func caret(pid: pid_t) async -> TextCaret? {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            guard let focused = Self.element(Self.attribute(application, kAXFocusedUIElementAttribute)),
                  ["AXTextField", "AXTextArea", "AXComboBox"].contains(Self.attribute(focused, kAXRoleAttribute) as? String ?? "") else { return nil }
            let characters = (Self.attribute(focused, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
            var selection: CFRange?
            if let value = Self.attribute(focused, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(value as! AXValue, .cfRange, &range) { selection = range }
            }
            guard characters != nil || selection != nil else { return nil }
            return TextCaret(characters: characters ?? -1, location: selection?.location ?? -1, selected: selection?.length ?? -1)
        }
    }

    /// Gives a control keyboard focus, or reports whether the focused one refuses text. nil when the keyboard may go there.
    func focus(pid: pid_t, control: InterfaceControl?) async -> String? {
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
                                kAXSelectedAttribute, kAXChildrenAttribute, kAXNumberOfCharactersAttribute, "AXPlaceholderValue",
                                "AXKeyShortcutsValue"] as [String]
    /// What a web app marks as said aloud to a screen reader: a status line or an alert.
    private static let announcements: Set<String> = ["AXApplicationStatus", "AXApplicationAlert"]

    static func walk(_ root: AXUIElement, budget: TimeInterval = 1.5) -> (controls: [InterfaceControl], truncated: Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var found: [InterfaceControl] = [], stack = [root], visited = 0
        while let node = stack.popLast() {
            visited += 1
            if visited > 5000 || ProcessInfo.processInfo.systemUptime > deadline { return (found, true) }
            let values = read(node)
            guard let role = values[0] as? String, !leaves.contains(role) else { continue }
            let children = values[6] as? [AXUIElement] ?? [], subrole = values[1] as? String ?? ""
            guard let kind = kinds[role] else {
                // An announcement is short by nature; one that is not is left unread, like any other text.
                if announcements.contains(subrole) {
                    let said = childText(children)
                    if !said.isEmpty { found.append(InterfaceControl(element: node, kind: "status", label: said, role: role)) }
                } else { stack.append(contentsOf: children.reversed()) }
                continue
            }
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
            else if ["AXRadioButton", "AXCheckBox", "AXSwitch", "AXMenuItem"].contains(role),
                    (attribute(node, kAXValueAttribute) as? NSNumber)?.intValue == 1 {
                states.append(role == "AXRadioButton" ? "selected" : role == "AXMenuItem" ? "checked" : "on")
            }
            if values[4] as? Bool == false { states.append("disabled") }
            if isText { states.append((values[7] as? NSNumber)?.intValue ?? 0 > 0 ? "has text" : "empty") }
            // The keys a web control says it is worked with: a level set with the arrows, for one.
            if let keys = values[9] as? String, !keys.isEmpty { states.append("keys: \(keys.prefix(60))") }
            found.append(InterfaceControl(element: node, kind: subrole == "AXTabButton" ? "tab" : subrole == "AXSearchField" ? "search" : kind,
                                          label: label.isEmpty ? "(unnamed)" : label, state: states.joined(separator: ", "),
                                          secure: subrole == "AXSecureTextField", role: role))
        }
        return (found, false)
    }

    /// What tells one listed control from another, and from itself once its name or state has changed.
    private static func mark(_ control: InterfaceControl) -> String {
        "\(CFHash(control.element))|\(control.kind)|\(control.label)|\(control.state)"
    }

    /// The listing the model reads, and which positions it printed. `fresh` are the positions that are new or
    /// changed since the snapshot before: they lead, so that what a press opened is not lost below a long window.
    static func describe(_ controls: [InterfaceControl], window: String, filter: String?, truncated: Bool,
                         fresh: Set<Int> = []) -> (text: String, shown: [Int]) {
        let needle = filter?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let matching = controls.indices.filter {
            needle.isEmpty || controls[$0].label.lowercased().contains(needle) || controls[$0].kind == needle || controls[$0].state.lowercased().contains(needle)
        }
        // With everything new there is nothing to set apart: another window, or a view that was replaced.
        let lead = matching.filter(fresh.contains), apart = !lead.isEmpty && lead.count < matching.count
        let shown = Array(((apart ? lead : []) + matching.filter { !apart || !fresh.contains($0) }).prefix(shownLimit))
        var lines = ["window \"\(window)\""]
        for (place, index) in shown.enumerated() {
            if apart, place == 0 { lines.append("new or changed since the last snapshot:") }
            if apart, place == lead.count { lines.append("as before:") }
            let control = controls[index]
            lines.append("e\(index + 1) \(control.kind) \"\(control.label)\"" + (control.state.isEmpty ? "" : " \(control.state)"))
        }
        if matching.isEmpty { lines.append(needle.isEmpty ? "(no controls readable in this window)" : "(no control matches \"\(needle)\")") }
        if matching.count > shownLimit { lines.append("(\(matching.count - shownLimit) more not shown; pass filter to narrow)") }
        if truncated { lines.append("(the window was too large to read completely; pass filter or use a shortcut)") }
        return (lines.joined(separator: "\n"), shown)
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
    private static func frame(_ node: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let position = attribute(node, kAXPositionAttribute), let extent = attribute(node, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
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
        "right": .right, "arrowup": .up, "arrowdown": .down, "arrowleft": .left, "arrowright": .right,
        "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
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
