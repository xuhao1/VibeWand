import Foundation

struct HUDGestureHint: Equatable {
    var kind: GestureKind
    var action: GestureAction
    var caption: String
    var title: String {
        let gesture: String
        switch kind {
        case .single: gesture = L10n.tr("单击", "Press")
        case .double: gesture = L10n.tr("双击", "Double")
        case .long: gesture = L10n.tr("长按", "Long")
        case .hold: gesture = L10n.tr("按住", "Hold")
        // A step is the plain press of its button or the tilt of its stick: the caption says it all.
        case .rotate: return caption
        case .heldLeft: gesture = L10n.tr("按住左旋", "Hold + left")
        case .heldRight: gesture = L10n.tr("按住右旋", "Hold + right")
        }
        return "\(gesture) · \(caption)"
    }
}

/// The HUD explains the effective mapping, including custom overrides. Its
/// concise captions never substitute for runtime focus/IME checks.
enum HUDGuidance {
    static func hints(template: DeviceTemplate, configuration: GestureConfiguration,
                      scope: GestureScope, profile: ApplicationProfile) -> [DeviceControl: [HUDGestureHint]] {
        Dictionary(uniqueKeysWithValues: template.controls.map { item in
            (item.control, configuration.live(scope, item.control, item.gestures).compactMap { kind in
                let action = configuration.action(scope, item.control, kind)
                let deletes = action == .deleteBackward || (action == .contextEscape && scope == .editing)
                return action == .none ? nil : HUDGestureHint(kind: kind, action: action,
                    caption: kind == .long && deletes ? L10n.tr("连续退格", "Keep deleting")
                        : caption(action, scope: scope, profile: profile))
            })
        })
    }

    static func primary(_ control: DeviceControl, snapshot: HUDSnapshot) -> HUDGestureHint? {
        let hints = snapshot.controlHints[control] ?? []
        return hints.first(where: { $0.kind == .hold }) ?? hints.first
    }

    /// Two opposite controls said in one breath where their actions are a pair, e.g. "↑↓ Scroll".
    static func pair(_ first: HUDGestureHint?, _ second: HUDGestureHint?, _ names: (String, String)) -> String? {
        switch (first?.action, second?.action) {
        case (nil, nil): return nil
        case (.scrollUp?, .scrollDown?): return names.0 + names.1 + " " + L10n.tr("滚屏", "Scroll")
        case (.cursorLeft?, .cursorRight?): return names.0 + names.1 + " " + L10n.tr("移动光标", "Move caret")
        case (.previousCandidate?, .nextCandidate?), (.previousApplication?, .nextApplication?):
            return names.0 + names.1 + " " + L10n.tr("上一个 / 下一个", "Previous / next")
        default: return "\(names.0) \(first?.caption ?? "—") · \(names.1) \(second?.caption ?? "—")"
        }
    }
    /// What the four directions of a stick or the direction pad do, on as few lines as say it.
    static func directions(_ hints: [DeviceControl: [HUDGestureHint]], up: DeviceControl, down: DeviceControl,
                           left: DeviceControl, right: DeviceControl) -> [String] {
        let vertical = pair(hints[up]?.first, hints[down]?.first, ("↑", "↓"))
        let sideways = pair(hints[left]?.first, hints[right]?.first, ("←", "→"))
        // In a list all four step through it.
        if let vertical, let sideways, vertical.dropFirst(2) == sideways.dropFirst(2), vertical.hasPrefix("↑↓") { return ["↑↓←→" + vertical.dropFirst(2)] }
        return [vertical, sideways].compactMap { $0 }
    }

    static func caption(_ action: GestureAction, scope: GestureScope, profile: ApplicationProfile) -> String {
        switch action {
        case .contextDial, .sessions:
            if [.sessions, .models, .efforts, .command].contains(scope), action == .contextDial { return confirmation(scope) }
            if profile.alwaysScrolls { return L10n.tr("下一标签页", "Next tab") }
            if profile.isMessaging { return L10n.tr("切换聊天", "Switch chat") }
            return L10n.tr("选会话", "Chats")
        case .models:
            if profile.alwaysScrolls { return L10n.tr("地址栏", "Address bar") }
            if profile.isMessaging { return L10n.tr("搜索聊天", "Search chats") }
            return L10n.tr("模型 / 强度", "Model / effort")
        case .contextConfirm, .confirmCandidate: return confirmation(scope)
        case .contextEscape: return scope == .editing ? L10n.tr("退格", "Backspace") : scope == .command ? L10n.tr("停止", "Stop") : L10n.tr("返回", "Back")
        case .contextLeft:
            if scope == .editing { return L10n.tr("光标左移", "Caret left") }
            if [.sessions, .models, .efforts, .command].contains(scope) { return L10n.tr("上一个", "Previous") }
            return L10n.tr("下滚屏", "Scroll down")
        case .contextRight:
            if scope == .editing { return L10n.tr("光标右移", "Caret right") }
            if [.sessions, .models, .efforts, .command].contains(scope) { return L10n.tr("下一个", "Next") }
            return L10n.tr("上滚屏", "Scroll up")
        case .deleteBackward: return L10n.tr("退格", "Backspace")
        case .enter: return "Enter"
        case .escape, .cancelPicker, .cancelApplication: return scope == .command ? L10n.tr("停止", "Stop") : L10n.tr("返回", "Back")
        case .dictation: return L10n.tr("听写", "Dictate")
        case .command: return L10n.tr("命令", "Command")
        case .pointerClick: return L10n.tr("鼠标左键", "Click")
        case .cursorLeft: return L10n.tr("光标左移", "Caret left")
        case .cursorRight: return L10n.tr("光标右移", "Caret right")
        case .scrollUp: return L10n.tr("上滚屏", "Scroll up")
        case .scrollDown: return L10n.tr("下滚屏", "Scroll down")
        case .previousCandidate, .previousApplication: return L10n.tr("上一个", "Previous")
        case .nextCandidate, .nextApplication: return L10n.tr("下一个", "Next")
        case .switchApplications: return L10n.tr("切应用", "Switch apps")
        case .confirmApplication: return L10n.tr("确认切换", "Switch")
        case .showControls: return L10n.tr("按键一览", "Controls")
        case .toggleOverlay: return L10n.tr("显示 / 隐藏面板", "Overlay")
        case .openSettings: return L10n.tr("设置", "Settings")
        default: return action.label
        }
    }

    private static func confirmation(_ scope: GestureScope) -> String {
        switch scope {
        case .sessions: return L10n.tr("确认会话", "Open chat")
        case .models: return L10n.tr("确认模型", "Use model")
        case .efforts: return L10n.tr("确认强度", "Use effort")
        case .command: return L10n.tr("确认", "Confirm")
        default: return L10n.tr("确认 / Enter", "Confirm / Enter")
        }
    }

    static func nextStep(_ snapshot: HUDSnapshot) -> String {
        if snapshot.captureOnly { return L10n.tr("仅采集输入", "Input capture only") }
        if !snapshot.connected && !snapshot.demo { return L10n.tr("连接设备开始", "Connect to begin") }
        let controls = snapshot.deviceTemplate.template.controls
        let preferred: [GestureAction] = [.confirmCandidate, .confirmApplication, .contextConfirm]
        let desired = snapshot.scope == .reading || snapshot.scope == .editing ? [GestureAction.contextDial] : preferred
        for action in desired {
            for item in controls {
                if let hint = snapshot.controlHints[item.control]?.first(where: { $0.action == action }) {
                    let title = shortName(item.control, template: snapshot.deviceTemplate)
                    return "\(title) · \(hint.title)"
                }
            }
        }
        return L10n.tr("按箭头提示操作", "Follow the button guide")
    }

    static func shortName(_ control: DeviceControl, template: DeviceTemplateID) -> String {
        // On the keyboard a control is known by the combination that stands for it.
        if template == .keyboard, !KeyboardLayout.current.label(control).isEmpty { return KeyboardLayout.current.label(control) }
        if template == .dualSense {
            switch control {
            case .dial: return "□"
            case .ok: return "×"
            case .escape: return "○"
            case .voice: return "△"
            case .options: return "☰"
            case .touchpad: return L10n.tr("触摸板", "Touchpad")
            case .leftStickPress: return "L3"
            case .rightStickPress: return "R3"
            default: break
            }
        }
        if template == .xiaomiRemote && control == .dial { return L10n.tr("中央键", "Center") }
        return template.template.controls.first { $0.control == control }?.title ?? control.label
    }
}
