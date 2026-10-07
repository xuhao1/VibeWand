import AppKit
import ApplicationServices

@MainActor
final class ApplicationSwitcher {
    private(set) var active = false
    private let source = CGEventSource(stateID: .privateState)
    private var timeout: Timer?
    var send: ((CGKeyCode, Bool, CGEventFlags) -> Void)?
    var onChange: (() -> Void)?
    func begin() {
        guard !active else { return }
        active = true
        post(55, true, .maskCommand)
        key(48, flags: .maskCommand)
        armTimeout(); onChange?()
    }
    func move(_ direction: Int) {
        guard active else { return }
        key(48, flags: direction < 0 ? [.maskCommand, .maskShift] : .maskCommand)
        armTimeout()
    }
    func confirm() {
        guard active else { return }
        active = false; timeout?.invalidate(); timeout = nil
        post(55, false, []); onChange?()
    }
    func cancel() {
        guard active else { return }
        key(53, flags: .maskCommand); confirm()
    }
    private func armTimeout() {
        timeout?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        timeout = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func key(_ code: CGKeyCode, flags: CGEventFlags) {
        post(code, true, flags); post(code, false, flags)
    }
    private func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        if let send { send(code, down, flags); return }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        if code == 55 { event.type = .flagsChanged }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}
