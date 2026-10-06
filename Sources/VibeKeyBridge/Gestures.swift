import Foundation

enum GestureScope: String, CaseIterable, Codable {
    case global, reading, editing, sessions, models, efforts, applications, command
    var label: String {
        switch self {
        case .global: return L10n.tr("通用默认", "Default")
        case .reading: return L10n.tr("阅读 / 空草稿", "Reading / empty draft")
        case .editing: return L10n.tr("编辑文字", "Editing text")
        case .sessions: return L10n.tr("会话选择", "Chat picker")
        case .models: return L10n.tr("模型选择", "Model picker")
        case .efforts: return L10n.tr("强度选择", "Effort picker")
        case .applications: return L10n.tr("切换应用", "App switcher")
        case .command: return L10n.tr("命令进行中", "Command in progress")
        }
    }
}
enum GestureKind: String, CaseIterable, Codable {
    case single, double, long, hold, rotate, heldLeft, heldRight
    var label: String {
        switch self {
        case .single: return L10n.tr("单击", "Press")
        case .double: return L10n.tr("双击", "Double press")
        case .long: return L10n.tr("长按", "Long press")
        case .hold: return L10n.tr("按住 / 松开", "Hold / release")
        case .rotate: return L10n.tr("旋转", "Turn")
        case .heldLeft: return L10n.tr("按住后左旋", "Hold + turn left")
        case .heldRight: return L10n.tr("按住后右旋", "Hold + turn right")
        }
    }
}
enum ActionCategory: String, CaseIterable {
    case system, application, vibeWand
    var label: String {
        switch self {
        case .system: return L10n.tr("系统功能", "System")
        case .application: return L10n.tr("应用功能", "Application")
        case .vibeWand: return L10n.tr("VibeWand 内功能", "VibeWand")
        }
    }
}

enum GestureAction: String, CaseIterable, Codable {
    case none, contextDial, contextLeft, contextRight, contextConfirm, contextEscape
    case sessions, models, deleteBackward, enter, escape, cursorLeft, cursorRight, scrollUp, scrollDown
    case previousCandidate, nextCandidate, confirmCandidate, cancelPicker
    case dictation, command, pointerClick, switchApplications, previousApplication, nextApplication, confirmApplication, cancelApplication
    case toggleOverlay, openSettings, toggleGuide, showControls
    var category: ActionCategory {
        switch self {
        case .dictation, .command, .pointerClick, .switchApplications, .previousApplication, .nextApplication, .confirmApplication, .cancelApplication:
            return .system
        case .none, .toggleOverlay, .openSettings, .toggleGuide, .showControls:
            return .vibeWand
        default: return .application
        }
    }
    var label: String {
        switch self {
        case .none: return L10n.tr("不执行", "Unassigned")
        case .contextDial: return L10n.tr("按应用：会话 / 标签页 / 确认", "Context: chat / tab / confirm")
        case .contextLeft: return L10n.tr("按场景：光标左移 / 下滚 / 上个候选", "Context: cursor left / scroll down / previous")
        case .contextRight: return L10n.tr("按场景：光标右移 / 上滚 / 下个候选", "Context: cursor right / scroll up / next")
        case .contextConfirm: return L10n.tr("按场景：确认 / Enter", "Context: confirm / Enter")
        case .contextEscape: return L10n.tr("按场景：删除 / 取消", "Context: delete / cancel")
        case .sessions: return L10n.tr("打开会话选择", "Open chat picker")
        case .models: return L10n.tr("打开模型 / 强度", "Open model / effort picker")
        case .deleteBackward: return L10n.tr("删除光标前字符 / 选区", "Delete previous character / selection")
        case .enter: return "Enter"
        case .escape: return L10n.tr("原生 Escape", "Native Escape")
        case .cursorLeft: return L10n.tr("光标向左", "Move cursor left")
        case .cursorRight: return L10n.tr("光标向右", "Move cursor right")
        case .scrollUp: return L10n.tr("向上滚屏", "Scroll up")
        case .scrollDown: return L10n.tr("向下滚屏", "Scroll down")
        case .previousCandidate: return L10n.tr("上一个候选（↑）", "Previous item (↑)")
        case .nextCandidate: return L10n.tr("下一个候选（↓）", "Next item (↓)")
        case .confirmCandidate: return L10n.tr("确认候选", "Confirm selection")
        case .cancelPicker: return L10n.tr("取消选择", "Cancel selection")
        case .dictation: return L10n.tr("听写（按住说话）", "Dictation (hold to speak)")
        case .command: return L10n.tr("命令（按住说话）", "Command (hold to speak)")
        case .pointerClick: return L10n.tr("点击光标位置（鼠标左键）", "Click at pointer (left mouse button)")
        case .switchApplications: return L10n.tr("打开应用切换（⌘Tab）", "Open app switcher (⌘Tab)")
        case .previousApplication: return L10n.tr("上一个应用", "Previous app")
        case .nextApplication: return L10n.tr("下一个应用", "Next app")
        case .confirmApplication: return L10n.tr("切换到选中应用", "Switch to selected app")
        case .cancelApplication: return L10n.tr("取消应用切换", "Cancel app switcher")
        case .toggleOverlay: return L10n.tr("显示 / 隐藏悬浮面板", "Show / hide overlay")
        case .openSettings: return L10n.tr("打开 VibeWand 设置", "Open VibeWand settings")
        case .toggleGuide: return L10n.tr("展开 / 收起按键说明", "Show / hide button guide")
        case .showControls: return L10n.tr("打开 / 关闭按键一览", "Show / hide the controls card")
        }
    }
    /// The picture that stands for the action beside its caption.
    var symbol: String {
        switch self {
        case .none: return "minus"
        case .dictation: return "mic"
        case .command: return "sparkles"
        case .contextDial, .sessions: return "bubble.left.and.bubble.right"
        case .models: return "slider.horizontal.3"
        case .contextConfirm, .enter, .confirmCandidate, .confirmApplication: return "return"
        case .contextEscape, .escape, .cancelPicker, .cancelApplication: return "arrow.uturn.backward"
        case .deleteBackward: return "delete.left"
        case .scrollUp, .scrollDown: return "arrow.up.arrow.down"
        case .contextLeft, .contextRight, .cursorLeft, .cursorRight: return "arrow.left.arrow.right"
        case .previousCandidate, .nextCandidate: return "list.bullet"
        case .switchApplications, .previousApplication, .nextApplication: return "square.on.square"
        case .pointerClick: return "cursorarrow.click"
        case .toggleOverlay: return "macwindow"
        case .openSettings: return "gearshape"
        case .toggleGuide, .showControls: return "gamecontroller"
        }
    }
    static func legacy(_ control: DeviceControl?) -> GestureAction {
        switch control {
        case .dial: return .contextDial
        case .left: return .contextLeft
        case .right: return .contextRight
        case .ok: return .contextConfirm
        case .escape: return .contextEscape
        case .voice: return .dictation
        case .settings: return .models
        case .forceEscape: return .escape
        case .l1, .l2, .r1, .r2, .leftStickPress, .rightStickPress,
             .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
             .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
             .options, .create, .home, .touchpad, .mute,
             .power, .volumeUp, .volumeDown, nil: return .none
        }
    }
}
struct GestureConfiguration: Codable {
    var schemaVersion = 1
    var doubleClickInterval = 0.28
    var longPressInterval = 0.55
    // Only overrides are stored. Missing entries inherit the built-in preset.
    var overrides: [String: GestureAction] = [:]
    /// The template's bindings for command mode, present only while it is on and has a model to run on.
    /// They sit under the user's own choices and are never saved.
    var commandLayer: [String: GestureAction] = [:]
    private enum CodingKeys: String, CodingKey { case schemaVersion, doubleClickInterval, longPressInterval, overrides }
    static func key(_ scope: GestureScope, _ control: DeviceControl, _ kind: GestureKind) -> String {
        "\(scope.rawValue).\(control.rawValue).\(kind.rawValue)"
    }
    func explicit(_ scope: GestureScope, _ control: DeviceControl, _ kind: GestureKind) -> GestureAction? {
        overrides[Self.key(scope, control, kind)]
    }
    func action(_ scope: GestureScope, _ control: DeviceControl, _ kind: GestureKind) -> GestureAction {
        if let custom = explicit(scope, control, kind) { return custom }
        // While the coordinator is asking or acting, the device answers it the way it answers a picker.
        if scope == .command { return action(.models, control, kind) }
        if scope == .applications {
            switch (control, kind) {
            case (.left, .rotate), (.dial, .heldLeft): return .previousApplication
            case (.right, .rotate), (.dial, .heldRight): return .nextApplication
            case (.dial, .single), (.ok, .single): return .confirmApplication
            case (.escape, .single), (.escape, .long): return .cancelApplication
            case (.dial, .double), (.dial, .long): return .none
            default: break
            }
        }
        if scope != .global, let custom = explicit(.global, control, kind) { return custom }
        if let layered = commandLayer[Self.key(.global, control, kind)] { return layered }
        // A stick or the direction pad moves the way it points: up is up in a page and in a list, and
        // sideways moves the caret. Saved configurations get these too; an explicit override above wins.
        if let direction = control.direction, kind == .rotate {
            // A direction-pad button the user gave a click is theirs: the step stands aside for it.
            if !control.isStickDirection, [GestureKind.single, .double, .long].contains(where: {
                (explicit(scope, control, $0) ?? explicit(.global, control, $0) ?? .none) != .none
            }) { return .none }
            let backwards = direction == .up || direction == .left
            switch scope {
            case .applications: return backwards ? .previousApplication : .nextApplication
            case .sessions, .models, .efforts: return backwards ? .previousCandidate : .nextCandidate
            default:
                switch direction {
                case .up: return .scrollUp
                case .down: return .scrollDown
                // With no draft there is no caret to move.
                case .left: return scope == .reading ? .none : .cursorLeft
                case .right: return scope == .reading ? .none : .cursorRight
                }
            }
        }
        let builtInNavigation = ((control == .left || control == .right) && kind == .rotate)
            || (control == .dial && (kind == .heldLeft || kind == .heldRight))
        if builtInNavigation {
            let backwards = control == .left || kind == .heldLeft
            switch scope {
            case .reading: return backwards ? .scrollDown : .scrollUp
            case .editing: return backwards ? .cursorLeft : .cursorRight
            case .sessions, .models, .efforts: return backwards ? .previousCandidate : .nextCandidate
            default: break
            }
        }
        // In an effort popover a second long press continues to the model list.
        if [.sessions, .models].contains(scope) && control == .dial && kind == .long { return .none }
        switch (control, kind) {
        case (.dial, .single): return .contextDial
        case (.dial, .double): return .switchApplications
        case (.dial, .long): return .models
        case (.dial, .heldLeft), (.left, .rotate): return .contextLeft
        case (.dial, .heldRight), (.right, .rotate): return .contextRight
        case (.ok, .single): return .contextConfirm
        case (.escape, .single): return .contextEscape
        // Same scene rule as the press; while editing, the runtime repeats it until release.
        case (.escape, .long): return .contextEscape
        case (.voice, .hold): return .dictation
        case (.settings, .single): return .models
        case (.forceEscape, .single): return .escape
        default: return .none
        }
    }
    /// The gestures among `kinds` that can fire on a button in a scene: a hold owns the whole press,
    /// and a step leaves no room for clicks.
    func live(_ scope: GestureScope, _ control: DeviceControl, _ kinds: [GestureKind]) -> [GestureKind] {
        guard !control.isStickDirection, control != .left, control != .right else { return kinds }
        let clicks: Set<GestureKind> = [.single, .double, .long]
        if action(scope, control, .hold) != .none { return kinds.filter { !clicks.contains($0) && $0 != .rotate } }
        if action(scope, control, .rotate) != .none { return kinds.filter { !clicks.contains($0) } }
        return kinds
    }
    mutating func set(_ scope: GestureScope, _ control: DeviceControl, _ kind: GestureKind, _ action: GestureAction?) {
        overrides[Self.key(scope, control, kind)] = action
    }
    func validate() throws {
        guard schemaVersion == 1, (0.15...0.6).contains(doubleClickInterval),
              (0.35...2).contains(longPressInterval), longPressInterval > doubleClickInterval,
              overrides.count <= GestureScope.allCases.count * DeviceControl.allCases.count * GestureKind.allCases.count
        else { throw ConfigurationError.invalid }
        for key in overrides.keys {
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 3, GestureScope(rawValue: parts[0]) != nil,
                  DeviceControl(rawValue: parts[1]) != nil, GestureKind(rawValue: parts[2]) != nil else { throw ConfigurationError.invalid }
        }
    }
    enum ConfigurationError: LocalizedError {
        case invalid
        var errorDescription: String? { L10n.tr("配置格式或手势时间范围不正确。", "Invalid configuration format or gesture timing.") }
    }
}

extension GestureConfiguration {
    /// A layout written by a later version may name an action this one does not have. That one binding is left
    /// out and the rest is read: failing here would throw away every saved layout, for every device.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        doubleClickInterval = try values.decode(Double.self, forKey: .doubleClickInterval)
        longPressInterval = try values.decode(Double.self, forKey: .longPressInterval)
        overrides = try values.decode([String: String].self, forKey: .overrides).compactMapValues(GestureAction.init(rawValue:))
    }
}

struct GestureSignal: Equatable {
    var control: DeviceControl
    var kind: GestureKind
    var action: GestureAction
    var phase: InputPhase
    var token: UInt64
}

/// Pure clock-driven recognizer. A double click never also executes its first
/// single click. Cancellation never manufactures a click or a key release tap.
struct GestureEngine {
    private struct Press {
        var started: TimeInterval
        var token: UInt64
        var single: GestureAction
        var double: GestureAction
        var long: GestureAction
        var hold: GestureAction
        var longInterval: TimeInterval
        var doubleInterval: TimeInterval
        var suppressed = false
        var secondClick = false
        /// A step fires as the button goes down and again while it stays down, like an arrow key.
        var step = GestureAction.none
        var nextStep: TimeInterval = 0
    }
    /// The pace a tilted stick repeats at.
    static let stepDelay = GameControllerDecoder.repeatDelay, stepInterval = GameControllerDecoder.repeatInterval
    private struct Click { var press: Press; var due: TimeInterval }
    private var presses: [DeviceControl: Press] = [:]
    private var clicks: [DeviceControl: Click] = [:]
    private var sequence: UInt64 = 0
    var held: Set<DeviceControl> { Set(presses.keys) }
    func token(for control: DeviceControl) -> UInt64? { presses[control]?.token }
    mutating func receive(_ control: DeviceControl, phase: InputPhase, now: TimeInterval,
                          scope: GestureScope, config: GestureConfiguration,
                          allowHeldRotation: Bool = true) -> [GestureSignal] {
        let holdAction: GestureAction = control.isStickDirection ? .none : config.action(scope, control, .hold)
        let isRotation = control == .left || control == .right || control.isStickDirection
        // A hold owns its whole press. Cancel any pending click before advancing
        // time, so beginning dictation cannot also flush an older Confirm tap.
        if holdAction != .none && (phase == .down || (phase == .pulse && !isRotation)) {
            clicks.removeValue(forKey: control)
        }
        // A release ends a step where it is: there is no last one on the way up.
        if phase == .up { presses[control]?.step = .none }
        var out = phase == .cancel ? [] : tick(now: now)
        switch phase {
        case .down:
            guard presses[control] == nil else { return out }
            sequence &+= 1
            // A button with a step bound leaves no room for clicks; a hold still comes first.
            let step: GestureAction = holdAction == .none && !isRotation ? config.action(scope, control, .rotate) : .none
            var press = Press(started: now, token: sequence,
                single: config.action(scope, control, .single), double: config.action(scope, control, .double),
                long: config.action(scope, control, .long), hold: holdAction,
                longInterval: config.longPressInterval, doubleInterval: config.doubleClickInterval,
                suppressed: holdAction != .none || control.isStickDirection || step != .none,
                step: step, nextStep: now + Self.stepDelay)
            if press.hold == .none, let previous = clicks[control], now <= previous.due,
               previous.press.double == press.double, press.double != .none {
                clicks.removeValue(forKey: control); press.secondClick = true
            }
            presses[control] = press
            if press.hold != .none { out.append(signal(control, .hold, press.hold, .down, press.token)) }
            else if step != .none { out.append(signal(control, .rotate, step, .pulse, press.token)) }
        case .up, .cancel:
            if phase == .cancel { clicks.removeValue(forKey: control) }
            guard let press = presses.removeValue(forKey: control) else { return out }
            if press.hold != .none { out.append(signal(control, .hold, press.hold, phase, press.token)) }
            if phase == .cancel { clicks.removeValue(forKey: control); return out }
            guard !press.suppressed else { return out }
            if press.secondClick, press.double != .none {
                out.append(signal(control, .double, press.double, .pulse, press.token))
            } else if press.double != .none {
                clicks[control] = Click(press: press, due: now + press.doubleInterval)
            } else if press.single != .none { out.append(signal(control, .single, press.single, .pulse, press.token)) }
        case .pulse:
            sequence &+= 1
            let kind: GestureKind
            let owner: DeviceControl
            if isRotation {
                if allowHeldRotation, !control.isStickDirection, var dial = presses[.dial] {
                    dial.suppressed = true; presses[.dial] = dial
                    kind = control == .left ? .heldLeft : .heldRight; owner = .dial
                } else { kind = .rotate; owner = control }
            } else {
                // A pulse-only source cannot represent a held action. Do not
                // replace it with a potentially destructive single-click action.
                guard holdAction == .none else { return out }
                kind = .single; owner = control
            }
            let action = config.action(scope, owner, kind)
            if action != .none { out.append(signal(control, kind, action, .pulse, sequence)) }
        }
        return out
    }
    mutating func tick(now: TimeInterval) -> [GestureSignal] {
        var out: [GestureSignal] = []
        for (control, click) in clicks.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where now >= click.due {
            clicks.removeValue(forKey: control)
            if click.press.single != .none { out.append(signal(control, .single, click.press.single, .pulse, click.press.token)) }
        }
        for (control, var press) in presses.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if press.step != .none {
                // One step a tick: a late tick never catches up with a burst.
                guard now >= press.nextStep else { continue }
                press.nextStep = now + Self.stepInterval; presses[control] = press
                out.append(signal(control, .rotate, press.step, .pulse, press.token))
            } else if !press.suppressed && now - press.started >= press.longInterval {
                press.suppressed = true; presses[control] = press; clicks.removeValue(forKey: control)
                if press.long != .none { out.append(signal(control, .long, press.long, .pulse, press.token)) }
            }
        }
        return out
    }
    mutating func reset() -> [GestureSignal] {
        let out = presses.compactMap { control, press -> GestureSignal? in
            press.hold == .none ? nil : signal(control, .hold, press.hold, .cancel, press.token)
        }
        presses.removeAll(); clicks.removeAll(); return out
    }
    private func signal(_ control: DeviceControl, _ kind: GestureKind, _ action: GestureAction,
                        _ phase: InputPhase, _ token: UInt64) -> GestureSignal {
        GestureSignal(control: control, kind: kind, action: action, phase: phase, token: token)
    }
}
