import Foundation
import AU05Device

/// A logical layout is deliberately separate from a verified HID interface.
/// Selecting a layout must never invent a device identifier or claim a live connection.
enum DeviceTemplateID: String, CaseIterable, Codable {
    case vibeKey, dualSense, xiaomiRemote
    /// No device at all: key combinations on the keyboard stand for the controls.
    case keyboard

    var template: DeviceTemplate { DeviceTemplate.catalog.first { $0.id == self }! }
}

struct DeviceTemplateControl {
    let control: DeviceControl
    let title: String
    let detail: String
    let symbol: String
    let gestures: [GestureKind]
    /// Normalized positions on a top-to-bottom device illustration.
    let x: Double
    let y: Double
    var id: String { control.rawValue }
}

struct DeviceTemplate {
    let id: DeviceTemplateID
    let title: String
    let subtitle: String
    let connectionNote: String
    let audioNote: String
    let controls: [DeviceTemplateControl]
    var requiresHIDProfile: Bool { id == .xiaomiRemote }

    /// Baseline overrides are part of the preset. To restore a single binding,
    /// copy its explicit baseline entry (which may be nil), rather than clearing blindly.
    var defaultConfiguration: GestureConfiguration {
        var configuration = GestureConfiguration()
        if id != .vibeKey {
            configuration.doubleClickInterval = 0.32
            configuration.longPressInterval = 0.65
        }
        if id == .dualSense {
            // One job a button. The face buttons act: ○ confirms, × goes back and □ deletes, in every scene.
            // The right shoulder talks (R1 a command, once command mode is live; R2 text) and the left one
            // switches (L1 chats, L2 apps). Sticks and the direction pad move; those defaults belong to every layout.
            // The physical input IDs stay as they were: Square=dial, Circle=escape, Cross=ok.
            configuration.set(.global, .dial, .single, .deleteBackward)
            configuration.set(.global, .dial, .double, GestureAction.none)
            configuration.set(.global, .dial, .long, .deleteBackward)
            configuration.set(.global, .escape, .single, .contextConfirm)
            configuration.set(.global, .escape, .long, GestureAction.none)
            configuration.set(.global, .ok, .single, .escape)
            configuration.set(.global, .touchpad, .single, .pointerClick)
            configuration.set(.global, .r2, .hold, .dictation)
            configuration.set(.global, .l1, .single, .contextDial)
            configuration.set(.global, .l1, .long, .models)
            // Held like ⌘Tab: a tap returns to the app before, a hold shows the row to choose from.
            configuration.set(.global, .l2, .hold, .switchApplications)
            configuration.set(.global, .options, .single, .showControls)
            for scope in [GestureScope.sessions, .models, .efforts, .applications] {
                let apps = scope == .applications
                configuration.set(scope, .escape, .single, apps ? .confirmApplication : .confirmCandidate)
                configuration.set(scope, .ok, .single, apps ? .cancelApplication : .cancelPicker)
                configuration.set(scope, .dial, .single, GestureAction.none)
                configuration.set(scope, .dial, .long, GestureAction.none)
                configuration.set(scope, .escape, .long, GestureAction.none)
                // In a list L1 steps on, the way it steps through a browser's tabs.
                configuration.set(scope, .l1, .single, apps ? .nextApplication : .nextCandidate)
                configuration.set(scope, .l1, .long, GestureAction.none)
            }
            // From an effort popover, holding L1 again continues to the model list.
            configuration.set(.efforts, .l1, .long, .models)
        }
        if id == .xiaomiRemote {
            configuration.set(.global, .dial, .single, .contextConfirm)
            configuration.set(.global, .dial, .long, .sessions)
            configuration.set(.global, .ok, .single, .contextDial)
            configuration.set(.global, .ok, .long, .models)
            for scope in [GestureScope.sessions, .models, .efforts] {
                configuration.set(scope, .dial, .long, GestureAction.none)
                configuration.set(scope, .ok, .single, .confirmCandidate)
                configuration.set(scope, .ok, .long, GestureAction.none)
            }
            configuration.set(.applications, .ok, .long, GestureAction.none)
            configuration.set(.efforts, .ok, .long, .models)
        }
        return configuration
    }

    /// Where the command key sits while command mode is live. A binding the user
    /// made themselves always wins; the remote has no spare hold-capable key by default.
    var commandBindings: [String: GestureAction] {
        switch id {
        // Holding the dial speaks a command, so the model entry moves to a long press of OK.
        case .vibeKey: return [GestureConfiguration.key(.global, .dial, .long): .command,
                               GestureConfiguration.key(.global, .ok, .long): .models]
        case .dualSense: return [GestureConfiguration.key(.global, .r1, .hold): .command]
        // The keyboard has a command key of its own: a right-hand modifier held alone.
        case .xiaomiRemote, .keyboard: return [:]
        }
    }

    private static let buttonGestures: [GestureKind] = [.single, .double, .long, .hold]
    private static func button(_ control: DeviceControl, _ title: String, _ detail: String,
                               _ symbol: String, _ x: Double, _ y: Double,
                               heldRotation: Bool = false) -> DeviceTemplateControl {
        DeviceTemplateControl(control: control, title: title, detail: detail, symbol: symbol,
            gestures: buttonGestures + (heldRotation ? [.heldLeft, .heldRight] : []), x: x, y: y)
    }
    private static func direction(_ control: DeviceControl, _ title: String, _ x: Double,
                                  _ y: Double) -> DeviceTemplateControl {
        DeviceTemplateControl(control: control, title: title,
            detail: L10n.tr("阅读时滚屏 · 编辑时移动光标 · 选择器中切换候选", "Scroll when reading · move cursor when editing · navigate pickers"),
            symbol: control == .left ? "arrow.left" : "arrow.right", gestures: [.rotate], x: x, y: y)
    }

    private static func unassigned(_ control: DeviceControl, _ symbol: String,
                                   _ x: Double, _ y: Double) -> DeviceTemplateControl {
        button(control, control.label,
               L10n.tr("默认未分配，可按自己的习惯设置。", "Unassigned by default. Make this button your own."),
               symbol, x, y)
    }
    /// A controller button. Besides the clicks and the hold it can be a step: at once on the way down, repeating while held.
    private static func pad(_ control: DeviceControl, _ title: String, _ detail: String,
                            _ symbol: String, _ x: Double, _ y: Double) -> DeviceTemplateControl {
        DeviceTemplateControl(control: control, title: title, detail: detail, symbol: symbol,
                              gestures: buttonGestures + [.rotate], x: x, y: y)
    }
    private static func pad(unassigned control: DeviceControl, _ symbol: String, _ x: Double, _ y: Double) -> DeviceTemplateControl {
        pad(control, control.label, L10n.tr("默认未分配，可按自己的习惯设置。", "Unassigned by default. Make this button your own."), symbol, x, y)
    }
    /// A direction-pad button is a step by default.
    private static func arrow(_ control: DeviceControl, _ symbol: String, _ x: Double, _ y: Double) -> DeviceTemplateControl {
        let vertical = control.direction == .up || control.direction == .down
        return DeviceTemplateControl(control: control, title: control.label,
            detail: vertical
                ? L10n.tr("按一下滚屏 · 列表里上一个 / 下一个 · 按住连续移动", "Press to scroll or move through a list · hold to keep going")
                : L10n.tr("编辑时移动光标 · 列表里上一个 / 下一个 · 按住连续移动", "Press to move the caret when editing or through a list · hold to keep going"),
            symbol: symbol, gestures: [.rotate] + buttonGestures, x: x, y: y)
    }

    private static func stick(_ control: DeviceControl, _ symbol: String,
                              _ x: Double, _ y: Double) -> DeviceTemplateControl {
        let vertical = [.leftStickUp, .leftStickDown, .rightStickUp, .rightStickDown].contains(control)
        return DeviceTemplateControl(control: control, title: control.label,
            detail: vertical
                ? L10n.tr("拨动滚屏 · 列表里上一个 / 下一个 · 持续拨住连续移动，回中停止", "Tilt to scroll or move through a list · keep tilted to repeat; center to stop")
                : L10n.tr("编辑时移动光标 · 列表里上一个 / 下一个 · 持续拨住连续移动，回中停止", "Tilt to move the caret when editing or through a list · keep tilted to repeat; center to stop"),
            symbol: symbol, gestures: [.rotate], x: x, y: y)
    }

    static var catalog: [DeviceTemplate] { [
        DeviceTemplate(id: .vibeKey, title: "VibeKey", subtitle: L10n.tr("旋钮 + 三枚按键", "Dial + three buttons"),
            connectionNote: L10n.tr("使用 AU05 接收器与内置直连协议；连接状态以实时设备反馈为准。", "Connect through the AU05 receiver using the built-in protocol. Live device feedback determines connection status."),
            audioNote: L10n.tr("按住麦克风键听写；在语音输入设置中选择输入法或内置识别。", "Hold the microphone button to dictate; choose an input method or built-in recognition in Voice input settings."),
            controls: [
                button(.dial, L10n.tr("旋钮", "Dial"), L10n.tr("单击会话 / 确认 · 双击切应用 · 长按模型", "Press for chats / confirm · double press to switch apps · long press for models"), "circle.circle", 0.50, 0.27, heldRotation: true),
                direction(.left, L10n.tr("左旋", "Turn left"), 0.18, 0.27), direction(.right, L10n.tr("右旋", "Turn right"), 0.82, 0.27),
                button(.voice, L10n.tr("麦克风键", "Microphone"), L10n.tr("按住听写，松开结束", "Hold to dictate; release to finish"), "mic.fill", 0.50, 0.55),
                button(.ok, L10n.tr("OK 键", "OK"), L10n.tr("确认 / Enter", "Confirm / Enter"), "return", 0.50, 0.72),
                button(.escape, L10n.tr("ESC 键", "ESC"), L10n.tr("删除 / 返回 · 编辑时按住连续删除", "Delete / back · hold to keep deleting while editing"), "delete.left", 0.50, 0.88)
            ]),
        DeviceTemplate(id: .dualSense, title: L10n.tr("手柄", "Controller"), subtitle: L10n.tr("右肩说话 · 左肩切换 · 面键确认删除 · 摇杆方向键移动", "Right shoulder talks · left shoulder switches · face buttons act · sticks and D-pad move"),
            connectionNote: L10n.tr("通过 USB 连接，或先在 macOS 蓝牙设置中配对。系统支持的手柄会自动识别，无需导入 HID 配置。按键支持以设备实际提供的输入为准。", "Connect over USB or pair in macOS Bluetooth settings. Supported controllers are detected automatically, without an HID profile. Available buttons depend on the device."),
            audioNote: L10n.tr("USB 麦克风以系统输入设备实际识别为准；蓝牙使用 Mac 或外接麦克风。△ 或 R2 按住听写。", "For USB microphones, check macOS input devices. With Bluetooth, use your Mac or an external microphone. Hold △ or R2 to dictate."),
            controls: [
                pad(.r1, "R1", L10n.tr("命令模式配好后：按住说一句命令", "Once command mode is set up: hold to speak a command"), "r1.button.roundedbottom.horizontal", 0.79, 0.21),
                pad(.r2, "R2", L10n.tr("按住听写：食指扣着说，拇指可以继续翻页", "Hold to dictate: the index finger holds it while the thumb keeps scrolling"), "r2.button.roundedtop.horizontal", 0.78, 0.10),
                pad(.dial, L10n.tr("□ 方形键", "□ Square"), L10n.tr("单击退格 · 按住连续删除", "Press to backspace · hold to keep deleting"), "square", 0.75, 0.38),
                pad(.ok, L10n.tr("× 交叉键", "× Cross"), L10n.tr("返回 / 停止 · 列表里取消", "Back / stop · cancel in a list"), "xmark", 0.82, 0.47),
                pad(.escape, L10n.tr("○ 圆形键", "○ Circle"), L10n.tr("确认 / Enter · 列表里确认", "Confirm / Enter · confirm in a list"), "circle", 0.89, 0.38),
                pad(.voice, L10n.tr("△ 三角键", "△ Triangle"), L10n.tr("按住听写，松开结束", "Hold to dictate; release to finish"), "triangle", 0.82, 0.29),
                pad(.l1, "L1", L10n.tr("单击会话 / 标签页 · 长按模型 / 强度 · 列表里下一个", "Press for chats / tabs · long press for models / effort · next item in a list"), "l1.button.roundedbottom.horizontal", 0.21, 0.21),
                pad(.l2, "L2", L10n.tr("按住切应用：轻按回到上一个应用；按住时左右选择，松开切换", "Hold to switch apps: a tap returns to the app before; while held choose with left / right, release to switch"), "l2.button.roundedtop.horizontal", 0.22, 0.10),
                pad(unassigned: .leftStickPress, "l.joystick.press.down", 0.37, 0.56),
                pad(unassigned: .rightStickPress, "r.joystick.press.down", 0.64, 0.56),
                stick(.leftStickUp, "arrow.up", 0.37, 0.51),
                stick(.leftStickDown, "arrow.down", 0.37, 0.61),
                stick(.leftStickLeft, "arrow.left", 0.32, 0.56),
                stick(.leftStickRight, "arrow.right", 0.42, 0.56),
                stick(.rightStickUp, "arrow.up", 0.64, 0.51),
                stick(.rightStickDown, "arrow.down", 0.64, 0.61),
                stick(.rightStickLeft, "arrow.left", 0.59, 0.56),
                stick(.rightStickRight, "arrow.right", 0.69, 0.56),
                arrow(.dpadUp, "arrow.up", 0.18, 0.29),
                arrow(.dpadDown, "arrow.down", 0.18, 0.47),
                arrow(.dpadLeft, "arrow.left", 0.11, 0.38),
                arrow(.dpadRight, "arrow.right", 0.25, 0.38),
                pad(.options, L10n.tr("☰ 选项键", "☰ Options"), L10n.tr("打开 / 关闭按键一览", "Show / hide the controls card"), "line.3.horizontal", 0.68, 0.30),
                pad(unassigned: .create, "square.and.arrow.up", 0.32, 0.30),
                pad(unassigned: .home, "house", 0.50, 0.61),
                pad(.touchpad, L10n.tr("触摸板", "Touchpad"), L10n.tr("滑动移动光标 · 按压鼠标左键", "Slide to move the pointer · press to click"), "rectangle", 0.50, 0.34),
                pad(unassigned: .mute, "mic.slash", 0.50, 0.68)
            ]),
        DeviceTemplate(id: .xiaomiRemote, title: L10n.tr("遥控器", "Remote"), subtitle: L10n.tr("方向键 + 语音 + 返回", "Direction pad + voice + back"),
            connectionNote: L10n.tr("逻辑模板已就绪；macOS 配对、HID 按键及释放事件需实测后导入配置。", "Pair with macOS and import a verified HID profile that includes button press and release events."),
            audioNote: L10n.tr("电视语音功能不等于 Mac 音频输入。语音键触发所选听写服务；使用 Mac 或外接麦克风。", "TV voice features do not guarantee Mac audio input. The voice key triggers your selected dictation service; use a Mac or external microphone."),
            controls: [
                button(.voice, L10n.tr("语音键", "Voice"), L10n.tr("按住听写，松开结束", "Hold to dictate; release to finish"), "mic.fill", 0.50, 0.16),
                button(.dial, L10n.tr("中央确认键", "Center button"), L10n.tr("单击确认 · 双击切应用 · 长按会话", "Press to confirm · double press to switch apps · long press for chats"), "circle.circle", 0.50, 0.38),
                direction(.left, L10n.tr("方向左", "Left"), 0.19, 0.38), direction(.right, L10n.tr("方向右", "Right"), 0.81, 0.38),
                button(.escape, L10n.tr("返回键", "Back"), L10n.tr("删除 / 返回 · 编辑时按住连续删除", "Delete / back · hold to keep deleting while editing"), "arrow.uturn.backward", 0.29, 0.64),
                button(.ok, L10n.tr("菜单键", "Menu"), L10n.tr("单击切换会话 / 标签页 · 长按模型 · 选择器中确认", "Press to switch chats / tabs · long press for models · confirm in pickers"), "line.3.horizontal", 0.71, 0.64),
                unassigned(.power, "power", 0.50, 0.07),
                arrow(.dpadUp, "arrow.up", 0.50, 0.29),
                arrow(.dpadDown, "arrow.down", 0.50, 0.47),
                unassigned(.home, "house", 0.50, 0.57),
                unassigned(.volumeUp, "plus", 0.35, 0.76),
                unassigned(.volumeDown, "minus", 0.65, 0.76)
            ]),
        keyboard
    ] }

    /// Each control is named by the key combination that stands for it, as the user has set it.
    private static var keyboard: DeviceTemplate {
        let layout = KeyboardLayout.current
        func name(_ control: DeviceControl, _ role: String) -> String { layout.label(control).isEmpty ? role : "\(layout.label(control))  \(role)" }
        return DeviceTemplate(id: .keyboard, title: L10n.tr("键盘", "Keyboard"), subtitle: L10n.tr("不用设备，组合键当按键", "No device: key combinations as the buttons"),
            connectionNote: L10n.tr("不需要连接任何设备。选中这个布局后，下面这些组合键由 VibeWand 接收，不再传给前台应用；需要辅助功能权限。每个键位都可以在设置里按一下来录制，自定义键盘的扩展键也行。", "Nothing to connect. While this layout is selected VibeWand takes the key combinations below and they no longer reach the app in front. Accessibility access is needed. Each one is recorded in Settings by pressing it, a custom keyboard's extra keys included."),
            audioNote: L10n.tr("按住听写的组合键说话，松开结束；使用 Mac 或外接麦克风。听写交给外置输入法时，直接按输入法自己的语音键更可靠。", "Hold the dictation combination to speak and release to finish. The Mac's or an external microphone is used. When dictation is left to an external input method, pressing that input method's own voice key is the surer way."),
            controls: [
                button(.voice, name(.voice, L10n.tr("听写", "Dictation")), L10n.tr("按住听写，松开结束", "Hold to dictate; release to finish"), "mic.fill", 0.5, 0.1),
                button(.dial, name(.dial, L10n.tr("主键", "Main")), L10n.tr("单击会话 / 确认 · 双击切应用 · 长按模型", "Press for chats / confirm · double press to switch apps · long press for models"), "circle.circle", 0.5, 0.3),
                direction(.left, name(.left, L10n.tr("向左", "Left")), 0.25, 0.5), direction(.right, name(.right, L10n.tr("向右", "Right")), 0.75, 0.5),
                button(.ok, name(.ok, L10n.tr("确认", "Confirm")), L10n.tr("确认 / Enter", "Confirm / Enter"), "return", 0.5, 0.7),
                button(.escape, name(.escape, L10n.tr("返回", "Back")), L10n.tr("删除 / 返回 · 编辑时按住连续删除", "Delete / back · hold to keep deleting while editing"), "delete.left", 0.5, 0.9)
            ])
    }
}

enum DeviceTemplateReadiness: Equatable {
    case builtIn, automatic, profileConfigured, needsProfile
    var label: String {
        switch self {
        case .builtIn: return L10n.tr("内置直连", "Built-in connection")
        case .automatic: return L10n.tr("自动识别手柄", "Automatic controller detection")
        case .profileConfigured: return L10n.tr("自定义 HID 接入", "Custom HID connection")
        case .needsProfile: return L10n.tr("待导入实测 HID 配置", "HID profile required")
        }
    }
    var hasInputConfiguration: Bool { self != .needsProfile }
}

/// Stores complete per-template gesture configurations so changing devices cannot
/// leak one device's remapping or timings into another. No credentials are stored.
final class DeviceTemplateStore {
    static let storageKey = "vibeWand.deviceTemplates.v1"
    private struct State: Codable {
        var schemaVersion = 1
        var selectedID: DeviceTemplateID = .vibeKey
        var configurations: [String: GestureConfiguration] = [:]
        var profiles: [String: HIDDeviceProfile] = [:]
        // Optional for the v1 store written before controller pointer support.
        var presetRevision: Int? = 6
    }
    private let defaults: UserDefaults
    private var state: State
    var selectedID: DeviceTemplateID { state.selectedID }
    var selectedTemplate: DeviceTemplate { selectedID.template }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(State.self, from: data), saved.schemaVersion == 1 {
            state = saved
            state.configurations = saved.configurations.filter {
                DeviceTemplateID(rawValue: $0.key) != nil && (try? $0.value.validate()) != nil
            }
            state.profiles = saved.profiles.filter {
                DeviceTemplateID(rawValue: $0.key) != nil && (try? $0.value.validate()) != nil
            }
            migratePresetDefaults()
            migrateSessionConfirmation()
            migrateEffortModelEntry()
            migrateHeldDelete()
            migrateControllerLayout()
        } else {
            state = State()
            state.presetRevision = 1
            migrateLegacyConfiguration()
            migratePresetDefaults()
            migrateSessionConfirmation()
            migrateEffortModelEntry()
            migrateHeldDelete()
            migrateControllerLayout()
        }
    }

    func configuration(for id: DeviceTemplateID? = nil) -> GestureConfiguration {
        let id = id ?? selectedID
        return state.configurations[id.rawValue] ?? id.template.defaultConfiguration
    }
    func profile(for id: DeviceTemplateID? = nil) -> HIDDeviceProfile? {
        state.profiles[(id ?? selectedID).rawValue]
    }
    func readiness(for id: DeviceTemplateID? = nil) -> DeviceTemplateReadiness {
        let id = id ?? selectedID
        if profile(for: id) != nil { return .profileConfigured }
        if id == .dualSense { return .automatic }
        return id.template.requiresHIDProfile ? .needsProfile : .builtIn
    }
    @discardableResult
    func select(_ id: DeviceTemplateID, currentConfiguration: GestureConfiguration? = nil) throws -> GestureConfiguration {
        if let currentConfiguration {
            try currentConfiguration.validate()
            state.configurations[selectedID.rawValue] = currentConfiguration
        }
        state.selectedID = id
        try persist()
        return configuration()
    }
    func updateConfiguration(_ configuration: GestureConfiguration) throws {
        try configuration.validate()
        state.configurations[selectedID.rawValue] = configuration
        try persist()
    }
    func setProfile(_ profile: HIDDeviceProfile?, for id: DeviceTemplateID) throws {
        try profile?.validate()
        state.profiles[id.rawValue] = profile
        try persist()
    }
    @discardableResult
    func resetConfiguration() throws -> GestureConfiguration {
        state.configurations.removeValue(forKey: selectedID.rawValue)
        try persist()
        return configuration()
    }

    private func migrateLegacyConfiguration() {
        if let data = defaults.data(forKey: "gestureConfiguration"),
           let saved = try? JSONDecoder().decode(GestureConfiguration.self, from: data),
           (try? saved.validate()) != nil {
            state.configurations[DeviceTemplateID.vibeKey.rawValue] = saved
        } else if let data = defaults.data(forKey: "inputMappings"),
                  let old = try? JSONDecoder().decode(InputMappings.self, from: data) {
            var configuration = GestureConfiguration()
            for input in AU05Control.allCases {
                guard let control = DeviceControl(rawValue: input.rawValue) else { continue }
                let mapped = old.resolve(input)
                guard mapped != control else { continue }
                let action = GestureAction.legacy(mapped)
                let kind: GestureKind = control == .left || control == .right ? .rotate : .single
                configuration.set(.global, control, kind, action == .dictation ? GestureAction.none : action)
                if control != .left && control != .right {
                    configuration.set(.global, control, .hold, action == .dictation ? .dictation : GestureAction.none)
                    configuration.set(.global, control, .double, GestureAction.none)
                    configuration.set(.global, control, .long, GestureAction.none)
                }
            }
            state.configurations[DeviceTemplateID.vibeKey.rawValue] = configuration
        }
        // Preserve an existing explicit custom interface on upgrade. Its name is
        // shown by the runtime; returning to AU05 clears this profile explicitly.
        if let data = defaults.data(forKey: "hidDeviceProfile"),
           let profile = try? JSONDecoder().decode(HIDDeviceProfile.self, from: data),
           (try? profile.validate()) != nil {
            state.profiles[DeviceTemplateID.vibeKey.rawValue] = profile
        }
        try? persist()
    }
    private func migratePresetDefaults() {
        guard (state.presetRevision ?? 1) < 2 else { return }
        for (id, var saved) in state.configurations {
            for scope in [GestureScope.global, .reading, .editing] {
                for control in [DeviceControl.leftStickUp, .rightStickUp, .leftStickDown, .rightStickDown] {
                    let key = GestureConfiguration.key(scope, control, .rotate)
                    let wasUp = control == .leftStickUp || control == .rightStickUp
                    if saved.overrides[key] == (wasUp ? .scrollUp : .scrollDown) {
                        saved.overrides[key] = wasUp ? .scrollDown : .scrollUp
                    }
                }
            }
            for (control, kind, old, new) in [(DeviceControl.left, GestureKind.rotate, GestureAction.scrollUp, GestureAction.scrollDown),
                                             (.right, .rotate, .scrollDown, .scrollUp),
                                             (.dial, .heldLeft, .scrollUp, .scrollDown),
                                             (.dial, .heldRight, .scrollDown, .scrollUp)] {
                let key = GestureConfiguration.key(.reading, control, kind)
                if saved.overrides[key] == old { saved.overrides[key] = new }
            }
            state.configurations[id] = saved
        }
        if var saved = state.configurations[DeviceTemplateID.dualSense.rawValue] {
            let old = GestureConfiguration()
            for (key, action) in Self.formerControllerPreset {
                let parts = key.split(separator: ".").map(String.init)
                guard let scope = GestureScope(rawValue: parts[0]),
                      let control = DeviceControl(rawValue: parts[1]),
                      let kind = GestureKind(rawValue: parts[2]) else { continue }
                // Upgrade old baseline entries, but preserve explicit remaps.
                if saved.overrides[key] == nil || saved.overrides[key] == old.action(scope, control, kind) {
                    saved.overrides[key] = action
                }
            }
            state.configurations[DeviceTemplateID.dualSense.rawValue] = saved
        }
        state.presetRevision = 2
        try? persist()
    }
    private func persist() throws {
        defaults.set(try JSONEncoder().encode(state), forKey: Self.storageKey)
    }
    /// Revision 4: the model action stays available inside an effort popover.
    private func migrateEffortModelEntry() {
        guard (state.presetRevision ?? 1) < 4 else { return }
        for (id, control) in [(DeviceTemplateID.dualSense, DeviceControl.escape), (.xiaomiRemote, .ok)] {
            guard var saved = state.configurations[id.rawValue] else { continue }
            let key = GestureConfiguration.key(.efforts, control, .long)
            if saved.overrides[key] == nil || saved.overrides[key] == GestureAction.none { saved.overrides[key] = .models }
            state.configurations[id.rawValue] = saved
        }
        state.presetRevision = 4
        try? persist()
    }
    /// Revision 5: holding the controller's delete button keeps deleting.
    private func migrateHeldDelete() {
        guard (state.presetRevision ?? 1) < 5 else { return }
        if var saved = state.configurations[DeviceTemplateID.dualSense.rawValue] {
            let key = GestureConfiguration.key(.global, .dial, .long)
            if saved.overrides[key] == nil || saved.overrides[key] == GestureAction.none { saved.overrides[key] = .deleteBackward }
            state.configurations[DeviceTemplateID.dualSense.rawValue] = saved
        }
        state.presetRevision = 5
        try? persist()
    }
    /// The controller's bindings before revision 6, to tell what a saved layout left as it came.
    static var formerControllerPreset: [String: GestureAction] {
        var former = GestureConfiguration()
        former.set(.global, .dial, .single, .deleteBackward)
        former.set(.global, .dial, .double, GestureAction.none)
        former.set(.global, .dial, .long, .deleteBackward)
        former.set(.global, .escape, .single, .contextConfirm)
        former.set(.global, .escape, .long, .models)
        former.set(.global, .ok, .single, .escape)
        former.set(.global, .ok, .double, .switchApplications)
        former.set(.global, .ok, .long, .contextDial)
        former.set(.global, .touchpad, .single, .pointerClick)
        for scope in [GestureScope.sessions, .models, .efforts, .applications] {
            let apps = scope == .applications, chats = scope == .sessions
            former.set(scope, .escape, .single, apps ? .confirmApplication : chats ? .cancelPicker : .confirmCandidate)
            former.set(scope, .ok, .single, apps ? .cancelApplication : chats ? .confirmCandidate : .cancelPicker)
            former.set(scope, .dial, .single, GestureAction.none)
            for control in [DeviceControl.dial, .ok, .escape] {
                former.set(scope, control, .double, GestureAction.none)
                former.set(scope, control, .long, GestureAction.none)
            }
        }
        former.set(.efforts, .escape, .long, .models)
        return former.overrides
    }
    /// Revision 6: R1 and R2 are buttons of their own, and the controller's layout was rearranged around them.
    /// A binding left as it came takes its new value; one the user had changed stays.
    private func migrateControllerLayout() {
        guard (state.presetRevision ?? 1) < 6 else { return }
        if var saved = state.configurations[DeviceTemplateID.dualSense.rawValue] {
            // R1 and R2 used to arrive as the two turns of a dial, one pulse a press. What they were given moves to
            // the gesture a button has for it: speaking is held now that there is a release to end it, moving
            // is a step, and anything else is a press.
            let moves: Set<GestureAction> = [.contextLeft, .contextRight, .cursorLeft, .cursorRight, .scrollUp, .scrollDown,
                                             .previousCandidate, .nextCandidate, .previousApplication, .nextApplication]
            for (turn, button) in [(DeviceControl.left, DeviceControl.r1), (.right, .r2)] {
                for scope in GestureScope.allCases {
                    guard let action = saved.overrides.removeValue(forKey: GestureConfiguration.key(scope, turn, .rotate)) else { continue }
                    let kind: GestureKind = action == .command || action == .dictation ? .hold : moves.contains(action) ? .rotate : .single
                    saved.overrides[GestureConfiguration.key(scope, button, kind)] = action
                }
            }
            let former = Self.formerControllerPreset, fresh = DeviceTemplateID.dualSense.template.defaultConfiguration.overrides
            func control(_ key: String) -> Substring { key.split(separator: ".")[1] }
            // A button that came empty and was given something by the user is left to them.
            let taken = Set(saved.overrides.keys.map(control)).subtracting(former.keys.map(control))
            for key in Set(former.keys).union(fresh.keys) where saved.overrides[key] == former[key] && !taken.contains(control(key)) {
                saved.overrides[key] = fresh[key]
            }
            state.configurations[DeviceTemplateID.dualSense.rawValue] = saved
        }
        state.presetRevision = 6
        try? persist()
    }
    private func migrateSessionConfirmation() {
        guard (state.presetRevision ?? 1) < 3 else { return }
        if var saved = state.configurations[DeviceTemplateID.dualSense.rawValue] {
            for (control, old, new) in [(DeviceControl.ok, GestureAction.cancelPicker, GestureAction.confirmCandidate),
                                       (.escape, .confirmCandidate, .cancelPicker)] {
                let key = GestureConfiguration.key(.sessions, control, .single)
                if saved.overrides[key] == nil || saved.overrides[key] == old { saved.overrides[key] = new }
            }
            state.configurations[DeviceTemplateID.dualSense.rawValue] = saved
        }
        state.presetRevision = 3
        try? persist()
    }
}

/// A pending template has no event source. In particular it must not leave the
/// AU05 source active while presenting a different device in settings.
@MainActor
final class UnconfiguredHIDSource: HIDEventSource {
    private let template: DeviceTemplate
    private(set) var connection: AU05Connection = .stopped
    var onConnection: ((AU05Connection) -> Void)?
    var onEvent: ((AU05Event) -> Void)?
    init(template: DeviceTemplate) { self.template = template }
    func start() {
        connection = .blocked(L10n.tr("\(template.title)：请先导入实测 HID 配置", "\(template.id.template.title): import a verified HID profile first"))
        onConnection?(connection)
    }
    func stop() { connection = .stopped; onConnection?(connection) }
}
