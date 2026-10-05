import AppKit
import ApplicationServices
import XCTest
import AU05Device
import SpeechInput
@testable import VibeKeyBridge

/// Opt-in live acceptance in an iTerm2 window the test opens for itself;
/// ordinary unit tests never touch a terminal, and no existing session is used.
final class TerminalLiveTests: XCTestCase {
    private static let frame = CGRect(x: 60, y: 80, width: 951, height: 691)

    /// The dedicated window. Its prompt row is read back to check each step;
    /// any other window, tab or app taking the keyboard ends the run.
    private struct Terminal {
        let pid: pid_t
        let window: AXUIElement
        let area: AXUIElement
        let device: String
        let launcher: URL

        /// Runs `command` in a new iTerm2 window placed at a frame no other window is expected to have.
        static func open(running command: String) throws -> Terminal {
            let launcher = FileManager.default.temporaryDirectory.appendingPathComponent("vibewand-terminal-\(UUID().uuidString).command")
            try "#!/bin/zsh -li\n\(command)\n".write(to: launcher, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
            var failure: NSDictionary?
            let device = NSAppleScript(source: """
                tell application "iTerm2"
                    set testWindow to (create window with default profile command "\(launcher.path)")
                    set bounds of testWindow to {\(Int(frame.minX)), \(Int(frame.minY)), \(Int(frame.maxX)), \(Int(frame.maxY))}
                    return tty of current session of testWindow
                end tell
                """)?.executeAndReturnError(&failure).stringValue
            guard let device, let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first else {
                throw stopped("iTerm2 did not open the test window: \(failure ?? [:])")
            }
            for _ in 0..<50 {
                let windows = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
                if let window = windows.first(where: { rect($0).map { abs($0.minX - frame.minX) < 3 && abs($0.minY - frame.minY) < 3 && abs($0.width - frame.width) < 3 } == true }),
                   let area = textArea(in: window) {
                    return Terminal(pid: app.processIdentifier, window: window, area: area, device: device, launcher: launcher)
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw stopped("The test window is not visible to accessibility")
        }

        /// Ends whatever the window runs; iTerm2 closes a window whose session has ended.
        func close() {
            try? FileManager.default.removeItem(at: launcher)
            let listing = Process(), output = Pipe()
            listing.executableURL = URL(fileURLWithPath: "/bin/ps")
            listing.arguments = ["-t", (device as NSString).lastPathComponent, "-o", "pid="]
            listing.standardOutput = output
            guard (try? listing.run()) != nil else { return }
            listing.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for process in text.split(whereSeparator: \.isWhitespace).compactMap({ pid_t($0) }) { kill(process, SIGKILL) }
        }

        var screen: TerminalScreen? { TerminalScreen(area: area) }
        var title: String { Self.attribute(window, kAXTitleAttribute) as? String ?? "" }
        /// The cursor's row up to the cursor, and the cursor's offset in the whole text.
        var cursor: (row: String, offset: Int) {
            guard let value = Self.attribute(area, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return ("", -1) }
            var range = CFRange()
            guard AXValueGetValue(value as! AXValue, .cfRange, &range), let text = Self.attribute(area, kAXValueAttribute) as? NSString,
                  range.location >= 0, range.location <= text.length else { return ("", -1) }
            let row = text.substring(to: range.location).components(separatedBy: "\n").last ?? ""
            return (row.replacingOccurrences(of: "\0", with: " "), range.location)
        }
        var owned: Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
            let app = AXUIElementCreateApplication(pid)
            return Self.attribute(app, kAXFocusedWindowAttribute).map(CFHash) == CFHash(window) &&
                Self.attribute(app, kAXFocusedUIElementAttribute).map(CFHash) == CFHash(area)
        }

        static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
        }
        static func rect(_ node: AXUIElement) -> CGRect? {
            guard let position = attribute(node, kAXPositionAttribute), let size = attribute(node, kAXSizeAttribute) else { return nil }
            var point = CGPoint.zero, extent = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
            return CGRect(origin: point, size: extent)
        }
        /// The session's text area is the large one; iTerm2 can put banners with small text views above it.
        static func textArea(in root: AXUIElement) -> AXUIElement? {
            var queue = [(root, 0)], index = 0, best: (AXUIElement, CGFloat)?
            while index < queue.count {
                let (node, depth) = queue[index]; index += 1
                if attribute(node, kAXRoleAttribute) as? String == "AXTextArea", let size = rect(node)?.size,
                   size.width * size.height > best?.1 ?? 0 { best = (node, size.width * size.height) }
                if depth < 6, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                    queue += children.prefix(12).map { ($0, depth + 1) }
                }
            }
            return best?.0
        }
    }

    private static func stopped(_ message: String) -> NSError {
        NSError(domain: "VibeWand.TerminalAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private final class Transcript: @unchecked Sendable { var text = "" }

    @MainActor
    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor
    private func wait(_ stage: String, seconds: Double = 8, until matches: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !matches() {
            guard Date() < deadline else { throw Self.stopped("Timed out: \(stage)") }
            try await pause(0.1)
        }
        print("Terminal acceptance:", stage)
    }

    @MainActor
    func testLiveDraftEditingListsAndBusyAgent() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let command = environment["VIBEWAND_TERMINAL_LIVE"], !command.isEmpty else {
            throw XCTSkip("Requires explicitly enabled live terminal acceptance")
        }
        guard AXIsProcessTrusted() else { throw Self.stopped("Native test process lacks Accessibility access") }
        let terminal = try Terminal.open(running: command)
        defer { terminal.close() }
        try await wait("agent prompt ready", seconds: 60) { terminal.screen?.prompt() == .empty }

        // Take the keyboard only once the person at the Mac has paused, and hand it back afterwards.
        try await wait("keyboard and mouse idle", seconds: 600) {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!) > 4
        }
        let previous = NSWorkspace.shared.frontmostApplication
        defer { previous?.activate(options: []) }
        _ = AXUIElementPerformAction(terminal.window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: terminal.pid)?.activate(options: [])
        try await wait("test window focused", seconds: 4) { terminal.owned }

        let suite = "VibeWand.TerminalLive.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let speech = SpeechPreferences(defaults: preferences)
        var configuration = speech.load()
        configuration.mode = .builtIn; configuration.provider = .system; configuration.textStyle = .verbatim
        try speech.save(configuration)
        let transcript = Transcript()
        let template = DeviceTemplateID(rawValue: environment["VIBEWAND_TERMINAL_DEVICE"] ?? "") ?? .vibeKey
        let templates = DeviceTemplateStore(defaults: preferences)
        try templates.select(template)
        // The production runtime, fed with presses instead of hardware and transcripts instead of audio.
        let runtime = BridgeRuntime(source: UnconfiguredHIDSource(template: template.template), templates: templates,
            sourceFactory: { _, id in UnconfiguredHIDSource(template: id.template) },
            voiceInput: VoiceInputController(preferences: speech, engineFactory: { _ in TranscriptReplayEngine(previews: [transcript.text]) }))
        runtime.start(demo: false)
        defer { runtime.stop() }

        // The controller layout deletes with □, confirms with ○ and sends Escape with ×.
        let controller = template == .dualSense
        let delete: DeviceControl = controller ? .dial : .escape, confirm: DeviceControl = controller ? .escape : .ok
        let escape: DeviceControl = controller ? .ok : .escape
        func step() throws { guard terminal.owned else { throw Self.stopped("The test window lost the keyboard; run stopped") } }
        func tap(_ control: DeviceControl) async throws {
            try step(); runtime.handle(control, phase: .down); try await pause(0.08); runtime.handle(control, phase: .up)
        }
        func hold(_ control: DeviceControl, _ seconds: Double) async throws {
            try step(); runtime.handle(control, phase: .down); try await pause(seconds); runtime.handle(control, phase: .up)
        }
        func turn(_ control: DeviceControl, _ count: Int) async throws {
            for _ in 0..<count { try step(); runtime.handle(control, phase: .pulse); try await pause(0.2) }
        }
        func openChats() async throws { if controller { try await hold(.ok, 0.9) } else { try await tap(.dial) } }
        func openModels() async throws { try await hold(controller ? .escape : .dial, 0.9) }
        func dictate(_ text: String) async throws {
            try step(); transcript.text = text
            runtime.replaySpeech(duration: 0.25)
            // Codex shows a leading "!" as its shell mark, so only the end of the text is compared.
            try await wait("dictated text on the prompt") { terminal.cursor.row.hasSuffix(String(text.suffix(6))) }
        }
        func clearDraft() async throws {
            try step(); runtime.handle(delete, phase: .down)
            defer { runtime.handle(delete, phase: .up) }
            try await wait("draft cleared") { terminal.owned && runtime.snapshot.scope == .reading }
        }
        try await wait("empty prompt recognised") { runtime.snapshot.scope == .reading && terminal.screen?.prompt() == .empty }

        // Dictation is pasted, then edited: tap and hold delete, turning moves the cursor.
        let text = "vibewand terminal acceptance"
        try await dictate(text)
        try await wait("draft recognised") { runtime.snapshot.scope == .editing }
        try await tap(delete)
        try await wait("tap deleted one character") { terminal.cursor.row.hasSuffix(String(text.dropLast())) }
        try await hold(delete, 1.2)
        try await wait("hold kept deleting") { !terminal.cursor.row.contains("accept") }
        try await pause(0.5) // The last repeat may still be on its way to the screen.
        var offset = terminal.cursor.offset
        try await turn(.left, 3)
        try await wait("cursor moved left") { terminal.cursor.offset == offset - 3 }
        try await hold(delete, 3)
        try await wait("everything before the cursor deleted") { terminal.screen?.prompt() == .empty }
        try await pause(0.5)
        XCTAssertEqual(runtime.snapshot.scope, .editing, "Text behind the cursor is still a draft")
        offset = terminal.cursor.offset
        try await turn(.right, 3)
        try await wait("cursor moved right") { terminal.cursor.offset == offset + 3 }

        // A list is never opened over a draft, and its command is never left behind.
        let kept = terminal.cursor.row
        try await openChats()
        try await pause(1.2)
        XCTAssertEqual(terminal.cursor.row, kept)
        try await clearDraft()
        try await wait("prompt empty again") { terminal.screen?.prompt() == .empty }

        // Chats and models: typed at the empty prompt, followed while shown, left with Escape.
        for scope in [GestureScope.sessions, .models] {
            if scope == .sessions { try await openChats() } else { try await openModels() }
            try await wait("\(scope.rawValue) list shown") { runtime.snapshot.scope == scope && terminal.screen?.prompt() == .list }
            try await turn(.right, 2)
            try await turn(.left, 1)
            XCTAssertEqual(runtime.snapshot.scope, scope)
            // In its chat list the controller cancels with ○; × confirms there.
            let leave: DeviceControl = controller && scope == .sessions ? .escape : escape
            for _ in 0..<3 where runtime.snapshot.scope != .reading { try await tap(leave); try await pause(1) }
            try await wait("\(scope.rawValue) list left") { runtime.snapshot.scope == .reading && terminal.screen?.prompt() == .empty }
        }

        // A working agent spins a mark in the window title; buttons must keep answering.
        guard let busy = environment["VIBEWAND_TERMINAL_BUSY"], !busy.isEmpty else { return }
        try await dictate(busy)
        try await tap(confirm)
        var titles: Set<String> = []
        for _ in 0..<20 { titles.insert(terminal.title); try await pause(0.1) }
        XCTAssertGreaterThan(titles.count, 1, "The agent did not animate its title; the busy check is void")
        try await dictate("busy")
        try await tap(delete)
        try await wait("deleted while busy") { terminal.cursor.row.hasSuffix("bus") }
        try await clearDraft()
        try await tap(escape)
        try await wait("Escape interrupted the agent") {
            let before = terminal.title
            Thread.sleep(forTimeInterval: 0.3)
            return terminal.title == before && terminal.screen?.prompt() == .empty
        }
    }
}
