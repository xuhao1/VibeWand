import Foundation

/// A late transcript belongs to the same app, window and focused editor that
/// owned key-down. Keep this policy independent of AX calls and key injection.
enum DictationDelivery {
    static func accepts(target: TargetIdentity, observation: TargetObservation, frontmostPID: pid_t?, ownsWrite: Bool = false) -> Bool {
        guard let current = observation.identity else { return false }
        let sameEditor = current.pid == target.pid && current.windowHash == target.windowHash &&
            current.focusedHash == target.focusedHash && current.focusedIdentifier == target.focusedIdentifier
        return sameEditor && (current.windowTitle == target.windowTitle || ownsWrite) && frontmostPID == target.pid &&
        observation.context.targetAvailable && (observation.context.editorFocused || observation.editor != nil) &&
        !observation.context.modalOpen && !observation.context.compositionActive && observation.context.picker == nil
    }
}
