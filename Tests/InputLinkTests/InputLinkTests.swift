import XCTest
@testable import InputLink

final class InputLinkTests: XCTestCase {
    private final class Field: InputTextClient {
        let application: String
        /// What a real text field would hold: committed text, then the marked text.
        var written = "", marked = ""
        var takesMarkedText = true
        init(_ application: String) { self.application = application }
        func mark(_ text: String) { if takesMarkedText { marked = text } }
        func insert(_ text: String) { written += text; marked = "" }
        var marking: Bool { !marked.isEmpty }
        /// What a click in the field does in most apps: the marked text becomes ordinary text.
        func click() { written += marked; marked = "" }
    }
    private func composer() -> (InputComposer, () -> [InputMessage]) {
        let composer = InputComposer()
        var sent: [InputMessage] = []
        composer.send = { sent.append($0) }
        return (composer, { defer { sent = [] }; return sent })
    }

    func testTextIsShownWhileItChangesAndTheFinishedTextReplacesIt() {
        let (composer, sent) = composer()
        let field = Field("com.example.chat")
        composer.activate(field)
        XCTAssertEqual(sent(), [.client("com.example.chat")])
        composer.receive(.begin("com.example.chat"))
        composer.receive(.show("今天"))
        composer.receive(.show("今天天气"))
        XCTAssertEqual(field.marked, "今天天气")
        XCTAssertEqual(field.written, "")
        composer.receive(.commit("今天天气不错。"))
        XCTAssertEqual(field.written, "今天天气不错。")
        XCTAssertEqual(field.marked, "")
        XCTAssertEqual(sent(), [.committed(true)])
    }
    func testAShortDictationIsWrittenWithoutEverBeingShown() {
        let (composer, sent) = composer()
        let field = Field("com.example.chat")
        composer.activate(field); _ = sent()
        composer.receive(.begin("com.example.chat"))
        composer.receive(.commit("好"))
        XCTAssertEqual(field.written, "好")
        XCTAssertEqual(sent(), [.committed(true)])
    }
    func testCancellingLeavesNothingBehind() {
        let (composer, sent) = composer()
        let field = Field("com.example.chat")
        composer.activate(field)
        composer.receive(.begin("com.example.chat"))
        composer.receive(.show("说错了"))
        composer.receive(.cancel)
        XCTAssertEqual(field.marked, "")
        XCTAssertEqual(field.written, "")
        XCTAssertEqual(sent().last, .committed(false), "VibeWand may now write there another way")
        // Late text of the cancelled dictation is not written either.
        composer.receive(.show("迟到"))
        XCTAssertEqual(field.marked, "")
    }
    func testADictationNeverFollowsTheFocusToAnotherField() {
        let (composer, sent) = composer()
        let chat = Field("com.example.chat"), terminal = Field("com.example.terminal")
        composer.activate(chat)
        composer.receive(.begin("com.example.chat"))
        composer.receive(.show("删除所有"))
        composer.deactivate(chat)
        composer.activate(terminal)
        // What was shown stays where it was written; the rest of the dictation goes nowhere.
        XCTAssertEqual(chat.written, "删除所有")
        XCTAssertEqual(sent(), [.client("com.example.chat"), .interrupted, .client(nil), .client("com.example.terminal")])
        composer.receive(.show("删除所有文件"))
        composer.receive(.commit("删除所有文件"))
        XCTAssertEqual(terminal.marked + terminal.written, "")
        XCTAssertEqual(sent(), [.committed(false)])
    }
    func testADictationForAnotherAppThanTheActiveOneIsNotWritten() {
        let (composer, sent) = composer()
        let terminal = Field("com.example.terminal")
        composer.activate(terminal); _ = sent()
        composer.receive(.begin("com.example.chat"))
        composer.receive(.show("你好"))
        composer.receive(.commit("你好"))
        XCTAssertEqual(terminal.marked + terminal.written, "")
        XCTAssertEqual(sent(), [.committed(false)])
    }
    func testTheFieldEndingCompositionKeepsWhatWasShownOnce() {
        let (composer, sent) = composer()
        let field = Field("com.example.chat")
        composer.activate(field); _ = sent()
        composer.receive(.begin("com.example.chat"))
        composer.interrupt(field)
        XCTAssertEqual(sent(), [], "Nothing was shown yet, so nothing was kept")
        composer.receive(.begin("com.example.chat"))
        composer.receive(.show("第一句"))
        composer.interrupt(field)
        composer.interrupt(field)
        XCTAssertEqual(field.written, "第一句")
        XCTAssertEqual(sent(), [.interrupted])
    }

    func testAFieldThatKeptTheTextByItselfIsNotWrittenToAgain() {
        let (composer, sent) = composer()
        let field = Field("com.example.chat")
        composer.activate(field); _ = sent()
        composer.receive(.begin("com.example.chat"))
        composer.receive(.show("帮我看一下"))
        field.click()
        composer.receive(.show("帮我看一下这个"))
        composer.receive(.commit("帮我看一下这个函数。"))
        XCTAssertEqual(field.written, "帮我看一下")
        XCTAssertEqual(field.marked, "")
        XCTAssertEqual(sent(), [.interrupted, .committed(false)])
    }

    func testTheInputMethodCannotPressReturnOrTab() {
        let (composer, _) = composer()
        let terminal = Field("com.example.terminal")
        composer.activate(terminal)
        composer.receive(.begin("com.example.terminal"))
        composer.receive(.show("rm -rf build\n"))
        XCTAssertEqual(terminal.marked, "rm -rf build ")
        composer.receive(.commit("rm -rf build\r\nls\t-la\u{2028}"))
        XCTAssertEqual(terminal.written, "rm -rf build  ls -la ")
    }

    func testAFieldThatTakesNoProvisionalTextIsLeftToVibeWand() {
        let (composer, sent) = composer()
        let field = Field("com.example.game")
        field.takesMarkedText = false
        composer.activate(field); _ = sent()
        composer.receive(.begin("com.example.game"))
        composer.receive(.show("你"))
        XCTAssertEqual(sent(), [.refused])
        composer.receive(.show("你好"))
        composer.receive(.commit("你好。"))
        XCTAssertEqual(sent(), [.committed(false)])
        // Nor is a dictation too short to have been shown reported as written when the field took nothing.
        composer.receive(.begin("com.example.game"))
        composer.receive(.commit("好"))
        XCTAssertEqual(sent(), [.committed(false)])
        XCTAssertEqual(field.written, "")
    }

    func testMessagesCrossTheSocketAndALostConnectionTakesBackWhatWasShown() throws {
        let path = NSTemporaryDirectory() + "vw-input-\(UInt32.random(in: 0...UInt32.max)).sock"
        let composer = InputComposer()
        let field = Field("com.example.chat")
        composer.activate(field)
        var refused = true
        let listener = try InputListener(path: path, admits: { _ in !refused }, onLine: composer.connect)
        defer { _ = listener }

        let stranger = InputLine(descriptor: try XCTUnwrap(InputLink.connect(to: path)))
        let dropped = expectation(description: "a process that is not admitted is dropped")
        stranger.onClose = { dropped.fulfill() }
        wait(for: [dropped], timeout: 2)

        refused = false
        let app = InputLine(descriptor: try XCTUnwrap(InputLink.connect(to: path)))
        var received: [InputMessage] = []
        var arrival = expectation(description: "the active app is announced on connecting")
        app.onMessage = { received.append($0); arrival.fulfill() }
        wait(for: [arrival], timeout: 2)
        XCTAssertEqual(received, [.client("com.example.chat")])

        arrival = expectation(description: "the commit is answered")
        app.send(.begin("com.example.chat")); app.send(.show("边说")); app.send(.commit("边说边写。"))
        wait(for: [arrival], timeout: 2)
        XCTAssertEqual(received.last, .committed(true))
        XCTAssertEqual(field.written, "边说边写。")

        app.send(.begin("com.example.chat")); app.send(.show("没说完"))
        let shown = expectation(description: "the provisional text arrives")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { shown.fulfill() }
        wait(for: [shown], timeout: 2)
        XCTAssertEqual(field.marked, "没说完")
        app.close()
        let cleared = expectation(description: "the connection closing is noticed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { cleared.fulfill() }
        wait(for: [cleared], timeout: 2)
        XCTAssertEqual(field.marked, "")
        XCTAssertEqual(field.written, "边说边写。")
    }
}
