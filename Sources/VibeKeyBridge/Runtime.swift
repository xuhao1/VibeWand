import AppKit
import ApplicationServices
import AU05Device

@MainActor
final class BridgeRuntime {
    let adapter = AccessibilityAdapter()
    let templates: DeviceTemplateStore
    private let suppliedSource: Bool
    private let sourceFactory: (HIDDeviceProfile?, DeviceTemplateID) throws -> any HIDEventSource
    var onInternalAction: ((GestureAction) -> Void)?
    var sendPointerMotion: ((ControllerPointerMotion) -> Void)? // Test seam.
    var sendPointerClick: (() -> Void)? // Test seam.
    private var device: any HIDEventSource
    let dictation = FnDictation()
    private(set) var configuration = GestureConfiguration()
    private var gestureEngine = GestureEngine()
    private var gestureTimer: Timer?
    let applicationSwitcher = ApplicationSwitcher()
    private var demoSwitcherActive = false
    private var demoApplicationIndex = 0
    private struct GestureOwner { var identity: TargetIdentity?; var pid: pid_t? }
    private var gestureOwners: [UInt64: GestureOwner] = [:]
    private var dictationHolders: Set<DeviceControl> = []
    private var hardwarePressed: Set<DeviceControl> = []
    private var hardwarePulseTimers: [DeviceControl: Timer] = [:]
    private var inputStarted = false
    private(set) var deviceName = "AU05"
    private var deviceStatus = L10n.tr("等待设备", "Waiting for device")
    var captureOnly = false {
        didSet {
            if captureOnly { demoTimer?.invalidate(); demoTimer = nil }
            snapshot.captureOnly = captureOnly; cancelAll()
            snapshot.action = captureOnly ? L10n.tr("只显示物理事件，不发送操作", "Physical events only; no actions sent") : L10n.tr("等待设备操作", "Waiting for device input")
            refresh(); onSettingsChanged?()
        }
    }
    private(set) var snapshot = HUDSnapshot()
    private var interaction = InteractionState()
    private var pulseTimers: [DeviceControl: Timer] = [:]
    private var pollTimer: Timer?
    private var demoTimer: Timer?
    var onSnapshot: ((HUDSnapshot) -> Void)?
    var onSettingsChanged: (() -> Void)?
    private var demoPicker: InteractionMode?
    private var demoChoice = 0
    private var demoActive = 0
    private var demoModel = 0
    private var demoEffort = 1
    private var demoDrafts = [L10n.tr("请帮我检查这个插件。", "Please review this plugin."), "", ""]
    private var demoCarets = [10, 0, 0]
    private var demoSessions: [String] { [L10n.tr("VibeWand 交互设计", "VibeWand interaction design"), L10n.tr("修复登录问题", "Fix sign-in issue"), L10n.tr("整理实验记录", "Organize research notes")] }
    private var inputReady = false
    private var eventCounts: [String: Int] = [:]
    private var lastDeviceEvent = "none"
    private var recentActions: [String] = []
    private var lastDispatch: [String: Any] = [:]
    private var generation: UInt = 0
    private var languageObserver: NSObjectProtocol?
    private var presentationScope = GestureScope.reading

    init(source: (any HIDEventSource)? = nil, templates: DeviceTemplateStore = DeviceTemplateStore(),
         sourceFactory: ((HIDDeviceProfile?, DeviceTemplateID) throws -> any HIDEventSource)? = nil) {
        self.templates = templates
        suppliedSource = source != nil
        self.sourceFactory = sourceFactory ?? Self.makeSource
        device = source ?? AU05HIDClient()
        configuration = templates.configuration()
        snapshot.deviceTemplate = templates.selectedID
        deviceName = templates.profile()?.name ?? templates.selectedTemplate.title
        languageObserver = NotificationCenter.default.addObserver(forName: L10n.languageDidChange,
            object: L10n.shared, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLanguage() }
            }
    }

    deinit {
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
    }

    private func refreshLanguage() {
        if device is GameControllerInputSource {
            deviceName = templates.selectedTemplate.title
        } else if templates.profile() == nil { deviceName = templates.selectedTemplate.title }
        if templates.readiness() == .needsProfile {
            deviceStatus = L10n.tr("请先导入实测 HID 配置", "Import a verified HID profile first")
        } else if device is GameControllerInputSource {
            deviceStatus = controllerConnectionSummary(device.connection)
        } else { deviceStatus = device.connection.title }
        snapshot.action = captureOnly
            ? L10n.tr("只显示物理事件，不发送操作", "Physical events only; no actions sent")
            : demo ? L10n.tr("演示数据，操作不会发给目标应用", "Demo data; no actions sent to apps")
            : L10n.tr("等待设备操作", "Waiting for device input")
        refresh()
    }

    var demo: Bool {
        get { snapshot.demo }
        set {
            cancelAll()
            demoTimer?.invalidate(); demoTimer = nil
            snapshot.demo = newValue
            interaction = InteractionState()
            demoPicker = nil
            snapshot.action = newValue ? L10n.tr("演示数据，操作不会发给目标应用", "Demo data; no actions sent to apps") : L10n.tr("等待设备事件", "Waiting for device events")
            refresh()
            onSettingsChanged?()
        }
    }

    func start(demo: Bool) {
        configuration = templates.configuration()
        if !suppliedSource {
            do { try replaceDevice(profile: templates.profile(), template: templates.selectedID) }
            catch { device = UnconfiguredHIDSource(template: templates.selectedTemplate) }
        }
        applicationSwitcher.onChange = { [weak self] in self?.refresh() }
        let gestureTimer = Timer(timeInterval: 0.015, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceGestures() }
        }
        self.gestureTimer = gestureTimer; RunLoop.main.add(gestureTimer, forMode: .common)
        snapshot.demo = demo
        inputStarted = true
        connectDevice()
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        inputStarted = false
        device.stop(); cancelAll(); pollTimer?.invalidate(); demoTimer?.invalidate(); gestureTimer?.invalidate(); gestureTimer = nil
    }

    static func makeSource(profile: HIDDeviceProfile?, template: DeviceTemplateID) throws -> any HIDEventSource {
        if let profile { return try GenericHIDClient(profile: profile) }
        switch template {
        case .vibeKey: return AU05HIDClient()
        case .dualSense: return GameControllerInputSource()
        case .xiaomiRemote: return UnconfiguredHIDSource(template: template.template)
        }
    }

    var connectionSummary: String {
        device is GameControllerInputSource ? controllerConnectionSummary(device.connection) : deviceStatus
    }

    private func controllerConnectionSummary(_ state: AU05Connection) -> String {
        switch state {
        case .ready: return L10n.tr("手柄已连接 · USB / 蓝牙自动识别", "Controller connected · automatic USB / Bluetooth input")
        case .waiting:
            if let controller = device as? GameControllerInputSource,
               controller.diagnostics.availableControllers > 0, controller.diagnostics.supportedControllers == 0 {
                return L10n.tr("设备已发现，但系统未提供标准手柄输入 · 可尝试 USB 或高级 HID 接入", "A device was found without a standard gamepad profile · try USB or advanced HID input")
            }
            return L10n.tr("未检测到手柄 · 请连接 USB 或在 macOS 蓝牙中完成连接", "No controller detected · connect USB or connect in macOS Bluetooth settings")
        default: return state.title
        }
    }

    private func replaceDevice(profile: HIDDeviceProfile?, template: DeviceTemplateID) throws {
        let next = try sourceFactory(profile, template)
        device.onEvent = nil; device.onConnection = nil
        (device as? any ControllerPointerEventSource)?.onPointerMotion = nil
        device.stop(); cancelAll(); inputReady = false; device = next
        deviceName = profile?.name ?? template.template.title
        deviceStatus = L10n.tr("等待设备", "Waiting for device")
        snapshot.deviceTemplate = template
        snapshot.rotation = 0
        if inputStarted { connectDevice() }
    }
    func configureDevice(profile: HIDDeviceProfile?) throws {
        try profile?.validate()
        try templates.setProfile(profile, for: templates.selectedID)
        try replaceDevice(profile: profile, template: templates.selectedID)
        onSettingsChanged?()
    }
    func selectTemplate(_ id: DeviceTemplateID) throws {
        let profile = templates.profile(for: id)
        try profile?.validate()
        let configuration = try templates.select(id, currentConfiguration: self.configuration)
        self.configuration = configuration
        try replaceDevice(profile: profile, template: id)
        refresh()
        onSettingsChanged?()
    }
    func reconnectDevice() { device.stop(); cancelAll(); if inputStarted { connectDevice() } }
    func updateConfiguration(_ value: GestureConfiguration) throws {
        try value.validate(); try templates.updateConfiguration(value)
        cancelAll(); configuration = value; refresh(); onSettingsChanged?()
    }
    func openApplicationSwitcher() {
        dispatch(GestureSignal(control: .dial, kind: .double, action: .switchApplications, phase: .pulse, token: 0))
    }
    func cancelApplicationSwitcher() { applicationSwitcher.cancel(); demoSwitcherActive = false; refresh() }
    func resetConfiguration() {
        if let value = try? templates.resetConfiguration() { cancelAll(); configuration = value; refresh(); onSettingsChanged?() }
    }
    private func connectDevice() {
        device.onConnection = { [weak self] state in
            guard let self else { return }
            self.inputReady = state == .ready
            if self.device is GameControllerInputSource {
                self.deviceName = self.templates.selectedTemplate.title
                self.deviceStatus = self.controllerConnectionSummary(state)
            } else { self.deviceStatus = state.title }
            if state != .ready { self.cancelAll(); self.snapshot.action = self.deviceStatus }
            else { self.snapshot.action = self.captureOnly ? L10n.tr("只显示物理事件，不发送操作", "Physical events only; no actions sent") : L10n.tr("直连已就绪，等待操作", "Connected; ready for input") }
            self.refresh()
        }
        device.onEvent = { [weak self] event in self?.receiveHardware(event) }
        (device as? any ControllerPointerEventSource)?.onPointerMotion = { [weak self, weak source = device] motion in
            guard let self, let source, self.device === source else { return }
            self.receivePointerMotion(motion)
        }
        device.start()
    }
    func receivePointerMotion(_ motion: ControllerPointerMotion) {
        guard inputStarted, inputReady, templates.selectedID == .dualSense,
              motion.dx.isFinite, motion.dy.isFinite else { return }
        snapshot.action = L10n.tr("触摸板 · 移动光标", "Touchpad · move pointer")
        if !captureOnly && !demo && adapter.trusted {
            if let sendPointerMotion { sendPointerMotion(motion) }
            else { SystemPointer.move(relative: motion) }
        }
        emit()
    }
    private func receiveHardware(_ event: AU05Event) {
        eventCounts["\(event.control.rawValue).\(event.phase.rawValue)", default: 0] += 1
        lastDeviceEvent = "\(event.control.rawValue).\(event.phase.rawValue)"
        guard let visual = DeviceControl(rawValue: event.control.rawValue) else { return }
        switch event.phase {
        case .down: hardwarePressed.insert(visual)
        case .up, .cancel: hardwarePressed.remove(visual)
        case .pulse:
            hardwarePressed.insert(visual)
            hardwarePulseTimers.removeValue(forKey: visual)?.invalidate()
            if !visual.isStickDirection {
                hardwarePulseTimers[visual] = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.hardwarePressed.remove(visual); self?.emit() }
                }
            }
        }
        if captureOnly {
            snapshot.mode = L10n.tr("采集物理事件", "Capture physical input")
            snapshot.action = "\(visual.label) · \(event.phase.rawValue)"
            if visual == .left || visual == .right { snapshot.rotation += visual == .left ? -1 : 1 }
            emit(); return
        }
        if let phase = InputPhase(rawValue: event.phase.rawValue) { handle(visual, phase: phase) }
        emit()
    }

    func handle(_ control: DeviceControl, phase: InputPhase) {
        guard !captureOnly else { return }
        let observation = demo ? demoObservation() : adapter.observe()
        let signals = gestureEngine.receive(control, phase: phase, now: ProcessInfo.processInfo.systemUptime,
            scope: currentScope(observation.context), config: configuration,
            allowHeldRotation: templates.selectedID == .vibeKey)
        if phase == .down, let token = gestureEngine.token(for: control) {
            gestureOwners[token] = GestureOwner(identity: observation.identity,
                pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        for signal in signals where gestureOwners[signal.token] == nil &&
            (signal.kind == .rotate || signal.kind == .heldLeft || signal.kind == .heldRight ||
             (phase == .pulse && signal.kind == .single && signal.control == control)) {
            gestureOwners[signal.token] = GestureOwner(identity: observation.identity,
                pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        if control == .left || control == .right, phase == .pulse { snapshot.rotation += control == .left ? -1 : 1 }
        if phase == .pulse {
            pulseTimers.removeValue(forKey: control)?.invalidate()
            pulseTimers[control] = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.pulseTimers.removeValue(forKey: control); self?.emit() }
            }
        }
        signals.forEach(dispatch)
        if phase == .cancel && dictationHolders.isEmpty { dictation.cancel() }
        if gestureOwners.count > 128 {
            let oldest = gestureOwners.keys.sorted().prefix(gestureOwners.count - 128)
            for token in oldest { gestureOwners.removeValue(forKey: token) }
        }
        emit()
    }
    func advanceGestures(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !captureOnly else { return }
        gestureEngine.tick(now: now).forEach(dispatch)
    }
    private var switcherActive: Bool { demo ? demoSwitcherActive : applicationSwitcher.active }
    private func currentScope(_ context: InteractionContext) -> GestureScope {
        if switcherActive { return .applications }
        if context.applicationProfile.alwaysScrolls && context.picker == nil { return .reading }
        switch context.picker {
        case .sessions: return .sessions
        case .models: return .models
        case .efforts: return .efforts
        default: return context.editingDraft ? .editing : .reading
        }
    }
    private func dispatch(_ signal: GestureSignal) {
        guard !captureOnly else { return }
        if signal.action == .pointerClick {
            guard signal.phase == .pulse || signal.phase == .down else { return }
            if !demo && adapter.trusted {
                if let sendPointerClick { sendPointerClick() } else { SystemPointer.clickAtCursor() }
            }
            snapshot.action = signal.action.label
            record(signal, action: signal.action.label); emit(); return
        }
        if [.toggleOverlay, .openSettings, .toggleGuide].contains(signal.action) {
            guard signal.phase == .pulse || signal.phase == .down else { return }
            snapshot.action = signal.action.label
            onInternalAction?(signal.action); record(signal, action: signal.action.label); emit(); return
        }
        if signal.action == .dictation {
            if signal.phase == .down { dictationHolders.insert(signal.control) }
            else if signal.phase == .up || signal.phase == .cancel { dictationHolders.remove(signal.control) }
            if !demo && !captureOnly && adapter.trusted {
                if signal.phase == .pulse { dictation.pulse() }
                else { dictation.setHeld(!dictationHolders.isEmpty) }
            }
            snapshot.action = signal.phase == .down ? L10n.tr("Fn 按住 · 豆包听写", "Fn held · dictation") : L10n.tr("Fn 松开 · 等待听写文字", "Fn released · waiting for dictated text")
            if demo && signal.phase == .up { insertDemoVoice() }
            emit(); return
        }
        if signal.kind == .hold && signal.action == .switchApplications && (signal.phase == .up || signal.phase == .cancel) {
            if demo { demoSwitcherActive = false }
            else if signal.phase == .up { applicationSwitcher.confirm() } else { applicationSwitcher.cancel() }
            refresh(); return
        }
        guard signal.phase == .pulse || signal.phase == .down else { return }
        switch signal.action {
        case .switchApplications, .previousApplication, .nextApplication, .confirmApplication, .cancelApplication:
            guard demo || adapter.trusted else { snapshot.status = L10n.tr("请先开启辅助功能权限", "Enable Accessibility permission first"); emit(); return }
            if demo {
                switch signal.action {
                case .switchApplications: demoSwitcherActive = true; demoApplicationIndex = 0
                case .previousApplication: demoApplicationIndex = max(0, demoApplicationIndex - 1)
                case .nextApplication: demoApplicationIndex = min(2, demoApplicationIndex + 1)
                default: demoSwitcherActive = false
                }
            } else {
                switch signal.action {
                case .switchApplications: dictation.cancel(); applicationSwitcher.begin()
                case .previousApplication: applicationSwitcher.move(-1)
                case .nextApplication: applicationSwitcher.move(1)
                case .confirmApplication: applicationSwitcher.confirm()
                case .cancelApplication: applicationSwitcher.cancel()
                default: break
                }
            }
            snapshot.action = signal.action.label; record(signal, action: signal.action.label); refresh(); return
        case .none: return
        default: break
        }
        if demo { execute(signal, observation: demoObservation()); return }
        let owner = gestureOwners[signal.token]
        let requestGeneration = generation, started = ProcessInfo.processInfo.systemUptime
        adapter.requestRefresh { [weak self] observation in
            guard let self, !self.demo, !self.captureOnly, self.generation == requestGeneration,
                  ProcessInfo.processInfo.systemUptime - started < 0.5,
                  observation.context.targetAvailable,
                  let original = owner?.identity, let current = observation.identity,
                  original.pid == current.pid, original.windowHash == current.windowHash else { return }
            if signal.kind != .rotate && signal.kind != .heldLeft && signal.kind != .heldRight {
                guard original == current else { return }
            }
            var currentSignal = signal
            if signal.kind == .rotate || signal.kind == .heldLeft || signal.kind == .heldRight {
                let control: DeviceControl = signal.kind == .rotate ? signal.control : .dial
                currentSignal.action = self.configuration.action(self.currentScope(observation.context), control, signal.kind)
            }
            if [.dictation, .switchApplications, .previousApplication, .nextApplication, .confirmApplication, .cancelApplication].contains(currentSignal.action) {
                self.dispatch(currentSignal)
            } else { self.execute(currentSignal, observation: observation) }
        }
    }
    private func execute(_ signal: GestureSignal, observation: TargetObservation) {
        let effect: BridgeEffect
        switch signal.action {
        case .contextDial: effect = reduce(state: &interaction, control: .dial, context: observation.context)
        case .contextLeft: effect = reduce(state: &interaction, control: .left, context: observation.context)
        case .contextRight: effect = reduce(state: &interaction, control: .right, context: observation.context)
        case .contextConfirm: effect = reduce(state: &interaction, control: .ok, context: observation.context)
        case .contextEscape: effect = reduce(state: &interaction, control: .escape, context: observation.context)
        case .sessions: effect = .openSessions
        case .models: effect = .openModels
        case .deleteBackward: effect = .deleteBackward
        case .enter: effect = .sendReturn
        case .escape: effect = .sendEscape
        case .cursorLeft: effect = .moveCursor(-1)
        case .cursorRight: effect = .moveCursor(1)
        case .scrollUp: effect = .scroll(-1)
        case .scrollDown: effect = .scroll(1)
        case .previousCandidate: effect = .moveCandidate(-1)
        case .nextCandidate: effect = .moveCandidate(1)
        case .confirmCandidate: effect = .confirmCandidate
        case .cancelPicker: effect = .cancelPicker
        default: effect = .none
        }
        let title = observation.context.applicationProfile.title(for: effect)
        snapshot.action = title; record(signal, action: title)
        if demo { applyDemo(effect) } else { snapshot.status = adapter.perform(effect, observation: observation) }
        lastDispatch = ["action": title, "result": snapshot.status,
            "picker": observation.context.picker?.rawValue ?? "none", "candidates": observation.candidates.count,
            "scrollPoint": observation.scrollPoint != nil, "slider": observation.adjustmentControl != nil]
        emit()
        if effect == .openModels || effect == .openSessions || effect == .confirmCandidate || effect == .cancelPicker {
            Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }
    }
    private func record(_ signal: GestureSignal, action: String) {
        recentActions.append("\(signal.control.rawValue).\(signal.kind.rawValue) · \(action)")
        if recentActions.count > 20 { recentActions.removeFirst(recentActions.count - 20) }
    }

    func playDemo() {
        demo = true
        demoTimer?.invalidate()
        let sequence: [DeviceControl] = [.dial, .right, .dial, .voice, .left, .left, .escape, .settings, .right, .dial, .right, .dial, .ok]
        var step = 0
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.demo, step < sequence.count else { timer.invalidate(); return }
                let control = sequence[step]; step += 1
                if control == .voice { self.insertDemoVoice(); self.handle(.voice, phase: .pulse) }
                else { self.handle(control, phase: .pulse) }
            }
        }
    }

    func exportSnapshot(_ url: URL) throws {
        // Diagnostic summary intentionally contains no chat text or credentials.
        var value: [String: Any] = ["mode":snapshot.mode,"action":snapshot.action,"status":snapshot.status,"demo":snapshot.demo,"inputReady":inputReady,"accessibility":adapter.trusted,"device":deviceName,"deviceStatus":deviceStatus,"captureOnly":captureOnly,"eventCounts":eventCounts,"lastDeviceEvent":lastDeviceEvent,"recentActions":recentActions,"lastDispatch":lastDispatch,"appSwitcher":switcherActive,"pressed":snapshot.pressed.map(\.rawValue)]
        value["dockVisible"] = NSApp?.activationPolicy() == .regular
        value["deviceTemplate"] = snapshot.deviceTemplate.rawValue
        if let controller = device as? GameControllerInputSource {
            value["inputBackend"] = "GameController"
            value["controllerMetrics"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.diagnostics))
        }
        if let au05 = device as? AU05HIDClient {
            value["hidMetrics"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(au05.diagnostics))
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func refresh() {
        if !demo && !captureOnly { adapter.requestRefresh { [weak self] _ in self?.updateObservedState() } }
        updateObservedState()
    }

    private func updateObservedState() {
        deviceStatus = connectionSummary
        let context: InteractionContext
        if captureOnly {
            context = InteractionContext(targetAvailable: false, editorFocused: false, modalOpen: false, compositionActive: false, picker: nil)
            snapshot.target = deviceName
        } else if demo {
            context = demoObservation().context
            snapshot.target = demoSessions[demoActive]
            if demoPicker == .sessions { snapshot.status = L10n.tr("候选：\(demoSessions[demoChoice])", "Selection: \(demoSessions[demoChoice])") }
            else if demoPicker == .models { snapshot.status = L10n.tr("候选模型：\(demoModel == 0 ? "A" : "B")", "Model: \(demoModel == 0 ? "A" : "B")") }
            else if demoPicker == .efforts { snapshot.status = L10n.tr("候选强度：\(["低", "中", "高"][demoEffort])", "Effort: \(["Low", "Medium", "High"][demoEffort])") }
            else { snapshot.status = L10n.tr("光标 \(demoCarets[demoActive]) / \(demoDrafts[demoActive].count) · 演示", "Cursor \(demoCarets[demoActive]) / \(demoDrafts[demoActive].count) · Demo") }
        } else {
            let observation = adapter.observe()
            context = observation.context
            snapshot.target = adapter.targetDisplayName
            snapshot.status = observation.status


        }
        presentationScope = currentScope(context)
        if let picker = context.picker { interaction.mode = picker }
        else { interaction.mode = !context.targetAvailable ? .unavailable : context.editingDraft ? .editing : .browse }
        snapshot.mode = interaction.mode.title
        if captureOnly { snapshot.mode = L10n.tr("采集物理事件", "Capture physical input"); snapshot.status = deviceStatus }
        else if !inputReady { snapshot.status = deviceStatus }
        snapshot.connected = inputReady
        if switcherActive {
            snapshot.mode = L10n.tr("切换应用", "Switch apps"); snapshot.target = "macOS"
            snapshot.status = demo ? L10n.tr("演示应用 \(demoApplicationIndex + 1) / 3", "Demo app \(demoApplicationIndex + 1) / 3") : L10n.tr("旋转选应用 · 按旋钮确认 · ESC 取消", "Turn to choose app · press to confirm · ESC to cancel")
        }
        emit()
    }

    private func cancelAll() {
        generation &+= 1
        adapter.reset()
        _ = gestureEngine.reset(); gestureOwners.removeAll(); dictationHolders.removeAll()
        dictation.cancel(); applicationSwitcher.cancel(); demoSwitcherActive = false; hardwarePressed.removeAll()
        hardwarePulseTimers.values.forEach { $0.invalidate() }; hardwarePulseTimers.removeAll()
        pulseTimers.values.forEach { $0.invalidate() }; pulseTimers.removeAll()
        snapshot.pressed.removeAll()
    }
    private func emit() {
        snapshot.deviceTemplate = templates.selectedID
        snapshot.controlActions = Dictionary(uniqueKeysWithValues: templates.selectedTemplate.controls.map { item in
            let held = item.gestures.contains(.hold) ? configuration.action(presentationScope, item.control, .hold) : .none
            let action = held != .none ? held : item.gestures.lazy.map { self.configuration.action(self.presentationScope, item.control, $0) }.first { $0 != .none } ?? .none
            return (item.control, action.label)
        })
        if inputStarted || demo {
            snapshot.pressed = demo && !captureOnly ? hardwarePressed.union(gestureEngine.held).union(pulseTimers.keys) : hardwarePressed
        }
        onSnapshot?(snapshot)
    }
    private func demoObservation() -> TargetObservation {
        var observation = TargetObservation()
        observation.context = InteractionContext(targetAvailable: true, editorFocused: demoPicker == nil, modalOpen: demoPicker != nil, compositionActive: false, picker: demoPicker, hasDraftText: !demoDrafts[demoActive].isEmpty)
        observation.status = L10n.tr("演示", "Demo")
        return observation
    }
    private func applyDemo(_ effect: BridgeEffect) {
        switch effect {
        case .openSessions: demoPicker = .sessions; demoChoice = demoActive
        case .openModels: demoPicker = .models
        case .moveCandidate(let n):
            if demoPicker == .sessions { demoChoice = min(2,max(0,demoChoice+n)) }
            else if demoPicker == .models { demoModel = min(1,max(0,demoModel+n)) }
            else if demoPicker == .efforts { demoEffort = min(2,max(0,demoEffort+n)) }
        case .confirmCandidate:
            if demoPicker == .sessions { demoActive = demoChoice; demoPicker = nil }
            else if demoPicker == .models { demoPicker = .efforts }
            else { demoPicker = nil }
        case .cancelPicker, .sendEscape: demoPicker = nil
        case .moveCursor(let n): demoCarets[demoActive] = min(demoDrafts[demoActive].count,max(0,demoCarets[demoActive]+n))
        case .deleteBackward:
            var characters = Array(demoDrafts[demoActive]); let position = demoCarets[demoActive]
            if position > 0 { characters.remove(at: position-1); demoDrafts[demoActive] = String(characters); demoCarets[demoActive] -= 1 }
        case .sendReturn: demoDrafts[demoActive] = ""; demoCarets[demoActive] = 0
        default: break
        }
        refresh()
    }
    private func insertDemoVoice() {
        guard demoPicker == nil else { return }
        var characters = Array(demoDrafts[demoActive]); let phrase = Array(L10n.tr("请保留语音听写。", "Please keep voice dictation."))
        characters.insert(contentsOf: phrase, at: demoCarets[demoActive]); demoCarets[demoActive] += phrase.count
        demoDrafts[demoActive] = String(characters)
        refresh()
    }
}
