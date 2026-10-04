import AppKit
import ApplicationServices
import AU05Device

struct InputMappings: Codable {
    var bindings: [String: String] = [:]
    private var held: [AU05Control: DeviceControl] = [:]
    enum CodingKeys: String, CodingKey { case bindings }
    func resolve(_ input: AU05Control) -> DeviceControl? {
        let value = bindings[input.rawValue] ?? input.rawValue
        return DeviceControl(rawValue: value) // "disabled" resolves to nil.
    }
    mutating func route(_ input: AU05Control, phase: AU05Phase) -> [(DeviceControl, InputPhase)] {
        switch phase {
        case .pulse:
            return resolve(input).map { [($0, .pulse)] } ?? []
        case .down:
            guard held[input] == nil, let control = resolve(input) else { return [] }
            let alreadyHeld = held.values.contains(control)
            held[input] = control
            return alreadyHeld ? [] : [(control, .down)]
        case .up, .cancel:
            guard let control = held.removeValue(forKey: input) else { return [] }
            return held.values.contains(control) ? [] : [(control, phase == .up ? .up : .cancel)]
        }
    }
    mutating func reset() { held.removeAll() }
}

@MainActor
final class FnDictation {
    private(set) var held = false
    private let source = CGEventSource(stateID: .privateState)
    private var pulseTimer: Timer?
    var send: ((Bool) -> Void)? // Test seam; production uses CGEvent.
    func setHeld(_ down: Bool) {
        pulseTimer?.invalidate(); pulseTimer = nil
        guard held != down else { return }; held = down
        if let send { send(down); return }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 63, keyDown: down) else { return }
        event.type = .flagsChanged
        var flags = CGEventSource.flagsState(.combinedSessionState)
        if down { flags.insert(.maskSecondaryFn) } else { flags.remove(.maskSecondaryFn) }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
    func pulse() {
        guard !held else { return }
        setHeld(true)
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.setHeld(false) }
        }
    }
    func cancel() { setHeld(false) }
}

extension DeviceControl {
    var label: String {
        switch self {
        case .voice: return L10n.tr("听写（按住 Fn）", "Dictation (hold Fn)")
        case .ok: return L10n.tr("确认 / Enter", "Confirm / Enter")
        case .escape: return L10n.tr("取消 / 删除", "Cancel / delete")
        case .dial: return L10n.tr("旋钮按压 / 会话", "Dial press / chats")
        case .left: return L10n.tr("向左 / 上一个", "Left / previous")
        case .right: return L10n.tr("向右 / 下一个", "Right / next")
        case .settings: return L10n.tr("模型 / 强度", "Model / effort")
        case .forceEscape: return L10n.tr("原生 Escape", "Native Escape")
        case .l1: return "L1"
        case .l2: return "L2"
        case .leftStickPress: return L10n.tr("左摇杆按下 · L3", "Left stick press · L3")
        case .rightStickPress: return L10n.tr("右摇杆按下 · R3", "Right stick press · R3")
        case .leftStickUp: return L10n.tr("左摇杆 ↑", "Left stick ↑")
        case .leftStickDown: return L10n.tr("左摇杆 ↓", "Left stick ↓")
        case .leftStickLeft: return L10n.tr("左摇杆 ←", "Left stick ←")
        case .leftStickRight: return L10n.tr("左摇杆 →", "Left stick →")
        case .rightStickUp: return L10n.tr("右摇杆 ↑", "Right stick ↑")
        case .rightStickDown: return L10n.tr("右摇杆 ↓", "Right stick ↓")
        case .rightStickLeft: return L10n.tr("右摇杆 ←", "Right stick ←")
        case .rightStickRight: return L10n.tr("右摇杆 →", "Right stick →")
        case .dpadUp: return L10n.tr("方向键 ↑", "D-pad ↑")
        case .dpadDown: return L10n.tr("方向键 ↓", "D-pad ↓")
        case .dpadLeft: return L10n.tr("方向键 ←", "D-pad ←")
        case .dpadRight: return L10n.tr("方向键 →", "D-pad →")
        case .options: return L10n.tr("选项键", "Options")
        case .create: return L10n.tr("分享键", "Share")
        case .home: return L10n.tr("主页键", "Home")
        case .touchpad: return L10n.tr("触控板按下", "Touchpad press")
        case .mute: return L10n.tr("静音键", "Mute")
        case .power: return L10n.tr("电源键", "Power")
        case .volumeUp: return L10n.tr("音量 +", "Volume +")
        case .volumeDown: return L10n.tr("音量 −", "Volume −")
        }
    }
}
