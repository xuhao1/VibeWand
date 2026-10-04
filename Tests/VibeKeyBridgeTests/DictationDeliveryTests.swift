import XCTest
@testable import VibeKeyBridge

final class DictationDeliveryTests: XCTestCase {
    let target = TargetIdentity(pid: 42, windowHash: 1, windowTitle: "Chat", focusedHash: 2, focusedIdentifier: "composer")
    func observation() -> TargetObservation {
        var value = TargetObservation()
        value.identity = target
        value.context = InteractionContext(targetAvailable: true, editorFocused: true, modalOpen: false,
            compositionActive: false, picker: nil, hasDraftText: false)
        return value
    }
    func testEmptyOriginalEditorAcceptsDictation() {
        XCTAssertTrue(DictationDelivery.accepts(target: target, observation: observation(), frontmostPID: 42))
    }
    func testLateTranscriptRejectedAfterAppWindowOrEditorChanges() {
        var value = observation()
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 43))
        value.identity?.focusedHash = 3
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 42))
        value = observation(); value.identity?.windowHash = 9
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 42))
        value = observation(); value.identity?.windowTitle = "Another chat"
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 42))
    }
    func testDialogPickerAndIMECompositionBlockTranscriptInsertion() {
        var value = observation(); value.context.modalOpen = true
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 42))
        value = observation(); value.context.compositionActive = true
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 42))
        value = observation(); value.context.picker = .sessions
        XCTAssertFalse(DictationDelivery.accepts(target: target, observation: value, frontmostPID: 42))
    }
}
