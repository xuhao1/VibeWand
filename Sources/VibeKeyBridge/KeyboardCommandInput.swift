import AppKit
import ApplicationServices

/// The keyboard's part in command mode. Holding the chosen right-hand modifier
/// on its own speaks a command. While the coordinator is asking or acting, the
/// arrows, Return and Escape answer it and are kept from the app in front;
/// every other key passes through untouched.
@MainActor
final class KeyboardCommandInput {
    enum Answer { case previous, next, confirm, stop }
    var key = CommandHotkey.none
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// The modifier turned out to be part of an ordinary shortcut.
    var onAbandon: (() -> Void)?
    /// Returns true when the coordinator took the key.
    var answer: ((Answer) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false, speaking = false
    private var pressToken = 0
    /// Long enough to tell a held key from a modifier on its way to a shortcut.
    static let holdDelay: TimeInterval = 0.18

    /// Needs the Accessibility grant; call again once it has been given.
    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue | 1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let input = Unmanaged<KeyboardCommandInput>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { input.handle(type, event) } ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap; self.source = source
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil; source = nil; held = false; speaking = false
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        // Keys VibeWand posts itself are not the user answering.
        guard event.getIntegerValueField(.eventSourceUserData) != AccessibilityAdapter.syntheticMarker else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            guard let wanted = key.keyCode, code == wanted else { return false }
            let down = event.flags.contains(key.flag)
            if down, !held {
                held = true; pressToken += 1
                let token = pressToken
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.held, self.pressToken == token else { return }
                        self.speaking = true; self.onPress?()
                    }
                }
            } else if !down, held {
                held = false
                if speaking { speaking = false; onRelease?() }
            }
            return false
        }
        if held {
            // Another key while the modifier is down: this is a shortcut, not a command.
            held = false
            if speaking { speaking = false; onAbandon?() }
            return false
        }
        switch code {
        case 126, 123: return answer?(.previous) ?? false
        case 125, 124: return answer?(.next) ?? false
        case 36, 76: return answer?(.confirm) ?? false
        case 53: return answer?(.stop) ?? false
        default: return false
        }
    }
}
