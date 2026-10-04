import XCTest
@testable import VibeKeyBridge

final class RuntimeTests: XCTestCase {
    func testUnknownIMEStillAllowsCursorMovementAndDeletionInComposer() {
        var state = InteractionState()
        let context = InteractionContext(targetAvailable: true, editorFocused: true,
            modalOpen: false, compositionActive: false, picker: nil)
        XCTAssertTrue(context.canEditDraft)
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .moveCursor(-1))
        XCTAssertEqual(reduce(state: &state, control: .right, context: context), .moveCursor(1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .deleteBackward)
        XCTAssertEqual(reduce(state: &state, control: .forceEscape, context: context), .sendEscape)
    }
    func testUnknownIMEStillPreservesCancelForVisibleCandidatesAndModals() {
        for (modal, composing, picker) in [(true, false, nil), (false, true, nil),
                                         (true, false, InteractionMode.sessions)] {
            var state = InteractionState()
            let context = InteractionContext(targetAvailable: true, editorFocused: true,
                modalOpen: modal, compositionActive: composing, picker: picker)
            XCTAssertFalse(context.canEditDraft)
            XCTAssertEqual(reduce(state: &state, control: .escape, context: context), picker == nil ? .sendEscape : .cancelPicker)
        }
    }
    func testCancelNeverTurnsHeldDialIntoClick() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.dial, phase: .down)
            runtime.handle(.dial, phase: .cancel)
            runtime.handle(.dial, phase: .up)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("编辑文字", "Editing text"))
            XCTAssertFalse(runtime.snapshot.pressed.contains(.dial))
            runtime.stop()
        }
    }
    func testPressRotateReleaseDoesNotOpenSessionPicker() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.dial, phase: .down)
            runtime.handle(.left, phase: .pulse)
            runtime.handle(.dial, phase: .up)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("编辑文字", "Editing text"))
            XCTAssertEqual(runtime.snapshot.rotation, -1)
            runtime.stop()
        }
    }
    func testHeldEscapeKeepsDeletingUntilRelease() async throws {
        try await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            let deletions: @MainActor () throws -> Int = { (try runtime.diagnostics()["recentActions"] as? [String])?.count ?? 0 }
            let start = ProcessInfo.processInfo.systemUptime
            runtime.handle(.escape, phase: .down)
            for step in 0..<4 { runtime.advanceGestures(now: start + 0.6 + Double(step) * 0.1) }
            let held = try deletions()
            XCTAssertGreaterThanOrEqual(held, 4)
            runtime.handle(.escape, phase: .up)
            for step in 4..<8 { runtime.advanceGestures(now: start + 0.6 + Double(step) * 0.1) }
            XCTAssertEqual(try deletions(), held)
            runtime.stop()
        }
    }
    func testHardwareDownUpSelectsSessionOnSecondPress() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 0.3)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("选择会话", "Choose a chat"))
            runtime.handle(.right, phase: .pulse)
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 0.3)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("阅读会话", "Reading"))
            XCTAssertEqual(runtime.snapshot.target, L10n.tr("修复登录问题", "Fix sign-in issue"))
            runtime.stop()
        }
    }
}
