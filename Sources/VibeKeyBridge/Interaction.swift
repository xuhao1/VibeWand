/// Converts hardware actions into application operations using the currently
/// observed UI. A shortcut being sent is never evidence that a picker opened.
func reduce(
    state: inout InteractionState,
    control: DeviceControl,
    context: InteractionContext
) -> BridgeEffect {
    guard context.targetAvailable else {
        state.mode = .unavailable
        return .none
    }

    let picker: InteractionMode?
    switch context.picker {
    case .sessions?, .models?, .efforts?: picker = context.picker
    default: picker = nil
    }
    let editsWithDial = context.editingDraft && !context.applicationProfile.alwaysScrolls
    state.mode = picker ?? (editsWithDial ? .editing : .browse)

    if control == .forceEscape { return .sendEscape }
    if control == .voice {
        // The independent Fn dictation adapter owns this action.
        return .none
    }

    // Composition can be active inside a recognized picker's search field.
    // Its candidate window takes precedence until the input method dismisses it.
    // Unknown modals also receive native confirmation/cancellation only: a
    // rotation is not enough information to guess their navigation semantics.
    if context.compositionActive || (context.modalOpen && picker == nil) {
        switch control {
        case .dial, .ok: return .sendReturn
        case .escape: return .sendEscape
        default: return .none
        }
    }

    if picker != nil {
        switch control {
        case .left: return .moveCandidate(-1)
        case .right: return .moveCandidate(1)
        case .dial, .ok: return .confirmCandidate
        case .escape: return .cancelPicker
        case .settings:
            // Inside a combined effort popover, the model action opens its model list.
            return picker == .efforts ? .openModels : .none
        default: return .none
        }
    }

    switch control {
    case .dial: return .openSessions
    case .settings: return .openModels
    case .left:
        return editsWithDial ? .moveCursor(-1) : .scroll(1)
    case .right:
        return editsWithDial ? .moveCursor(1) : .scroll(-1)
    case .escape:
        return editsWithDial ? .deleteBackward : .sendEscape
    case .ok: return .sendReturn
    default: return .none
    }
}
