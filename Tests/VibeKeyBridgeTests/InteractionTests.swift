import XCTest
@testable import VibeKeyBridge

final class InteractionTests: XCTestCase {
    private func context(
        available: Bool = true,
        editing: Bool = false,
        modal: Bool = false,
        composing: Bool = false,
        picker: InteractionMode? = nil
    ) -> InteractionContext {
        InteractionContext(
            targetAvailable: available,
            editorFocused: editing,
            modalOpen: modal,
            compositionActive: composing,
            picker: picker
        )
    }

    func testNoControlReachesAnotherApplication() {
        for control in DeviceControl.allCases {
            var state = InteractionState(mode: .sessions, ownerPID: 42, pickerConfirmed: true)
            let effect = reduce(
                state: &state,
                control: control,
                context: context(available: false, editing: true, modal: true, composing: true, picker: .sessions)
            )
            XCTAssertEqual(effect, .none, "Unexpected effect for \(control)")
            XCTAssertEqual(state.mode, .unavailable)
            XCTAssertNil(state.ownerPID)
            XCTAssertFalse(state.pickerConfirmed)
        }
    }

    func testSecondDialClickConfirmsOnlyAnObservedPicker() {
        var state = InteractionState()
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context()), .openSessions)
        XCTAssertEqual(state.mode, .browse, "Sending a shortcut must not pretend its UI opened")
        XCTAssertEqual(reduce(state: &state, control: .right, context: context(picker: .sessions)), .moveCandidate(1))
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context(picker: .sessions)), .confirmCandidate)
        XCTAssertTrue(state.pickerConfirmed)

        XCTAssertEqual(reduce(state: &state, control: .right, context: context(editing: true)), .moveCursor(1))
        XCTAssertEqual(state.mode, .editing)
        XCTAssertFalse(state.pickerConfirmed)
    }

    func testMissingPickerRecoversFromStaleStateInsteadOfSendingReturn() {
        var state = InteractionState(mode: .sessions, ownerPID: 42, pickerConfirmed: true)
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context(editing: true)), .openSessions)
        XCTAssertEqual(state.mode, .editing)
        XCTAssertFalse(state.pickerConfirmed)
    }

    func testFocusSwitchImmediatelyChangesRotationAndEscape() {
        var state = InteractionState(mode: .editing)
        XCTAssertEqual(reduce(state: &state, control: .left, context: context()), .scroll(1))
        XCTAssertEqual(state.mode, .browse)
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context()), .sendEscape)

        XCTAssertEqual(reduce(state: &state, control: .left, context: context(editing: true)), .moveCursor(-1))
        XCTAssertEqual(reduce(state: &state, control: .right, context: context(editing: true)), .moveCursor(1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context(editing: true)), .deleteBackward)
        XCTAssertEqual(state.mode, .editing)
    }

    func testEmptyComposerScrollsEvenWhileInputRetainsFocus() {
        var state = InteractionState(mode: .editing)
        var observed = context(editing: true)
        observed.hasDraftText = false
        XCTAssertEqual(reduce(state: &state, control: .left, context: observed), .scroll(1))
        XCTAssertEqual(reduce(state: &state, control: .right, context: observed), .scroll(-1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: observed), .sendEscape)
        XCTAssertEqual(state.mode, .browse)
        XCTAssertFalse(observed.canEditDraft)
        observed.hasDraftText = true
        XCTAssertEqual(reduce(state: &state, control: .left, context: observed), .moveCursor(-1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: observed), .deleteBackward)
        XCTAssertEqual(state.mode, .editing)
    }
    func testEmptyComposerDoesNotOverrideOpenPickerNavigation() {
        var state = InteractionState()
        var observed = context(editing: true, modal: true, picker: .models)
        observed.hasDraftText = false
        XCTAssertEqual(reduce(state: &state, control: .right, context: observed), .moveCandidate(1))
        XCTAssertEqual(state.mode, .models)
    }

    func testIMEAndUnknownModalsPreventDestructiveEditingRemaps() {
        let blockedContexts = [
            context(editing: true, modal: true),
            context(editing: true, composing: true),
            context(editing: true, composing: true, picker: .sessions)
        ]
        for observed in blockedContexts {
            var state = InteractionState(mode: .editing)
            XCTAssertEqual(reduce(state: &state, control: .escape, context: observed), .sendEscape)
            XCTAssertEqual(reduce(state: &state, control: .left, context: observed), .none)
            XCTAssertEqual(reduce(state: &state, control: .right, context: observed), .none)
            XCTAssertEqual(reduce(state: &state, control: .settings, context: observed), .none)
            XCTAssertEqual(reduce(state: &state, control: .dial, context: observed), .sendReturn)
            XCTAssertFalse(state.pickerConfirmed, "IME confirmation must not confirm the enclosing picker")
        }
    }

    func testObservedPickersOverrideUnderlyingEditorAndModal() {
        for picker in [InteractionMode.sessions, .models, .efforts] {
            var state = InteractionState(mode: .editing)
            let observed = context(editing: true, modal: true, picker: picker)
            XCTAssertEqual(reduce(state: &state, control: .left, context: observed), .moveCandidate(-1))
            XCTAssertEqual(reduce(state: &state, control: .ok, context: observed), .confirmCandidate)
            XCTAssertTrue(state.pickerConfirmed)
            XCTAssertEqual(reduce(state: &state, control: .escape, context: observed), .cancelPicker)
            XCTAssertFalse(state.pickerConfirmed)
            XCTAssertEqual(state.mode, picker, "Cancellation does not prove the modal closed")
        }
    }

    func testModelAndEffortStagesFollowObservedUI() {
        var state = InteractionState(mode: .editing)
        XCTAssertEqual(reduce(state: &state, control: .settings, context: context(editing: true)), .openModels)
        XCTAssertEqual(state.mode, .editing)
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context(picker: .models)), .confirmCandidate)
        XCTAssertTrue(state.pickerConfirmed)
        XCTAssertEqual(reduce(state: &state, control: .right, context: context(picker: .efforts)), .moveCandidate(1))
        XCTAssertEqual(state.mode, .efforts)
        XCTAssertFalse(state.pickerConfirmed)
    }

    func testNativeReturnAndEscapeRemainAvailable() {
        for observed in [context(), context(editing: true), context(modal: true), context(composing: true)] {
            var state = InteractionState()
            XCTAssertEqual(reduce(state: &state, control: .ok, context: observed), .sendReturn)
            XCTAssertEqual(reduce(state: &state, control: .forceEscape, context: observed), .sendEscape)
        }
    }

    func testVoiceDoesNotInjectKeysOrOpenPickers() {
        for observed in [context(), context(editing: true), context(picker: .sessions), context(composing: true)] {
            var state = InteractionState()
            XCTAssertEqual(reduce(state: &state, control: .voice, context: observed), .none)
        }
    }

    func testUnassignedAdditionalButtonsHaveNoLegacyApplicationEffect() {
        let controls: [DeviceControl] = [.l1, .l2, .leftStickPress, .rightStickPress,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .options, .create, .home, .touchpad, .mute,
            .power, .volumeUp, .volumeDown]
        for observed in [context(), context(editing: true), context(picker: .sessions), context(composing: true)] {
            for control in controls {
                var state = InteractionState()
                XCTAssertEqual(reduce(state: &state, control: control, context: observed), .none)
                XCTAssertEqual(GestureAction.legacy(control), .none)
            }
        }
    }

    func testInvalidPickerKindsDoNotInventAConfirmationTarget() {
        var state = InteractionState(mode: .sessions)
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context(editing: true, picker: .editing)), .openSessions)
        XCTAssertEqual(state.mode, .editing)
    }
}
