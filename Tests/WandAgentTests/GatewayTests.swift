import XCTest
@testable import WandAgent

/// Stands in for the app: records what reached the desktop.
final class FakeHost: ToolHost {
    var performed: [String] = []
    var confirmations: [String] = []
    var allow = true
    var result: (String, JSONValue) -> ToolOutcome = { _, _ in .ok("ok") }
    var delay: UInt64 = 0
    private(set) var running = 0, overlap = false
    func perform(_ tool: String, _ arguments: JSONValue) async -> ToolOutcome {
        running += 1; if running > 1 { overlap = true }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        performed.append(tool); running -= 1
        return result(tool, arguments)
    }
    func confirm(_ tool: String, _ arguments: JSONValue) async -> Bool { confirmations.append(tool); return allow }
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
        // Navigation is never held up by a question.
        _ = await gateway.call("open_session", ["app": "codex", "id": "t"])
        XCTAssertEqual(host.confirmations.count, 2)
    }

    func testUnverifiedActionsAreRememberedAndTheJournalKeepsNoResultText() async throws {
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
        XCTAssertEqual(recorded[5]["error"]?.string, "No control e9.")
        XCTAssertFalse(recorded.map(\.text).joined().contains("私有标题"))
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
