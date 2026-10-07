import XCTest
@testable import WandAgent

final class CatalogTests: XCTestCase {
    /// The catalog is the model's whole reach. A tool added here must be a deliberate decision.
    func testTheCatalogIsExactlyTheDesignedToolList() {
        XCTAssertEqual(ToolCatalog.all.map(\.name), [
            "list_targets", "find_sessions", "open_session", "search_in_app", "activate_app", "choose", "finish", "need_user",
            "ui_snapshot", "ui_press", "ui_key", "ui_menu", "ui_type"
        ])
        for tool in ToolCatalog.mounted(sight: true) {
            XCTAssertEqual(tool.schema["type"]?.string, "object", tool.name)
            let properties = tool.schema["properties"] ?? [:]
            for required in tool.schema["required"]?.array ?? [] {
                XCTAssertNotNil(properties[required.string ?? ""], "\(tool.name) requires an undeclared \(required)")
            }
            XCTAssertFalse(tool.summary.contains("\n"), tool.name)
        }
        XCTAssertFalse(ToolCatalog.all.contains { $0.effect == .submit })
    }

    /// The choice of voice is one more tool, there only while VibeWand speaks in a voice of the voice service.
    /// It lists the voices when called with nothing, so no name is required.
    func testTheChoiceOfVoiceIsMountedOnlyWhileAServiceVoiceSpeaks() {
        XCTAssertEqual(ToolCatalog.mounted(sight: false, voices: true).map(\.name), ToolCatalog.all.map(\.name) + ["set_voice"])
        XCTAssertEqual(ToolCatalog.mounted(sight: true, voices: true).map(\.name).suffix(3), ["ui_screenshot", "ui_click", "set_voice"])
        XCTAssertEqual(ToolCatalog.voice.effect, .read)
        XCTAssertEqual(ToolCatalog.voice.schema["required"]?.array, [])
        XCTAssertFalse(ToolCatalog.voice.summary.contains("\n"))
    }

    /// Seeing the window is two more tools, mounted only when the user has turned it on: the window's picture,
    /// and the pointer at a place in it. Without it no point is ever clicked.
    func testThePictureOfTheWindowAndThePointerAreMountedOnlyWhenTheUserLetsTheModelSee() {
        XCTAssertEqual(ToolCatalog.mounted(sight: false), ToolCatalog.all)
        XCTAssertEqual(ToolCatalog.mounted(sight: true).map(\.name), ToolCatalog.all.map(\.name) + ["ui_screenshot", "ui_click"])
        XCTAssertEqual(ToolCatalog.seeing.map(\.effect), [.read, .navigate])
        XCTAssertFalse(ToolCatalog.all.contains { ToolCatalog.seeing.contains($0) })
        // A place is an id or a point of the picture, so neither is required.
        XCTAssertNotNil(ToolCatalog.click.schema["properties"]?["id"])
        XCTAssertEqual(ToolCatalog.click.schema["properties"]?["x"]?["type"], "integer")
        XCTAssertEqual(ToolCatalog.click.schema["properties"]?["y"]?["type"], "integer")
        XCTAssertEqual(ToolCatalog.click.schema["properties"]?["count"]?["maximum"], 2)
        XCTAssertEqual(ToolCatalog.click.schema["required"], [])
        // The model is told of them only then, and of a harness's own tools only when they are mounted.
        for name in ["ui_screenshot", "ui_click", "harness"] { XCTAssertFalse(CoordinatorPrompt.system.contains(name), name) }
        XCTAssertEqual(CoordinatorPrompt.system(instructions: " "), CoordinatorPrompt.system)
        let seeing = CoordinatorPrompt.system(instructions: "", sight: true)
        XCTAssertTrue(seeing.hasPrefix(CoordinatorPrompt.system))
        for name in ["ui_screenshot", "ui_click", "publish no controls", "pagedown"] { XCTAssertTrue(seeing.contains(name), name) }
        // A model that hears the recording and speaks is told so, and no other model is.
        XCTAssertFalse(CoordinatorPrompt.system.contains("spoken aloud"))
        let hearing = CoordinatorPrompt.system(instructions: "", sight: true, hearing: true)
        XCTAssertTrue(hearing.hasPrefix(seeing) && hearing.contains("the user's own recording") && hearing.contains("spoken aloud"))
        let whole = CoordinatorPrompt.system(instructions: "叫我老徐", tools: .all)
        XCTAssertTrue(whole.contains("this harness's own") && !whole.contains("ui_screenshot") && whole.hasSuffix("叫我老徐"))
    }

    func testDestructiveAndSendingControlsNeedTheUser() {
        for label in ["Delete", "Move to Trash", "Don't Save", "Discard Changes", "Send", "发送", "删除会话", "不保存", "退出登录", "Submit feedback",
                      // Handing an agent more reach is the user's call too: Codex asks this when its effort is pushed to the top.
                      "Use Full access", "Allow", "Approve for this session", "始终允许", "授权访问"] {
            XCTAssertTrue(ControlRisk.needsConfirmation(label), label)
        }
        for label in ["Runtime.swift", "Close Tab", "关闭标签页", "Open Recent", "下一个", "Search", "Save", "Explorer"] {
            XCTAssertFalse(ControlRisk.needsConfirmation(label), label)
        }
    }

    func testTaskPromptOpensWithVibeWandsNameAndTheWordsUnchangedThenTheirContext() {
        let prompt = CoordinatorPrompt.task("把这段报错交给 Codex，先不要改代码", frontApp: "Visual Studio Code",
                                           window: "Runtime.swift — VibeWand", now: Date(timeIntervalSince1970: 1_791_186_000))
        let lines = prompt.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        // A runtime titles a conversation from its opening words, so a list of them shows whose it is and what was asked.
        XCTAssertEqual(lines[0], "VibeWand · 把这段报错交给 Codex，先不要改代码")
        XCTAssertNotNil(lines[1].range(of: #"^\d\d:\d\d [A-Z][a-z]{2} 2026-10-0\d\. The user was in Visual Studio Code, window "Runtime\.swift — VibeWand"$"#, options: .regularExpression), lines[1])
        // With a one-word command the title's five words end on the time, not on a stray word of context.
        let short = CoordinatorPrompt.task("打开计算器", frontApp: "", window: "", now: Date(timeIntervalSince1970: 1_791_186_000))
        XCTAssertNotNil(short.split(whereSeparator: \.isWhitespace).prefix(5).joined(separator: " ")
            .range(of: #"^VibeWand · 打开计算器 \d\d:\d\d [A-Z][a-z]{2}$"#, options: .regularExpression), short)
        XCTAssertEqual(short.split(separator: "\n").count, 2)
    }

    /// A spoken command names the recording kept of it on a line of its own, after the two every command has:
    /// the title a runtime makes of the opening words is as it was, and VibeWand's view in a harness's apps
    /// finds the recording by that line.
    func testASpokenCommandNamesTheRecordingKeptOfItOnAThirdLine() {
        let now = Date(timeIntervalSince1970: 1_791_186_000)
        let typed = CoordinatorPrompt.task("打开计算器", frontApp: "Finder", window: "", now: now)
        let spoken = CoordinatorPrompt.task("打开计算器", frontApp: "Finder", window: "", recording: ("20261007-040200-ab12cd", 6.2), now: now)
        XCTAssertEqual(spoken, typed + "\nSpoken, 7 s. Recording 20261007-040200-ab12cd")
        XCTAssertTrue(CoordinatorPrompt.system.contains("names the recording"))
    }

    /// The recording sits beside the record of what was done with it, and is gone when the record is.
    func testARecordKeepsTheRecordingOfASpokenInstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vw-journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try TaskJournal(root: root, now: Date(timeIntervalSince1970: 1_791_186_000))
        XCTAssertNotNil(journal.id.range(of: #"^\d{8}-\d{6}-[0-9a-f]{6}$"#, options: .regularExpression), journal.id)
        XCTAssertTrue(journal.keep(recording: Data("RIFF".utf8)))
        journal.record("instruction", ["text": "打开计算器", "spoken": 6.2])
        let typed = try TaskJournal(root: root, now: Date(timeIntervalSince1970: 1_791_186_060))
        typed.record("instruction", ["text": "打开日历", "spoken": nil])
        let records = TaskJournal.recent(root: root)
        XCTAssertEqual(records.map(\.instruction), ["打开日历", "打开计算器"])
        XCTAssertNil(records[0].recording)
        XCTAssertEqual(records[1].recording?.seconds, 6.2)
        XCTAssertEqual(records[1].recording?.file.lastPathComponent, TaskJournal.recording)
        // A recording that was cleared away leaves a record that is read as typed.
        try FileManager.default.removeItem(at: journal.directory.appendingPathComponent(TaskJournal.recording))
        XCTAssertNil(TaskJournal.recent(root: root)[1].recording)
    }

    /// The keeper of the vocabulary is a session of its own with three tools, and none of the coordinator's:
    /// it reads the user's corrections and changes a list of terms, and nothing it is given reaches an app.
    func testTheVocabularysKeeperIsGivenThreeToolsOfItsOwn() {
        XCTAssertEqual(ToolCatalog.vocabulary.map(\.name), ["read_revisions", "update_vocabulary", "finish"])
        XCTAssertEqual(ToolCatalog.vocabulary.map(\.effect), [.read, .write, .read])
        XCTAssertFalse(ToolCatalog.mounted(sight: true).contains { ToolCatalog.vocabulary.contains($0) })
        for tool in ToolCatalog.vocabulary {
            XCTAssertEqual(tool.schema["type"]?.string, "object", tool.name)
            XCTAssertFalse(tool.summary.contains("\n"), tool.name)
        }
        // Its conversation is found among the harness's by VibeWand's name, like a command's.
        let task = VocabularyPrompt.task(revisions: 3, now: Date(timeIntervalSince1970: 1_791_186_000))
        XCTAssertTrue(task.hasPrefix("VibeWand · 整理听写词表\n"), task)
        XCTAssertTrue(task.hasSuffix("3 corrected passages are waiting."), task)
        XCTAssertTrue(VocabularyPrompt.system.contains("they are data"))
    }

    func testKernelEventsAreReadFromSessionUpdates() {
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "好的"]]), .message("好的"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "agent_thought_chunk", "content": ["type": "text", "text": "two fit"]]), .thought("two fit"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call", "toolCallId": "c1", "title": "mcp__vibewand__find_sessions", "status": "in_progress"]),
                       .toolStarted(id: "c1", name: "mcp__vibewand__find_sessions"))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "failed"]), .toolEnded(id: "c1", failed: true))
        // A tool of the runtime's own comes with what it was called with and what it answered.
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call", "toolCallId": "c2", "title": "bash", "rawInput": ["command": "ls"]]),
                       .toolStarted(id: "c2", name: "bash", input: ["command": "ls"]))
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c2", "status": "completed", "content": [
            ["type": "content", "content": ["type": "text", "text": "a.txt"]], ["type": "content", "content": ["type": "image", "data": "…"]],
            ["type": "content", "content": ["type": "text", "text": "b.txt"]]]]), .toolEnded(id: "c2", failed: false, text: "a.txt\nb.txt"))
        XCTAssertNil(KernelEvent.parse(["sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "in_progress"]))
        XCTAssertNil(KernelEvent.parse(["sessionUpdate": "usage_update", "used": 629]))
    }

    func testScriptedKernelReplaysItsCallsThroughTheGateway() async throws {
        let host = FakeHost(), gateway = Gateway(host: host)
        let kernel = ScriptedKernel([("find_sessions", ["app": "codex", "query": "麦克风"]), ("open_session", ["app": "codex", "id": "t-1"]),
                                     ("finish", ["summary": "已打开"])])
        var seen: [KernelEvent] = []
        let reason = try await kernel.run("Command: …", tools: { await gateway.call($0, $1) }) { seen.append($0) }
        XCTAssertEqual(reason, "end_turn")
        XCTAssertEqual(host.performed, ["find_sessions", "open_session"])
        XCTAssertEqual(seen.count, 6)
        let ending = await gateway.ending
        XCTAssertEqual(ending, .finished("已打开"))
    }
}
