import XCTest
import AppKit
import SpeechInput
@testable import VibeWandBridge

final class LiveDictationDraftTests: XCTestCase {
    func testAppendOnlyTypesNewCharactersAndRevisionReplacesOnlyChangedTail() throws {
        let field = MemoryDraftField(value: "已有：", selection: NSRange(location: 3, length: 0))
        let draft = try XCTUnwrap(LiveDictationDraft(field: field))
        XCTAssertEqual(draft.update("测"), .applied)
        XCTAssertEqual(draft.update("测试"), .applied)
        XCTAssertEqual(field.replacements.last?.0, NSRange(location: 4, length: 0))
        XCTAssertEqual(field.replacements.last?.1, "试")
        XCTAssertEqual(draft.update("测验"), .applied)
        XCTAssertEqual(field.replacements.last?.0, NSRange(location: 4, length: 1))
        XCTAssertEqual(field.replacements.last?.1, "验")
        XCTAssertEqual(field.state.value, "已有：测验")
    }
    func testBrowserValueAndCaretCanSettleSeparatelyWithoutDuplicateWrites() throws {
        let field = DelayedDraftField(value: "已有：", selection: NSRange(location: 3, length: 0))
        var time = 0.0
        let draft = try XCTUnwrap(LiveDictationDraft(field: field, now: { time }))
        XCTAssertEqual(draft.update("测试"), .pending)
        time = 0.4
        XCTAssertEqual(draft.update("测试语音"), .pending)
        XCTAssertEqual(field.writes, 1)
        field.state.value = "已有：测"; field.state.selection = NSRange(location: 4, length: 0)
        XCTAssertEqual(draft.update("测试语音"), .pending)
        field.state.value = "已有：测试" // The AX caret still lags the text.
        XCTAssertEqual(draft.update("测试语音"), .pending)
        time = 0.8; field.state.selection = NSRange(location: 5, length: 0)
        XCTAssertEqual(draft.update("测试语音"), .pending)
        XCTAssertEqual(field.writes, 2)
        field.applyPending()
        XCTAssertEqual(draft.update("测试语音"), .applied)
        XCTAssertEqual(field.state.value, "已有：测试语音")
    }
    func testFailedWriteIsNotMistakenForAUserEditOrRetriedForever() throws {
        let field = DelayedDraftField(value: "", selection: NSRange(location: 0, length: 0))
        var time = 0.0
        let draft = try XCTUnwrap(LiveDictationDraft(field: field, now: { time }))
        XCTAssertEqual(draft.update("测"), .pending)
        time = 0.5; XCTAssertEqual(draft.update("测试"), .pending)
        time = 1.6; XCTAssertEqual(draft.update("测试"), .conflict)
        XCTAssertEqual(draft.failureReason, "write-unconfirmed")
        XCTAssertEqual(field.state.value, "")
    }
    func testManualEditOutsidePendingWriteStillStopsImmediately() throws {
        let field = DelayedDraftField(value: "保留：", selection: NSRange(location: 3, length: 0))
        let draft = try XCTUnwrap(LiveDictationDraft(field: field))
        XCTAssertEqual(draft.update("测试"), .pending)
        field.state.value = "用户修改："
        XCTAssertEqual(draft.update("测试语音"), .conflict)
        XCTAssertFalse(draft.rollback())
        XCTAssertEqual(field.state.value, "用户修改：")
    }
    func testUnicodeFallbackCannotTurnParagraphsIntoSubmitKeys() {
        XCTAssertEqual(UnicodeTextDelivery.safeCharacters("第一行\r\n第二行\n第三行\t代码"), "第一行 第二行 第三行 代码")
    }
    func testASRRevisionAndPolishingReplaceOnlyTheOwnedSelection() throws {
        let original = "已有草稿：要替换；保留结尾😊"
        let field = MemoryDraftField(value: original, selection: (original as NSString).range(of: "要替换"))
        let draft = try XCTUnwrap(LiveDictationDraft(field: field))
        XCTAssertEqual(draft.update("周一"), .applied)
        XCTAssertEqual(field.state.value, "已有草稿：周一；保留结尾😊")
        XCTAssertEqual(draft.update("周二开会"), .applied)
        XCTAssertEqual(field.state.value, "已有草稿：周二开会；保留结尾😊")
        XCTAssertEqual(draft.update("请安排周二的会议。"), .applied)
        XCTAssertEqual(field.state.value, "已有草稿：请安排周二的会议。；保留结尾😊")
        XCTAssertTrue(draft.rollback())
        XCTAssertEqual(field.state.value, original)
    }
    func testManualEditsStopASRAndCannotBeRolledBack() throws {
        let field = MemoryDraftField(value: "保留：", selection: NSRange(location: 3, length: 0))
        let draft = try XCTUnwrap(LiveDictationDraft(field: field))
        XCTAssertEqual(draft.update("今天"), .applied)
        field.state.value += "用户手动追加"
        XCTAssertEqual(draft.update("今天天气不错"), .conflict)
        XCTAssertFalse(draft.rollback())
        XCTAssertEqual(field.state.value, "保留：今天用户手动追加")
    }
    func testCaretMovementPreservesUserChoice() throws {
        let field = MemoryDraftField(value: "", selection: NSRange(location: 0, length: 0))
        let draft = try XCTUnwrap(LiveDictationDraft(field: field))
        XCTAssertEqual(draft.update("Hello 😊"), .applied)
        field.state.selection = NSRange(location: 0, length: 0)
        XCTAssertEqual(draft.update("Hello world 😊"), .conflict)
        XCTAssertEqual(field.state.value, "Hello 😊")
    }
    func testEmptyRevisionAndEmojiKeepUTF16RangesValid() throws {
        let field = MemoryDraftField(value: "A😊Z", selection: NSRange(location: 1, length: 2))
        let draft = try XCTUnwrap(LiveDictationDraft(field: field))
        XCTAssertEqual(draft.update("语音😊"), .applied)
        XCTAssertEqual(field.state.value, "A语音😊Z")
        XCTAssertEqual(draft.update(""), .applied)
        XCTAssertEqual(field.state.value, "AZ")
        XCTAssertTrue(draft.rollback()); XCTAssertEqual(field.state.value, "A😊Z")
    }
    func testSmallOverlayIsIndependentOfHardwareAndHiding() async {
        await MainActor.run {
            let previous = UserDefaults.standard.string(forKey: "hudDisplayMode")
            defer { if let previous { UserDefaults.standard.set(previous, forKey: "hudDisplayMode") } else { UserDefaults.standard.removeObject(forKey: "hudDisplayMode") } }
            let overlay = OverlayController(onControl: { _, _ in })
            overlay.setVisible(false); overlay.setDisplayMode(.compact)
            XCTAssertFalse(overlay.isVisible)
            let idle = VoiceHUDSnapshot()
            let size = SpeechOverlayLayout.size(template: .dualSense, expanded: true, mode: .compact, voice: idle)
            XCTAssertEqual(size.height, 48)
            let recording = VoiceHUDSnapshot(enabled: true, state: .recording, text: "正在说话")
            XCTAssertEqual(SpeechOverlayLayout.size(template: .vibeKey, expanded: false, mode: .compact, voice: recording).height, 118)
            overlay.setDisplayMode(.full); XCTAssertFalse(overlay.isVisible)
        }
    }
    func testSpeechOverlayVariantsRenderWithoutTakingFocus() async throws {
        try await MainActor.run {
            let previousMode = UserDefaults.standard.string(forKey: "hudDisplayMode")
            defer { if let previousMode { UserDefaults.standard.set(previousMode, forKey: "hudDisplayMode") } else { UserDefaults.standard.removeObject(forKey: "hudDisplayMode") } }
            let overlay = OverlayController(onControl: { _, _ in XCTFail("Rendering must not send input") })
            for mode in OverlayDisplayMode.allCases {
                for style in DictationTextStyle.allCases {
                    var snapshot = HUDSnapshot(); snapshot.deviceTemplate = .dualSense
                    snapshot.connected = true
                    snapshot.voice = VoiceHUDSnapshot(enabled: true, state: .recording, style: style,
                        text: "这是语音输入测试，请帮我检查代码，并保留我的草稿。", status: L10n.tr("正在听写 · 松开结束", "Listening · release to finish"))
                    overlay.update(snapshot); overlay.setDisplayMode(mode)
                    let image = try XCTUnwrap(overlay.previewImage(appearance: NSAppearance(named: .aqua)))
                    XCTAssertEqual(image.size, SpeechOverlayLayout.size(template: .dualSense, expanded: false, mode: mode, voice: snapshot.voice))
                    XCTAssertFalse(overlay.isVisible)
                    if let path = ProcessInfo.processInfo.environment["VIBEWAND_VOICE_OVERLAY_REVIEW"] {
                        let url = URL(fileURLWithPath: path).appendingPathComponent("\(mode.rawValue)-\(style.rawValue).png")
                        XCTAssertTrue(overlay.renderPNG(to: url))
                    }
                }
            }
        }
    }
}

private final class MemoryDraftField: DictationEditableField {
    var state: DictationFieldState
    var replacements: [(NSRange, String)] = []
    init(value: String, selection: NSRange) { state = DictationFieldState(value: value, selection: selection) }
    func read() -> DictationFieldState? { state }
    func replace(_ range: NSRange, with text: String, expectedValue: String) -> Bool {
        replacements.append((range, text))
        state.value = (state.value as NSString).replacingCharacters(in: range, with: text)
        state.selection = NSRange(location: range.location + text.utf16.count, length: 0)
        return state.value == expectedValue
    }
}

private final class DelayedDraftField: DictationEditableField {
    var state: DictationFieldState
    var writes = 0
    private var pending: DictationFieldState?
    init(value: String, selection: NSRange) { state = DictationFieldState(value: value, selection: selection) }
    func read() -> DictationFieldState? { state }
    func replace(_ range: NSRange, with text: String, expectedValue: String) -> Bool {
        writes += 1
        pending = DictationFieldState(value: expectedValue, selection: NSRange(location: range.location + text.utf16.count, length: 0))
        return true
    }
    func applyPending() { if let pending { state = pending; self.pending = nil } }
}
