import AppKit
import ApplicationServices
import Darwin

/// Developer-only control channel for end-to-end checks. It exists only when
/// the app is launched with `--automation-socket <path>`: one JSON request per
/// connection, one JSON reply, same-user peers only. Normal launches never
/// open it, so no other process can borrow VibeWand's Accessibility access.
@MainActor
final class AutomationServer {
    typealias Reply = ([String: Any]) -> Void
    private let path: String
    private var descriptor: Int32 = -1
    private var listener: DispatchSourceRead?
    private let handler: @MainActor ([String: Any], @escaping Reply) -> Void

    init?(path: String, handler: @escaping @MainActor ([String: Any], @escaping Reply) -> Void) {
        self.path = path; self.handler = handler
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return nil }
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        unlink(path)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, S_IRUSR | S_IWUSR) == 0, listen(descriptor, 8) == 0 else {
            close(descriptor); descriptor = -1; return nil
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.accept() } }
        source.resume(); listener = source
    }

    func stop() {
        listener?.cancel(); listener = nil
        if descriptor >= 0 { close(descriptor); descriptor = -1; unlink(path) }
    }

    private func accept() {
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        var user: uid_t = 0, group: gid_t = 0
        guard getpeereid(client, &user, &group) == 0, user == getuid() else { close(client); return }
        let handler = handler
        DispatchQueue.global(qos: .userInitiated).async {
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while data.count < 1_048_576, !data.contains(10) {
                let count = read(client, &buffer, buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer[0..<count])
            }
            let line = data.prefix { $0 != 10 }
            let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handler(request) { reply in
                        var output = (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])) ?? Data("{}".utf8)
                        output.append(10)
                        DispatchQueue.global(qos: .userInitiated).async {
                            output.withUnsafeBytes { bytes in
                                var sent = 0
                                while sent < bytes.count {
                                    let count = write(client, bytes.baseAddress! + sent, bytes.count - sent)
                                    if count <= 0 { break }
                                    sent += count
                                }
                            }
                            close(client)
                        }
                    }
                }
            }
        }
    }
}

/// Reads another app's accessibility tree for adapter development and for
/// verifying what a check actually typed. Runs off the main thread.
enum AccessibilityProbe {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
    static func range(_ value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }

    static func line(_ element: AXUIElement, values: Bool) -> String {
        var parts = [string(element, kAXRoleAttribute)]
        let subrole = string(element, kAXSubroleAttribute)
        if !subrole.isEmpty { parts[0] += "/" + subrole }
        for (label, name) in [("t", kAXTitleAttribute), ("d", kAXDescriptionAttribute), ("id", kAXIdentifierAttribute),
                              ("ph", "AXPlaceholderValue"), ("help", kAXHelpAttribute), ("dom", "AXDOMIdentifier"), ("cls", "AXDOMClassList")] {
            let text: String
            if let list = attribute(element, name) as? [String] { text = list.joined(separator: " ") }
            else { text = string(element, name) }
            if !text.isEmpty { parts.append("\(label)=\"\(text.prefix(90))\"") }
        }
        if let value = attribute(element, kAXValueAttribute) {
            if let text = value as? String {
                parts.append(values ? "v(\(text.utf16.count))=\"\(text.prefix(60).replacingOccurrences(of: "\n", with: "⏎"))\"" : "v(\(text.utf16.count))")
            } else if let number = value as? NSNumber { parts.append("v=\(number)") }
        }
        if let selection = range(attribute(element, kAXSelectedTextRangeAttribute)) { parts.append("sel=\(selection.location)+\(selection.length)") }
        if let rect = frame(element) { parts.append("@\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))") }
        var flags: [String] = []
        if (attribute(element, kAXFocusedAttribute) as? Bool) == true { flags.append("focused") }
        if (attribute(element, kAXSelectedAttribute) as? Bool) == true { flags.append("selected") }
        if (attribute(element, kAXEnabledAttribute) as? Bool) == false { flags.append("disabled") }
        if (attribute(element, "AXEditable") as? Bool) == true { flags.append("editable") }
        for (label, name) in [("set:value", kAXValueAttribute), ("set:selText", kAXSelectedTextAttribute),
                              ("set:selRange", kAXSelectedTextRangeAttribute)] where settable(element, name) { flags.append(label) }
        var actions: CFArray?
        if AXUIElementCopyActionNames(element, &actions) == .success, let names = actions as? [String], !names.isEmpty {
            flags.append("act:" + names.map { $0.replacingOccurrences(of: "AX", with: "") }.joined(separator: ","))
        }
        if !flags.isEmpty { parts.append("[" + flags.joined(separator: " ") + "]") }
        return parts.joined(separator: " ")
    }

    /// `root`: "focus" prints the focus ancestry and the focused subtree,
    /// "window" the focused window, "app" every window.
    static func dump(pid: pid_t, root: String, depth: Int, limit: Int, values: Bool, manual: Bool) -> String {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 1.5)
        var lines: [String] = [], count = 0
        if manual {
            let result = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            lines.append("# AXManualAccessibility set → \(result.rawValue)")
        }
        func walk(_ node: AXUIElement, _ level: Int) {
            guard count < limit else { return }
            count += 1
            lines.append(String(repeating: "  ", count: level) + line(node, values: values))
            guard level < depth, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for child in children { walk(child, level + 1) }
        }
        let focused = element(attribute(application, kAXFocusedUIElementAttribute))
        let window = element(attribute(application, kAXFocusedWindowAttribute))
        switch root {
        case "focus":
            var chain: [AXUIElement] = [], node = focused
            while let current = node, chain.count < 40 { chain.append(current); node = element(attribute(current, kAXParentAttribute)) }
            lines.append("# ancestry (window → focus)")
            for (index, item) in chain.reversed().enumerated() { lines.append(String(repeating: " ", count: index) + line(item, values: values)) }
            lines.append("# focused subtree")
            if let focused { walk(focused, 0) } else { lines.append("(no focused element)") }
        case "app": walk(application, 0)
        default:
            if let window { walk(window, 0) } else { lines.append("(no focused window)") }
        }
        if count >= limit { lines.append("… truncated at \(limit) nodes") }
        return lines.joined(separator: "\n")
    }

    /// First element in the focused window (breadth-first) matching a role and
    /// a case-insensitive substring of its title, description or identifier.
    static func find(pid: pid_t, role: String?, text: String?, limit: Int = 6000) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let window = element(attribute(application, kAXFocusedWindowAttribute)) else { return nil }
        var queue = [window], index = 0
        let needle = text?.lowercased()
        while index < queue.count, index < limit {
            let node = queue[index]; index += 1
            let matchesRole = role == nil || string(node, kAXRoleAttribute) == role
            if matchesRole {
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, "AXPlaceholderValue"]
                    .map { string(node, $0).lowercased() }.joined(separator: "\n")
                if needle == nil || label.contains(needle!) { return node }
            }
            if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        return nil
    }

    static func focusedField(pid: pid_t) -> [String: Any] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 1)
        guard var node = element(attribute(application, kAXFocusedUIElementAttribute)) else { return ["ok": false, "error": "no focus"] }
        for _ in 0..<8 {
            if ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"].contains(string(node, kAXRoleAttribute)) { break }
            guard let parent = element(attribute(node, kAXParentAttribute)) else { break }
            node = parent
        }
        var result: [String: Any] = ["ok": true, "role": string(node, kAXRoleAttribute), "description": line(node, values: false)]
        if let value = attribute(node, kAXValueAttribute) as? String { result["value"] = value }
        if let selection = range(attribute(node, kAXSelectedTextRangeAttribute)) { result["selection"] = [selection.location, selection.length] }
        return result
    }
}

/// Maps automation requests onto the same entry points the hardware uses.
@MainActor
final class AutomationController {
    private let runtime: BridgeRuntime
    private let overlay: OverlayController
    private let openSettings: (Int?) -> Void
    private let renderSettings: (URL) -> Bool
    private var server: AutomationServer?
    private let worker = DispatchQueue(label: "vibewand.automation", qos: .userInitiated)

    init?(path: String, runtime: BridgeRuntime, overlay: OverlayController,
          openSettings: @escaping (Int?) -> Void, renderSettings: @escaping (URL) -> Bool) {
        self.runtime = runtime; self.overlay = overlay
        self.openSettings = openSettings; self.renderSettings = renderSettings
        guard let server = AutomationServer(path: path, handler: { [weak self] request, reply in
            guard let self else { reply(["ok": false]); return }
            self.handle(request, reply: reply)
        }) else { return nil }
        self.server = server
    }

    func stop() { server?.stop() }

    private func after(_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { MainActor.assumeIsolated { work() } }
    }

    private func targetPID(_ request: [String: Any]) -> pid_t? {
        if let bundle = request["bundle"] as? String {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func handle(_ request: [String: Any], reply: @escaping AutomationServer.Reply) {
        let command = request["cmd"] as? String ?? ""
        let device = (request["device"] as? String).flatMap(DeviceTemplateID.init(rawValue:))
        let control = (request["control"] as? String).flatMap(DeviceControl.init(rawValue:))
        func fail(_ message: String) { reply(["ok": false, "error": message]) }
        func state(_ extra: [String: Any] = [:]) {
            var value = (try? runtime.diagnostics()) ?? [:]
            value["ok"] = true
            value["front"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            for (key, item) in extra { value[key] = item }
            reply(value)
        }
        switch command {
        case "ping": reply(["ok": true, "pid": getpid(), "trusted": AXIsProcessTrusted()])
        case "state": state()
        case "input", "tap", "turn":
            guard let control else { return fail("unknown control") }
            do {
                if command == "input" {
                    guard let phase = (request["phase"] as? String).flatMap(InputPhase.init(rawValue:)) else { return fail("unknown phase") }
                    try runtime.simulate(control, phase: phase, device: device)
                    after(request["settle"] as? Int ?? 60) { state() }
                } else if command == "turn" {
                    let count = max(1, min(60, request["count"] as? Int ?? 1)), gap = request["gap"] as? Int ?? 45
                    try runtime.simulate(control, phase: .pulse, device: device)
                    for index in 1..<count { after(index * gap) { try? self.runtime.simulate(control, phase: .pulse, device: nil) } }
                    after(count * gap + (request["settle"] as? Int ?? 250)) { state() }
                } else {
                    try runtime.simulate(control, phase: .down, device: device)
                    let hold = request["hold"] as? Int ?? 60
                    after(hold) {
                        try? self.runtime.simulate(control, phase: .up, device: nil)
                        self.after(request["settle"] as? Int ?? 700) { state() }
                    }
                }
            } catch { fail(error.localizedDescription) }
        case "template":
            guard let device else { return fail("unknown device") }
            do { try runtime.selectTemplate(device); state() } catch { fail(error.localizedDescription) }
        case "activate":
            guard let bundle = request["bundle"] as? String,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return fail("app not running") }
            app.activate(options: [.activateAllWindows])
            after(request["settle"] as? Int ?? 900) { state() }
        case "ax":
            guard let pid = targetPID(request) else { return fail("no target app") }
            let root = request["root"] as? String ?? "focus", depth = request["depth"] as? Int ?? 6
            let limit = request["limit"] as? Int ?? 400, values = request["values"] as? Bool ?? false
            let manual = request["manual"] as? Bool ?? false, path = request["path"] as? String
            worker.async {
                let text = AccessibilityProbe.dump(pid: pid, root: root, depth: depth, limit: limit, values: values, manual: manual)
                if let path { try? text.write(toFile: path, atomically: true, encoding: .utf8) }
                DispatchQueue.main.async { reply(path == nil ? ["ok": true, "text": text] : ["ok": true, "path": path!, "lines": text.split(separator: "\n").count]) }
            }
        case "field":
            guard let pid = targetPID(request) else { return fail("no target app") }
            worker.async {
                let value = AccessibilityProbe.focusedField(pid: pid)
                DispatchQueue.main.async { reply(value) }
            }
        case "ui":
            guard let pid = targetPID(request) else { return fail("no target app") }
            let role = request["role"] as? String, text = request["text"] as? String, action = request["do"] as? String ?? "none"
            worker.async {
                guard let node = AccessibilityProbe.find(pid: pid, role: role, text: text) else {
                    DispatchQueue.main.async { reply(["ok": false, "error": "not found"]) }; return
                }
                var result: AXError = .success
                if action == "press" { result = AXUIElementPerformAction(node, kAXPressAction as CFString) }
                else if action == "focus" { result = AXUIElementSetAttributeValue(node, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
                let line = AccessibilityProbe.line(node, values: false)
                DispatchQueue.main.async { reply(["ok": result == .success, "element": line, "result": result.rawValue]) }
            }
        case "key":
            // Test clean-up only (select all, delete, escape). Return is refused
            // so a check can never submit a draft by accident.
            guard let code = request["code"] as? Int, code != 36, code != 76 else { return fail("key refused") }
            var flags: CGEventFlags = []
            for name in request["flags"] as? [String] ?? [] {
                switch name {
                case "cmd": flags.insert(.maskCommand)
                case "shift": flags.insert(.maskShift)
                case "alt": flags.insert(.maskAlternate)
                case "ctrl": flags.insert(.maskControl)
                default: break
                }
            }
            let source = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
                event?.flags = flags
                event?.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
                event?.post(tap: .cghidEventTap)
            }
            after(request["settle"] as? Int ?? 250) { state() }
        case "overlay":
            if let visible = request["visible"] as? Bool { overlay.setVisible(visible) }
            if let mode = (request["mode"] as? String).flatMap(OverlayDisplayMode.init(rawValue:)) { overlay.setDisplayMode(mode) }
            if let expanded = request["expanded"] as? Bool { overlay.setExpanded(expanded) }
            if let origin = request["origin"] as? [Double], origin.count == 2 { overlay.setOrigin(NSPoint(x: origin[0], y: origin[1])) }
            if request["toggle"] as? Bool == true { overlay.toggleDisplayMode() }
            var value = overlay.automationState
            if let path = request["render"] as? String { value["rendered"] = overlay.renderPNG(to: URL(fileURLWithPath: path)) }
            value["ok"] = true
            after(request["settle"] as? Int ?? 120) { var final = self.overlay.automationState; final["ok"] = true; final["rendered"] = value["rendered"] ?? false; reply(final) }
        case "settings":
            openSettings(request["section"] as? Int)
            after(request["settle"] as? Int ?? 900) {
                var value: [String: Any] = ["ok": true]
                if let path = request["render"] as? String { value["rendered"] = self.renderSettings(URL(fileURLWithPath: path)) }
                reply(value)
            }
        case "dictate":
            guard let previews = request["previews"] as? [String], !previews.isEmpty else { return fail("previews required") }
            let interval = Double(request["interval"] as? Int ?? 350) / 1000
            runtime.automationDictate(previews: previews, interval: interval, polished: request["polished"] as? Bool ?? false)
            after(Int((Double(previews.count) * interval + (Double(request["wait"] as? Int ?? 2500) / 1000)) * 1000)) { state() }
        case "listen":
            let seconds = min(60, max(1, request["seconds"] as? Double ?? 5))
            runtime.automationListen(seconds: seconds)
            after(Int((seconds + (request["wait"] as? Double ?? 6)) * 1000)) { state() }
        case "set":
            if let demo = request["demo"] as? Bool { runtime.demo = demo }
            if let follow = request["autoSwitch"] as? Bool { runtime.setFollowsActiveDevice(follow) }
            if let force = request["forceEditing"] as? Bool { runtime.adapter.forceEditing = force }
            state()
        case "quit": reply(["ok": true]); after(100) { NSApp.terminate(nil) }
        default: fail("unknown cmd")
        }
    }
}
