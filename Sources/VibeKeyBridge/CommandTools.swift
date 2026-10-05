import AppKit
import ApplicationServices
import WandAgent

/// Something the coordinator needs from the user before it goes on.
enum CommandQuestion: Equatable {
    case choose(String, [String])
    case confirm(String)
}

/// What the coordinator's tools do on this Mac. Every call has passed the
/// gateway; this is where it meets the adapters and the window in front.
@MainActor
final class CommandTools: ToolHost {
    struct Source: Equatable { var pid: pid_t; var name: String; var window: String }
    /// Apps with their own adapter, under the id the model uses for them.
    private static let targets: [(id: String, profile: ApplicationProfile, bundleIDs: [String])] = [
        ("codex", .codex, ["com.openai.codex"]),
        ("claude", .claude, ["com.anthropic.claudefordesktop"]),
        ("harness", .deepSeekHarness, ["com.deepseek.dsh"]),
        ("workbuddy", .workBuddy, ["com.tencent.workbuddy.mac"]),
        ("feishu", .feishu, ["com.electron.lark", "com.bytedance.Lark", "com.larksuite.Lark"]),
        ("wechat", .weChat, ["com.tencent.xinWeChat", "com.tencent.WeChat"])
    ]

    private let adapter: AccessibilityAdapter
    private let interface = InterfaceTools()
    private var codex: CodexAppServer?
    private var known: [String: ChatSession] = [:]
    /// Where the user was when they spoke.
    private(set) var source: Source?
    /// The app this task is operating: the source, until the task brings another one forward.
    private var target: pid_t?
    /// Puts a question on the overlay. Returns the chosen index, 0 for a confirmation, or nil.
    var ask: ((CommandQuestion) async -> Int?)?

    init(adapter: AccessibilityAdapter) { self.adapter = adapter }

    /// Taken at key-down, before anything can change what is in front.
    func captureSource() {
        known = [:]; target = nil
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { source = nil; return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var window: CFTypeRef?, title: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success, let window,
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        }
        source = Source(pid: app.processIdentifier, name: Self.displayName(app), window: title as? String ?? "")
        target = app.processIdentifier
    }
    func shutdown() { codex?.stop(); codex = nil }

    func confirm(_ tool: String, _ arguments: JSONValue, every: Bool) async -> Bool? {
        guard let question = await question(tool, arguments, every: every) else { return nil }
        return await ask?(.confirm(question)) != nil
    }

    /// What to ask before a call, in words that say what it will do. nil when it needs no word from the user:
    /// with `every` unset, that is anything but a control, menu item or shortcut that sends or destroys.
    private func question(_ tool: String, _ arguments: JSONValue, every: Bool) async -> String? {
        func quoted(_ text: String) -> String { text.count > 40 ? text.prefix(40) + "…" : text }
        switch tool {
        case "ui_press":
            guard operated() != nil, let control = await interface.control(arguments["id"]?.string ?? ""),
                  every || ControlRisk.needsConfirmation(control.label) else { return nil }
            return L10n.tr("按下「\(control.label)」？", "Press “\(control.label)”?")
        case "ui_menu":
            guard let pid = operated(), let item = await interface.menuItem(pid: pid, path: arguments["path"]?.array?.compactMap(\.string) ?? []).control,
                  every || ControlRisk.needsConfirmation(item.label) else { return nil }
            return L10n.tr("选择菜单「\(item.label)」？", "Choose “\(item.label)” from the menu?")
        case "ui_key":
            guard let pid = operated(), let keys = arguments["keys"]?.string, let stroke = KeyStroke.parse(keys) else { return nil }
            if stroke.needsConfirmation(focusedRole: await interface.focusedRole(pid: pid)) {
                return L10n.tr("发送按键 \(keys)？它可能提交或删除内容", "Send \(keys)? It may submit or delete something")
            }
            return every ? L10n.tr("发送按键 \(keys)？", "Send \(keys)?") : nil
        case "ui_type":
            return every ? L10n.tr("输入「\(quoted(arguments["text"]?.string ?? ""))」？", "Type “\(quoted(arguments["text"]?.string ?? ""))”?") : nil
        case "activate_app":
            guard every else { return nil }
            let app = arguments["app"]?.string ?? ""
            let name = Self.targets.first { $0.id == app }?.profile.title ?? app
            if let open = arguments["open"]?.string, !open.isEmpty { return L10n.tr("用 \(name) 打开 \(quoted(open))？", "Open \(quoted(open)) in \(name)?") }
            return L10n.tr("切换到 \(name)？", "Switch to \(name)?")
        case "open_session":
            guard every else { return nil }
            let title = known[arguments["id"]?.string ?? ""]?.title ?? ""
            return L10n.tr("打开会话「\(quoted(title))」？", "Open the chat “\(quoted(title))”?")
        case "search_in_app":
            guard every else { return nil }
            let name = Self.targets.first { $0.id == arguments["app"]?.string }?.profile.title ?? ""
            return L10n.tr("在 \(name) 里搜索「\(quoted(arguments["query"]?.string ?? ""))」？", "Search \(name) for “\(quoted(arguments["query"]?.string ?? ""))”?")
        default: return every ? L10n.tr("执行 \(tool)？", "Run \(tool)?") : nil
        }
    }

    func perform(_ tool: String, _ arguments: JSONValue) async -> ToolOutcome {
        switch tool {
        case "list_targets": return listTargets()
        case "find_sessions": return await findSessions(arguments)
        case "open_session": return await openSession(arguments)
        case "search_in_app": return await searchInApp(arguments)
        case "activate_app": return await activateApp(arguments)
        case "choose": return await choose(arguments)
        case "ui_snapshot":
            guard let pid = operated() else { return movedAway }
            return await interface.snapshot(pid: pid, filter: arguments["filter"]?.string)
        case "ui_press": return await press(arguments)
        case "ui_key": return await key(arguments)
        case "ui_menu": return await menu(arguments)
        case "ui_type": return await type(arguments)
        default: return .failure("\(tool) is not available.")
        }
    }

    // MARK: Apps and chats

    private func route(_ profile: ApplicationProfile) -> String {
        profile == .codex && codexExecutable != nil ? "list" : "search"
    }
    private var codexExecutable: URL? {
        CodexAppServer.locate(desktopApp: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"))
    }

    private func listTargets() -> ToolOutcome {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var apps: [JSONValue] = [], adapted: Set<pid_t> = []
        for entry in Self.targets where adapter.isEnabled(entry.profile) {
            let process = running.first { entry.bundleIDs.contains($0.bundleIdentifier ?? "") }
            if let process { adapted.insert(process.processIdentifier) }
            guard process != nil || installed(entry.bundleIDs) != nil else { continue }
            apps.append(["id": .string(entry.id), "name": .string(entry.profile.title), "running": .bool(process != nil),
                         "front": .bool(process != nil && process?.processIdentifier == front), "sessions": .string(route(entry.profile))])
        }
        let others = running.filter { !adapted.contains($0.processIdentifier) }.map { JSONValue.string(Self.displayName($0)) }
        return .ok(["apps": .array(apps), "other_running_apps": .array(others),
                    "user_was_in": ["app": .string(source?.name ?? ""), "window": .string(source?.window ?? "")]])
    }

    private func findSessions(_ arguments: JSONValue) async -> ToolOutcome {
        guard arguments["app"]?.string == "codex", let executable = codexExecutable else {
            return .failure("This app has no structured chat list. Use search_in_app.")
        }
        do {
            if codex == nil { codex = try CodexAppServer(executable: executable) }
            let all = try await codex!.sessions(limit: 60)
            for session in all { known[session.id] = session }
            let ranked = ChatSession.rank(all, query: arguments["query"]?.string, limit: min(max(arguments["limit"]?.int ?? 8, 1), 20))
            let clock = DateFormatter(); clock.dateFormat = "MM-dd HH:mm"
            var result: [String: JSONValue] = ["matched": .bool(ranked.matched), "sessions": .array(ranked.sessions.map {
                ["id": .string($0.id), "title": .string($0.title), "folder": .string($0.folder), "updated": .string(clock.string(from: $0.updated))]
            })]
            // Chats that live on another machine are in Codex's window but not in this list.
            if !ranked.matched {
                result["note"] = "Nothing matched; these are only the most recent chats kept on this Mac. If none of them is the one, call search_in_app to search Codex itself."
            }
            return .ok(.object(result))
        } catch {
            codex?.stop(); codex = nil
            return .failure("Codex's chat list is unavailable. Use search_in_app.")
        }
    }

    private func openSession(_ arguments: JSONValue) async -> ToolOutcome {
        guard arguments["app"]?.string == "codex", let id = arguments["id"]?.string, let session = known[id],
              let link = URL(string: "codex://threads/\(id)") else {
            return .failure("Unknown chat id. Only ids returned by find_sessions can be opened.")
        }
        NSWorkspace.shared.open(link)
        let app = await front(["com.openai.codex"])
        if let app { target = app.processIdentifier }
        // The link is Codex's own; whether it landed on the chat cannot be read back from here.
        return .ok(["opened": .string(session.title), "app_in_front": .bool(app != nil)], verified: false)
    }

    private func searchInApp(_ arguments: JSONValue) async -> ToolOutcome {
        guard let entry = Self.targets.first(where: { $0.id == arguments["app"]?.string }), adapter.isEnabled(entry.profile) else {
            return .failure("Unknown app id. Use an id from list_targets.")
        }
        guard let app = await bringForward(entry.bundleIDs) else { return .failure("\(entry.profile.title) could not be brought to the front.") }
        target = app.processIdentifier
        // An app arriving from another Space has no window with the keyboard for a moment, and would not get the shortcut.
        var observation = await observe()
        for _ in 0..<25 where observation.pid != app.processIdentifier || !observation.context.targetAvailable {
            try? await Task.sleep(nanoseconds: 100_000_000)
            observation = await observe()
        }
        var open = false
        for attempt in 0..<2 where !open {
            let asked = observation.identity
            _ = adapter.perform(.openSessions, observation: observation)
            for _ in 0..<12 where !open {
                try? await Task.sleep(nanoseconds: 150_000_000)
                observation = await observe()
                open = observation.context.picker == .sessions
            }
            // An app still settling can miss the shortcut. Asking again is safe only when nothing moved:
            // on a search that did open, the same shortcut would close it.
            guard attempt == 0, observation.identity == asked else { break }
        }
        guard open else {
            return .ok(["search_open": false, "query_typed": false, "next": "The app's search did not open. Call need_user and say so."], verified: false)
        }
        // A sidebar list is walked row by row; there is no field to type a query into.
        let query = arguments["query"]?.string ?? ""
        guard !query.isEmpty, !entry.profile.picksSessionsFromSidebar else {
            return .ok(["search_open": true, "query_typed": false, "next": "The user picks with the dial. Call finish."])
        }
        switch await fill(query, pid: app.processIdentifier) {
        case true?: return .ok(["search_open": true, "query_typed": true, "next": "The user picks with the dial. Call finish."])
        case nil: return .ok(["search_open": true, "query_typed": "sent, but this app's search cannot be read to check",
                              "next": "The user picks with the dial. Call finish."], verified: false)
        case false?: return .ok(["search_open": true, "query_typed": false,
                                 "next": "The search is open but the keywords did not go in. Call finish and say that the user has to type them."], verified: false)
        }
    }

    /// Puts the keywords into the search that has just opened, in place of anything it still holds.
    private func fill(_ query: String, pid: pid_t) async -> Bool? {
        // The search's field takes the keyboard a moment after the search appears.
        for _ in 0..<15 {
            if await interface.caret(pid: pid) != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        KeyStroke.parse("cmd+a")?.post(to: pid)
        try? await Task.sleep(nanoseconds: 80_000_000)
        return await paste(query, pid: pid)
    }

    /// Pastes text where the keyboard is, as dictation does: an input method cannot swallow it, and the clipboard
    /// is put back. Tells whether it arrived: true, false, or nil when the field cannot be read to check.
    private func paste(_ text: String, pid: pid_t) async -> Bool? {
        let before = await interface.caret(pid: pid)
        let delivery = ClipboardTextDelivery()
        defer { delivery.restore(confirmed: true) }
        delivery.post(text, pid: pid)
        guard let before else {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return nil
        }
        // Most apps take the paste from the keyboard's path. Feishu's search takes it only when addressed to the app.
        for attempt in 0..<2 {
            if attempt == 1 { KeyStroke.parse("cmd+v")?.post(to: pid) }
            for _ in 0..<(attempt == 0 ? 6 : 10) {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if let now = await interface.caret(pid: pid), now != before { return true }
            }
        }
        return false
    }

    private func activateApp(_ arguments: JSONValue) async -> ToolOutcome {
        guard let name = arguments["app"]?.string, let application = resolve(name) else {
            return .failure("No such app. Use an id or a name from list_targets.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        do {
            if let open = arguments["open"]?.string, !open.isEmpty {
                let expanded = (open as NSString).expandingTildeInPath
                guard let item = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : URL(string: open) else { return .failure("Not a path or URL: \(open)") }
                _ = try await NSWorkspace.shared.open([item], withApplicationAt: application, configuration: configuration)
            } else { _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration) }
        } catch { return .failure("The app could not be opened.") }
        let app = await front { $0.bundleURL?.standardizedFileURL == application.standardizedFileURL }
        if let app { target = app.processIdentifier }
        return .ok(["in_front": .bool(app != nil), "app": .string(application.deletingPathExtension().lastPathComponent)], verified: app != nil)
    }

    private func choose(_ arguments: JSONValue) async -> ToolOutcome {
        let options = arguments["options"]?.array ?? []
        let labels = options.map { ($0["label"]?.string ?? "") + ($0["detail"]?.string.map { " · \($0)" } ?? "") }
        guard !labels.isEmpty, let index = await ask?(.choose(arguments["question"]?.string ?? "", labels)), options.indices.contains(index) else {
            return .ok("cancelled")
        }
        return .ok(["chosen": options[index]["id"] ?? .null])
    }

    // MARK: The window in front

    private var movedAway: ToolOutcome { .failure("The app being operated is no longer in front. Stop and call need_user.") }
    /// The operated app, only while it is still the one in front.
    private func operated() -> pid_t? {
        guard let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { return nil }
        return target
    }
    // Whether the user is asked first was settled before these run, by the gateway and `question`.
    // Each still checks that its app is in front: the user may have moved on while a question was showing.

    private func press(_ arguments: JSONValue) async -> ToolOutcome {
        guard operated() != nil else { return movedAway }
        guard let control = await interface.control(arguments["id"]?.string ?? "") else {
            return .failure("No such control in the latest snapshot. Take a new snapshot.")
        }
        return await interface.press(control)
    }

    private func key(_ arguments: JSONValue) async -> ToolOutcome {
        guard let pid = operated() else { return movedAway }
        guard let keys = arguments["keys"]?.string, let stroke = KeyStroke.parse(keys) else {
            return .failure("Unrecognised keys. Use forms like cmd+p, ctrl+tab, escape, down or return.")
        }
        stroke.post(to: pid)
        return .ok(["sent": .string(keys)])
    }

    private func menu(_ arguments: JSONValue) async -> ToolOutcome {
        guard let pid = operated() else { return movedAway }
        let path = arguments["path"]?.array?.compactMap(\.string) ?? []
        let found = await interface.menuItem(pid: pid, path: path)
        guard let item = found.control else { return .failure(found.error) }
        return await interface.press(item)
    }

    private func type(_ arguments: JSONValue) async -> ToolOutcome {
        guard let pid = operated() else { return movedAway }
        guard let text = arguments["text"]?.string, !text.isEmpty else { return .failure("Nothing to type.") }
        var control: InterfaceControl?
        if let id = arguments["id"]?.string {
            control = await interface.control(id)
            guard control != nil else { return .failure("No such control in the latest snapshot. Take a new snapshot.") }
        }
        if let refusal = await interface.focusForTyping(pid: pid, control: control) { return .failure(refusal) }
        guard operated() == pid else { return movedAway }
        switch await paste(text, pid: pid) {
        case true?: return .ok(["typed_characters": .number(Double(text.count)), "note": "The text is in the field. It was not submitted."])
        case nil: return .ok(["typed_characters": .number(Double(text.count)),
                              "note": "Sent, but this field cannot be read to check that it arrived. It was not submitted."], verified: false)
        case false?: return .failure("The text did not go in: the field did not change. Take a snapshot to see what has the keyboard.")
        }
    }

    // MARK: Helpers

    private func observe() async -> TargetObservation {
        await withCheckedContinuation { continuation in adapter.requestRefresh { continuation.resume(returning: $0) } }
    }
    private func installed(_ bundleIDs: [String]) -> URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }
    private func bringForward(_ bundleIDs: [String]) async -> NSRunningApplication? {
        guard let application = installed(bundleIDs) else { return nil }
        _ = try? await NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration())
        return await front(bundleIDs)
    }
    private func front(_ bundleIDs: [String]) async -> NSRunningApplication? {
        await front { bundleIDs.contains($0.bundleIdentifier ?? "") }
    }
    private func front(_ matches: (NSRunningApplication) -> Bool) async -> NSRunningApplication? {
        for _ in 0..<30 {
            if let app = NSWorkspace.shared.frontmostApplication, matches(app) {
                // Frontmost comes first; the window follows when the app arrives from another Space.
                for _ in 0..<15 {
                    if await interface.hasWindowHere(pid: app.processIdentifier) { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                return app
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    /// An adapter id, a running app's name or bundle id, or an installed app's name.
    private func resolve(_ name: String) -> URL? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let entry = Self.targets.first(where: { $0.id == wanted }) { return installed(entry.bundleIDs) }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        func names(_ app: NSRunningApplication) -> [String] {
            [app.localizedName, app.bundleURL?.deletingPathExtension().lastPathComponent, app.bundleIdentifier].compactMap { $0?.lowercased() }
        }
        if let app = running.first(where: { names($0).contains(wanted) }) ?? running.first(where: { names($0).contains { $0.contains(wanted) } }) {
            return app.bundleURL
        }
        if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return application }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        return folders.map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".app") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The name the user knows an app by; some report a shorter one to the system (Visual Studio Code is "Code").
    private static func displayName(_ app: NSRunningApplication) -> String {
        let reported = app.localizedName ?? "", onDisk = app.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
        return onDisk.isEmpty || onDisk.localizedCaseInsensitiveContains(reported) ? (onDisk.isEmpty ? reported : onDisk) : "\(reported) (\(onDisk))"
    }
}

extension KeyStroke {
    /// Return sends a message from a multi-line field and submits with ⌘; ⌘⌫ deletes and ⌘Q quits.
    func needsConfirmation(focusedRole: String) -> Bool {
        if isReturn { return flags.contains(.maskCommand) || focusedRole == "AXTextArea" }
        return flags.contains(.maskCommand) && (code == 51 || code == 12)
    }
}
