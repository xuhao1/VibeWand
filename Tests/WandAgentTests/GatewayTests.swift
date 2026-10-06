import XCTest
@testable import WandAgent

/// Stands in for the app: records what reached the desktop.
final class FakeHost: ToolHost {
    var performed: [String] = []
    var confirmations: [String] = []
    var allow = true
    /// Tools whose call the host itself holds to be risky.
    var risky: Set<String> = []
    var result: (String, JSONValue) -> ToolOutcome = { _, _ in .ok("ok") }
    var delay: UInt64 = 0
    private(set) var running = 0, overlap = false
    func perform(_ tool: String, _ arguments: JSONValue) async -> ToolOutcome {
        running += 1; if running > 1 { overlap = true }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        performed.append(tool); running -= 1
        return result(tool, arguments)
    }
    func confirm(_ tool: String, _ arguments: JSONValue, every: Bool) async -> Bool? {
        guard every || risky.contains(tool) else { return nil }
        confirmations.append(tool); return allow
    }
}

final class GatewayTests: XCTestCase {
    private func journalRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vw-journal-\(UUID().uuidString)")
    }
    private func lines(_ journal: TaskJournal) throws -> [JSONValue] {
        try String(contentsOf: journal.directory.appendingPathComponent("journal.jsonl"), encoding: .utf8)
            .split(separator: "\n").compactMap { JSONValue(data: Data($0.utf8)) }
    }

    func testOnlyCataloguedToolsReachTheHost() async {
        let host = FakeHost(), gateway = Gateway(host: host)
        let shell = await gateway.call("bash", ["command": "rm -rf ~"])
        XCTAssertTrue(shell.isError)
        let listed = await gateway.call("list_targets", [:])
        XCTAssertFalse(listed.isError)
        XCTAssertEqual(host.performed, ["list_targets"])
    }

    func testTheKernelEndsATaskOnlyThroughFinishOrNeedUser() async {
        let host = FakeHost(), gateway = Gateway(host: host)
        _ = await gateway.call("open_session", ["app": "codex", "id": "t-1"])
        var ending = await gateway.ending
        XCTAssertNil(ending)
        _ = await gateway.call("finish", ["summary": "已切到会话"])
        ending = await gateway.ending
        XCTAssertEqual(ending, .finished("已切到会话"))
        // Ending never touches the desktop, and nothing runs after it.
        let late = await gateway.call("ui_press", ["id": "e1"])
        XCTAssertTrue(late.isError)
        XCTAssertEqual(host.performed, ["open_session"])

        let other = Gateway(host: host)
        _ = await other.call("need_user", ["reason": "没有找到这个会话"])
        ending = await other.ending
        XCTAssertEqual(ending, .needsUser("没有找到这个会话"))
    }

    func testStopRefusesEverythingAfterIt() async {
        let host = FakeHost(), gateway = Gateway(host: host)
        _ = await gateway.call("ui_snapshot", [:])
        await gateway.stop()
        let pressed = await gateway.call("ui_press", ["id": "e3"])
        XCTAssertTrue(pressed.isError)
        XCTAssertEqual(host.performed, ["ui_snapshot"])
    }

    func testStepLimitEndsARunawayLoop() async {
        let host = FakeHost(), gateway = Gateway(host: host)
        for _ in 0..<Gateway.stepLimit { _ = await gateway.call("ui_snapshot", [:]) }
        let extra = await gateway.call("ui_snapshot", [:])
        XCTAssertTrue(extra.isError)
        XCTAssertEqual(host.performed.count, Gateway.stepLimit)
        // Told to say how far it got, the model still can.
        let closing = await gateway.call("need_user", ["reason": "步数用完了，只找到两个"])
        XCTAssertFalse(closing.isError)
        let ending = await gateway.ending
        XCTAssertEqual(ending, .needsUser("步数用完了，只找到两个"))
    }

    /// Only the tools a gateway was given exist for it: the window's picture and the pointer in it are there
    /// when the user allows them.
    func testAToolThatWasNotMountedIsUnknown() async {
        let host = FakeHost(), closed = Gateway(host: host)
        for tool in ["ui_screenshot", "ui_click"] {
            let refused = await closed.call(tool, ["x": 10, "y": 10])
            XCTAssertTrue(refused.isError, tool)
        }
        XCTAssertTrue(host.performed.isEmpty)
        let seeing = Gateway(tools: ToolCatalog.mounted(sight: true), host: host)
        let shown = await seeing.call("ui_screenshot", [:])
        XCTAssertFalse(shown.isError)
        XCTAssertEqual(host.performed, ["ui_screenshot"])
        XCTAssertTrue(host.confirmations.isEmpty, "looking changes nothing and is never asked about")
        // A click is an action like a press: the host is asked what stands there, and every one waits when the user asks for that.
        _ = await seeing.call("ui_click", ["id": "t3"])
        XCTAssertTrue(host.confirmations.isEmpty)
        host.risky = ["ui_click"]
        _ = await seeing.call("ui_click", ["id": "t4"])
        host.risky = []
        let asking = Gateway(tools: ToolCatalog.mounted(sight: true), host: host, permission: .ask)
        _ = await asking.call("ui_click", ["x": 10, "y": 10])
        XCTAssertEqual(host.confirmations, ["ui_click", "ui_click"])
        XCTAssertEqual(host.performed, ["ui_screenshot", "ui_click", "ui_click", "ui_click"])
    }

    /// A harness's own tool that wants to leave its sandbox is the user's to allow, in whatever mode.
    func testARuntimeToolLeavingItsSandboxAlwaysAsksAndTheAnswerIsRecorded() async throws {
        let journal = try TaskJournal(root: journalRoot())
        defer { TaskJournal.clear(root: journal.directory.deletingLastPathComponent()) }
        let host = FakeHost(), gateway = Gateway(host: host, permission: .risky, journal: journal)
        var allowed = await gateway.approve("bash", ["command": "rm -rf build"])
        XCTAssertTrue(allowed)
        host.allow = false
        allowed = await gateway.approve("bash", ["command": "rm -rf ~"])
        XCTAssertFalse(allowed)
        XCTAssertEqual(host.confirmations, ["bash", "bash"])
        XCTAssertTrue(host.performed.isEmpty, "the runtime runs its own tools; the gateway only asks")
        XCTAssertEqual(try lines(journal).map { "\($0["kind"]?.string ?? "") \($0["tool"]?.string ?? "")" }, ["confirmed bash", "declined bash"])
        // After stop nothing is allowed and nobody is asked.
        host.allow = true
        await gateway.stop()
        allowed = await gateway.approve("bash", ["command": "ls"])
        XCTAssertFalse(allowed)
        XCTAssertEqual(host.confirmations.count, 2)
    }

    func testCallsRequestedTogetherRunOneAtATime() async {
        let host = FakeHost(); host.delay = 20_000_000
        let gateway = Gateway(host: host)
        async let first = gateway.call("ui_press", ["id": "e1"])
        async let second = gateway.call("ui_press", ["id": "e2"])
        async let third = gateway.call("ui_key", ["keys": "cmd+p"])
        _ = await (first, second, third)
        XCTAssertFalse(host.overlap)
        XCTAssertEqual(host.performed.count, 3)
    }

    func testSubmissionWaitsForTheUserAndADeclineReachesNothing() async {
        let submit = ToolDefinition(name: "delegate", summary: "", schema: [:], effect: .submit)
        let host = FakeHost(), gateway = Gateway(tools: [submit] + ToolCatalog.all, host: host)
        host.allow = false
        let declined = await gateway.call("delegate", ["app": "codex"])
        XCTAssertTrue(declined.isError)
        XCTAssertEqual(host.performed, [])
        host.allow = true
        let accepted = await gateway.call("delegate", ["app": "codex"])
        XCTAssertFalse(accepted.isError)
        XCTAssertEqual(host.confirmations, ["delegate", "delegate"])
        XCTAssertEqual(host.performed, ["delegate"])
        // Navigation is not held up by a question unless the user asked to confirm every step.
        _ = await gateway.call("open_session", ["app": "codex", "id": "t"])
        XCTAssertEqual(host.confirmations.count, 2)
    }

    func testPermissionModeDecidesWhatWaitsForTheUser() async throws {
        let journal = try TaskJournal(root: journalRoot())
        defer { TaskJournal.clear(root: journal.directory.deletingLastPathComponent()) }
        let host = FakeHost(); host.risky = ["ui_press"]
        // Every step: whatever changes something asks first; reading never does.
        let asking = Gateway(host: host, permission: .ask, journal: journal)
        _ = await asking.call("ui_snapshot", [:])
        _ = await asking.call("activate_app", ["app": "Calculator"])
        _ = await asking.call("ui_type", ["text": "hello"])
        XCTAssertEqual(host.confirmations, ["activate_app", "ui_type"])
        XCTAssertEqual(host.performed, ["ui_snapshot", "activate_app", "ui_type"])
        host.allow = false
        let refused = await asking.call("ui_key", ["keys": "cmd+p"])
        XCTAssertTrue(refused.isError)
        XCTAssertEqual(host.performed.count, 3)
        XCTAssertEqual(try lines(journal).compactMap { $0["kind"]?.string }.filter { $0 == "confirmed" || $0 == "declined" }, ["confirmed", "confirmed", "declined"])

        // Risky only: the host's own judgement of the call decides.
        host.confirmations = []; host.performed = []; host.allow = true
        let guarded = Gateway(host: host, permission: .risky)
        _ = await guarded.call("activate_app", ["app": "Calculator"])
        _ = await guarded.call("ui_press", ["id": "e1"])
        XCTAssertEqual(host.confirmations, ["ui_press"])

        // Bypass: nothing asks, not even what the host holds to be risky, and a submission goes straight through.
        host.confirmations = []; host.performed = []
        let submit = ToolDefinition(name: "delegate", summary: "", schema: [:], effect: .submit)
        let open = Gateway(tools: [submit] + ToolCatalog.all, host: host, permission: .bypass)
        _ = await open.call("ui_press", ["id": "e1"])
        _ = await open.call("delegate", [:])
        XCTAssertEqual(host.confirmations, [])
        XCTAssertEqual(host.performed, ["ui_press", "delegate"])
    }

    func testTheStepLimitCanBeSetPerInstruction() async {
        let host = FakeHost(), gateway = Gateway(host: host, stepLimit: 2)
        _ = await gateway.call("ui_snapshot", [:]); _ = await gateway.call("ui_snapshot", [:])
        let extra = await gateway.call("ui_snapshot", [:])
        XCTAssertTrue(extra.isError)
        XCTAssertEqual(host.performed.count, 2)
    }

    func testUnverifiedActionsAreRememberedAndTheJournalKeepsWhatEachToolAnswered() async throws {
        let journal = try TaskJournal(root: journalRoot())
        defer { TaskJournal.clear(root: journal.directory.deletingLastPathComponent()) }
        let host = FakeHost(), gateway = Gateway(host: host, journal: journal)
        host.result = { tool, _ in
            tool == "open_session" ? .ok(["opened": true], verified: false)
                : tool == "ui_press" ? .failure("No control e9.") : .ok("window \"私有标题\"")
        }
        _ = await gateway.call("ui_snapshot", [:])
        _ = await gateway.call("open_session", ["app": "codex", "id": "t-9"])
        _ = await gateway.call("ui_press", ["id": "e9"])
        let unverified = await gateway.unverified
        XCTAssertEqual(unverified, ["open_session"])
        let recorded = try lines(journal)
        XCTAssertEqual(recorded.compactMap { $0["kind"]?.string }, ["call", "result", "call", "result", "call", "result"])
        XCTAssertEqual(recorded[2]["arguments"]?["id"]?.string, "t-9")
        XCTAssertEqual(recorded[3]["verified"], false)
        XCTAssertEqual(recorded[5]["ok"], false)
        XCTAssertEqual(recorded[5]["text"]?.string, "No control e9.")
        // The history shows what the model was given, cut where a listing runs long.
        XCTAssertEqual(recorded[1]["text"]?.string, "window \"私有标题\"")
        host.result = { _, _ in .ok(.string(String(repeating: "x", count: TaskJournal.resultLimit + 500))) }
        _ = await gateway.call("ui_snapshot", [:])
        XCTAssertEqual(try lines(journal).last?["text"]?.string?.count, TaskJournal.resultLimit)
    }

    func testAPictureAToolShowedIsKeptBesideTheRecordAndCallsOfTheRuntimesOwnToolsAreRecordedToo() async throws {
        let root = journalRoot()
        defer { TaskJournal.clear(root: root) }
        let journal = try TaskJournal(root: root)
        let host = FakeHost(), gateway = Gateway(tools: ToolCatalog.mounted(sight: true), host: host, journal: journal)
        let picture = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        host.result = { tool, _ in tool == "ui_screenshot" ? ToolOutcome(text: "window \"备忘录\", 800×600 px", image: picture) : .ok("ok") }
        // The runtime reports every call; VibeWand's own are recorded by the gateway that ran them, once.
        journal.note(.toolStarted(id: "1", name: "mcp__vibewand__ui_screenshot"))
        let shown = await gateway.call("ui_screenshot", [:])
        XCTAssertEqual(shown.image, picture)
        journal.note(.toolEnded(id: "1", failed: false, text: "window …"))
        journal.note(.toolStarted(id: "2", name: "bash", input: ["command": "ls ~/Desktop"]))
        journal.note(.toolEnded(id: "2", failed: false, text: "notes.md"))
        journal.note(.toolStarted(id: "3", name: "read", input: ["path": "/nowhere"]))
        journal.note(.toolEnded(id: "3", failed: true, text: "No such file"))
        let recorded = try lines(journal)
        XCTAssertEqual(recorded.map { "\($0["kind"]?.string ?? "") \($0["tool"]?.string ?? "")" },
                       ["call ui_screenshot", "result ui_screenshot", "call bash", "result bash", "call read", "result read"])
        XCTAssertEqual(recorded[1]["image"], "picture-1.jpg")
        XCTAssertEqual(try Data(contentsOf: journal.directory.appendingPathComponent("picture-1.jpg")), picture)
        XCTAssertEqual(recorded[2]["arguments"], ["command": "ls ~/Desktop"])
        XCTAssertEqual(recorded[3]["text"], "notes.md")
        XCTAssertEqual(recorded[5]["ok"], false)
        // Read back, the record knows where its pictures are, and counts every tool call as a step.
        let record = try XCTUnwrap(TaskJournal.recent(root: root).first)
        XCTAssertEqual(record.directory.path, journal.directory.path)
        XCTAssertEqual(record.steps, 3)
    }

    func testTheJournalWritesThinkingWholeBeforeTheStepItLedToAndReadsBackAsARecord() throws {
        let root = journalRoot()
        defer { TaskJournal.clear(root: root) }
        let journal = try TaskJournal(root: root)
        journal.record("instruction", ["text": "切到 Codex", "app": "Finder", "model": "deepseek-flash", "turn": 2])
        journal.note(.thought("用户想去")); journal.note(.thought(" Codex。"))
        journal.note(.toolStarted(id: "1", name: "mcp__vibewand__activate_app"))
        journal.record("call", ["tool": "activate_app", "arguments": ["app": "codex"]])
        journal.record("result", ["tool": "activate_app", "ok": true, "verified": true, "text": "{}"])
        journal.note(.toolEnded(id: "1", failed: false))
        journal.note(.usage(used: 1200, size: 8000))
        journal.note(.message("好了"))
        journal.settle()
        journal.record("end", ["reason": "end_turn", "finished": true, "said": "已切到 Codex"])
        XCTAssertEqual(try lines(journal).compactMap { $0["kind"]?.string },
                       ["instruction", "thought", "call", "result", "usage", "message", "end"])
        XCTAssertEqual(try lines(journal)[1]["text"]?.string, "用户想去 Codex。")

        let record = try XCTUnwrap(TaskJournal.recent(root: root).first)
        XCTAssertEqual(record.instruction, "切到 Codex")
        XCTAssertEqual(record.app, "Finder")
        XCTAssertEqual(record.model, "deepseek-flash")
        XCTAssertEqual(record.turn, 2)
        XCTAssertEqual(record.steps, 1)
        XCTAssertEqual(record.usage?.used, 1200)
        XCTAssertEqual(record.usage?.size, 8000)
        XCTAssertEqual(record.outcome?.text, "已切到 Codex")
        XCTAssertEqual(record.outcome?.finished, true)
        XCTAssertNotNil(record.started)
        // Newest first, and an instruction that was interrupted has no outcome.
        let later = try TaskJournal(root: root, now: Date().addingTimeInterval(5))
        later.record("instruction", ["text": "第二条"])
        let recent = TaskJournal.recent(root: root)
        XCTAssertEqual(recent.map(\.instruction), ["第二条", "切到 Codex"])
        XCTAssertNil(recent[0].outcome)
        XCTAssertEqual(TaskJournal.recent(root: root, limit: 1).count, 1)
    }

    func testJournalsAreClearedByAge() throws {
        let root = journalRoot()
        let journal = try TaskJournal(root: root)
        journal.record("instruction", ["text": "切到 Codex"])
        XCTAssertEqual(try lines(journal).first?["text"]?.string, "切到 Codex")
        TaskJournal.clear(root: root, olderThan: 14)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.directory.path))
        TaskJournal.clear(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.directory.path))
    }
}
