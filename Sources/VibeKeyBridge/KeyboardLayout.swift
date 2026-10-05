import AppKit
import ApplicationServices
import AU05Device

/// One key with the modifiers held beside it, known by the code the keyboard sends for it. Any key that sends one
/// can stand here, named or not: the extra keys of a larger or custom keyboard are told apart by that code alone,
/// which is why a combination is recorded by pressing it rather than picked from a list.
struct KeyChord: Codable, Hashable {
    var code: CGKeyCode
    var command = false
    var option = false
    var control = false
    var shift = false

    init(code: CGKeyCode, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.code = code; self.command = command; self.option = option; self.control = control; self.shift = shift
    }
    /// A key as it was pressed, with the modifiers that were down.
    init(code: CGKeyCode, flags: CGEventFlags) {
        self.init(code: code, command: flags.contains(.maskCommand), option: flags.contains(.maskAlternate),
                  control: flags.contains(.maskControl), shift: flags.contains(.maskShift))
    }
    var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift { flags.insert(.maskShift) }
        return flags
    }
    var label: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + Self.name(code) }

    /// What a key is called: the name VibeWand has for a key it can also send, the name of a key only larger
    /// keyboards have, and for anything else the number the keyboard sends.
    static func name(_ code: CGKeyCode) -> String {
        ApplicationKey.allCases.first { $0.keyCode == code }?.title ?? beyond[code] ?? L10n.tr("键 \(code)", "Key \(code)")
    }
    private static let beyond: [CGKeyCode: String] = [
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5", 88: "Num 6", 89: "Num 7", 91: "Num 8", 92: "Num 9",
        65: "Num .", 67: "Num *", 69: "Num +", 75: "Num /", 78: "Num −", 81: "Num =", 76: "Num Enter", 71: "Clear",
        114: "Help", 110: "Menu", 10: "§", 93: "¥", 94: "_", 95: "Num ,", 102: "英数", 104: "かな"
    ]
    /// The keys text is typed and edited with. Alone, one of these has to stay the app's.
    static let typing: Set<CGKeyCode> = Set(ApplicationKey.allCases.filter {
        ![.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .home, .end, .pageUp, .pageDown].contains($0)
    }.map(\.keyCode))
}

/// The key combinations that stand for a device's controls when the keyboard is the device. Each of the six
/// inputs every layout has is one combination; what a control then does, pressed, double-pressed or held,
/// is set like any other device's.
struct KeyboardLayout: Codable, Equatable {
    static let storageKey = "keyboardLayout"
    /// The inputs a keyboard stands in for, in the order the overlay lists them.
    static let controls: [DeviceControl] = [.voice, .dial, .left, .right, .ok, .escape]
    /// Three modifiers together are left alone by nearly every app, and a remapped "hyper" key gives them one finger.
    static let standard = KeyboardLayout(chords: [
        DeviceControl.voice.rawValue: chord(.space), DeviceControl.dial.rawValue: chord(.up),
        DeviceControl.left.rawValue: chord(.left), DeviceControl.right.rawValue: chord(.right),
        DeviceControl.ok.rawValue: chord(.returnKey), DeviceControl.escape.rawValue: chord(.backspace)
    ])
    private static func chord(_ key: ApplicationKey) -> KeyChord { KeyChord(code: key.keyCode, command: true, option: true, control: true) }

    var chords: [String: KeyChord]

    /// What is in force, read once and replaced whenever the user changes a combination.
    nonisolated(unsafe) static var current = load()
    static func load(_ defaults: UserDefaults = .standard) -> KeyboardLayout {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(KeyboardLayout.self, from: $0) } ?? standard
    }
    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
        if defaults == .standard { Self.current = self }
    }

    func chord(_ control: DeviceControl) -> KeyChord? { chords[control.rawValue] }
    /// How a control's combination is written on a key cap. Empty when it has none.
    func label(_ control: DeviceControl) -> String { chord(control)?.label ?? "" }
    /// The control a key stands for when exactly these modifiers are down.
    func control(code: CGKeyCode, flags: CGEventFlags) -> DeviceControl? {
        let pressed = KeyChord(code: code, flags: flags)
        return Self.controls.first { control in chord(control).map { Self.usable($0) && $0 == pressed } ?? false }
    }
    /// A key that text is typed or edited with has to come with a modifier, or every press of it would be taken
    /// from what is being typed. Any other key may stand alone: a function key, the number pad, and whatever
    /// else a larger or custom keyboard adds.
    static func usable(_ chord: KeyChord) -> Bool {
        chord.command || chord.option || chord.control || !KeyChord.typing.contains(chord.code)
    }
    /// Controls that share a combination with an earlier one: only the first would ever fire.
    var clashes: Set<DeviceControl> {
        var seen: Set<KeyChord> = [], result: Set<DeviceControl> = []
        for control in Self.controls {
            guard let chord = chord(control) else { continue }
            if !seen.insert(chord).inserted { result.insert(control) }
        }
        return result
    }
}

/// The keyboard as a device: it turns the layout's key combinations into the same press, release and turn
/// events a handset sends, and keeps those keys from the app in front. Every other key passes through untouched.
/// Like the other sources it lives on the main thread.
final class KeyboardInputSource: HIDEventSource {
    private(set) var connection: AU05Connection = .stopped
    var onConnection: ((AU05Connection) -> Void)?
    var onEvent: ((AU05Event) -> Void)?
    /// The layout in force. Tests supply their own.
    var layout: () -> KeyboardLayout = { KeyboardLayout.current }
    /// Set while the user is choosing a combination: the next key pressed is handed over, with the modifiers held,
    /// instead of standing for a control. It is seen here, where the layout itself listens, so that a key the
    /// system would otherwise take for a shortcut of its own can be chosen, and like any control's key it is kept
    /// from the app in front.
    nonisolated(unsafe) static var capture: ((KeyChord) -> Void)?
    /// The key `capture` just took, until it is let go: its repeats and its release stand for nothing.
    private var captured: CGKeyCode?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    /// Keys that are down as a control, by key code: the release belongs to the control whatever modifiers remain.
    private var held: [CGKeyCode: DeviceControl] = [:]
    private var sequence: UInt64 = 0

    /// Listening needs the Accessibility grant. Until it is given the keyboard counts as not connected,
    /// and is tried again.
    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let input = Unmanaged<KeyboardInputSource>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { input.receive(type, event) } ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            set(.blocked(L10n.tr("键盘：需要辅助功能权限", "Keyboard: Accessibility access is needed")))
            retry?.invalidate()
            retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.start() } }
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap; self.source = source
        set(.ready)
    }
    func stop() {
        retry?.invalidate(); retry = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil; source = nil; held = [:]; captured = nil
        set(.stopped)
    }
    private func set(_ state: AU05Connection) { connection = state; onConnection?(state) }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        // Keys VibeWand posts itself are its own actions, not the user's hand.
        guard event.getIntegerValueField(.eventSourceUserData) != AccessibilityAdapter.syntheticMarker else { return false }
        return handle(code: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags, down: type == .keyDown,
                      repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    }

    /// One key event. Returns true when the key was a control's and must not reach the app in front.
    func handle(code: CGKeyCode, flags: CGEventFlags, down: Bool, repeated: Bool) -> Bool {
        if code == captured {
            if !down { captured = nil }
            return true
        }
        if down, !repeated, let capture = Self.capture {
            captured = code
            capture(KeyChord(code: code, flags: flags))
            return true
        }
        if !down {
            guard let control = held.removeValue(forKey: code) else { return false }
            if control != .left, control != .right { emit(control, .up) }
            return true
        }
        // A key held down repeats: a turn keeps turning, a button stays pressed.
        if repeated, let control = held[code] {
            if control == .left || control == .right { emit(control, .pulse) }
            return true
        }
        guard let control = layout().control(code: code, flags: flags) else { return false }
        held[code] = control
        emit(control, control == .left || control == .right ? .pulse : .down)
        return true
    }
    private func emit(_ control: DeviceControl, _ phase: AU05Phase) {
        guard let input = AU05Control(rawValue: control.rawValue) else { return }
        sequence += 1
        onEvent?(AU05Event(control: input, phase: phase, sequence: sequence, uptime: ProcessInfo.processInfo.systemUptime))
    }
}
