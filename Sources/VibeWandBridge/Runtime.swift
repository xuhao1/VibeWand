import AppKit
import ApplicationServices
import AU05Device
import SpeechInput

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
    /// Other layouts with a usable backend keep listening, so the first press
    /// on another device makes it current. The selected layout stays `device`.
    private var companions: [DeviceTemplateID: any HIDEventSource] = [:]
    static let autoSwitchKey = "deviceAutoSwitch"
    private(set) var followsActiveDevice = UserDefaults.standard.object(forKey: BridgeRuntime.autoSwitchKey) as? Bool ?? true
    /// Settings pins the layout being edited while its window is in front.
    var autoSwitchSuspended = false
    let dictation = FnDictation()
    let voiceInput: VoiceInputController
    /// Tests build the controller with their own settings and kernel, on this runtime's adapter and voice input.
    private let makeCommand: ((AccessibilityAdapter, VoiceInputController) -> CommandController)?
    private(set) lazy var command: CommandController = {
        let controller = makeCommand?(adapter, voiceInput) ?? {
            let own = CommandController(settings: CommandSettings(), tools: CommandTools(adapter: adapter), voice: voiceInput)
            // A controller brought by a test or the film stays silent.
            own.speech = SpeechOutput()
            return own
        }()
        controller.onChange = { [weak self] in self?.updateObservedState() }
        controller.settings.onChange = { [weak self] in self?.applyCommandSettings() }
        return controller
    }()
    /// Learns the user's words from what they change in dictated text, when they have turned that on.
    /// A scripted run brings a keeper with settings and a notebook of its own.
    private let makeVocabulary: ((VoiceInputController, CommandController) -> VocabularyKeeper)?
    private(set) lazy var vocabulary = makeVocabulary?(voiceInput, command) ?? VocabularyKeeper(voice: voiceInput, command: command)
    private let keyboard = KeyboardCommandInput()
    /// The keyboard's command key is starting a recording, whichever device is in use.
    private var keyboardSpeaking = false
    /// The button whose press opened the microphone ahead of the long hold that may make it a command.
    private var listeningPress: DeviceControl?
    /// The last dictation as it was to be written, kept so that it can be written again.
    private(set) var lastDictation = ""
    /// A command spoken on a long press lasts as long as the press does.
    private var commandHold: (control: DeviceControl, token: UInt64)?
    private(set) var dualSenseVoiceEnabled = UserDefaults.standard.bool(forKey: "dualSenseVoiceEnabled")
    func setDualSenseVoiceEnabled(_ enabled: Bool) throws {
        guard !enabled || DualSenseMicrophoneSource.supported else {
            throw NSError(domain: "VibeWand.DualSenseVoice",code: 1,
                userInfo: [NSLocalizedDescriptionKey: "当前版本未包含兼容的蓝牙麦克风组件"])
        }
        guard dualSenseVoiceEnabled != enabled else { return }
        cancelAll()
        dualSenseVoiceEnabled = enabled
        UserDefaults.standard.set(enabled,forKey: "dualSenseVoiceEnabled")
        if templates.selectedID == .dualSense { try replaceDevice(profile: templates.profile(), template: .dualSense) }
        else { dropCompanion(.dualSense); syncCompanions() }
        onSettingsChanged?()
    }
    private var dictationTarget: TargetIdentity?
    private var dictationApp: (pid: pid_t, bundleID: String)?
    private let inserter = TextInserter()
    /// A live preview was written, then the field changed under it and could not be restored.
    private var liveDraftDiverged = false
    private var lastInsertion = ""
    private var liveDraft: LiveDictationDraft?
    let inputMethod: InputMethod
    /// This dictation is shown in the target's text field through the input method.
    private var liveInput = false
    private var typewriter = TranscriptTypewriter()
    private var typing: Timer?
    private var pendingDictationPreview: String?
    private var pendingDictationFinal: String?
    private var draftUpdateInFlight = false
    private let dictationTargetAdapter = DictationTargetAdapter()
    private var lastDictationFailure = ""
    private(set) var configuration = GestureConfiguration() { didSet { configuration.commandLayer = commandBindings } }
    private var commandBindings: [String: GestureAction] {
        command.settings.active ? templates.selectedTemplate.commandBindings : [:]
    }
    private var gestureEngine = GestureEngine()
    private var gestureTimer: Timer?
    let applicationSwitcher = ApplicationSwitcher()
    private var demoSwitcherActive = false
    private var demoApplicationIndex = 0
    private struct GestureOwner { var identity: TargetIdentity?; var pid: pid_t? }
    private var gestureOwners: [UInt64: GestureOwner] = [:]
    /// A long press that deleted keeps deleting until its key is released.
    private var deleteRepeat: (signal: GestureSignal, due: TimeInterval)?
    static let deleteRepeatInterval: TimeInterval = 0.07
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
    private var nextVoiceRouteCheck: TimeInterval = 0
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
    private var presentationProfile = ApplicationProfile.codex
    /// The scene the controls card shows; nil while it is closed.
    private var cardScene: GestureScope?
    private var cardTried = ""

    init(source: (any HIDEventSource)? = nil, templates: DeviceTemplateStore = DeviceTemplateStore(),
         sourceFactory: ((HIDDeviceProfile?, DeviceTemplateID) throws -> any HIDEventSource)? = nil,
         voiceInput: VoiceInputController? = nil, inputMethod: InputMethod? = nil,
         command: ((AccessibilityAdapter, VoiceInputController) -> CommandController)? = nil,
         vocabulary: ((VoiceInputController, CommandController) -> VocabularyKeeper)? = nil) {
        self.voiceInput = voiceInput ?? VoiceInputController()
        self.inputMethod = inputMethod ?? InputMethod()
        makeCommand = command; makeVocabulary = vocabulary
        self.templates = templates
        suppliedSource = source != nil
        self.sourceFactory = sourceFactory ?? Self.makeSource
        device = source ?? AU05HIDClient()
        configuration = templates.configuration()
        snapshot.deviceTemplate = templates.selectedID
        deviceName = templates.profile()?.name ?? templates.selectedTemplate.title
        self.voiceInput.onChange = { [weak self] in
            guard let self else { return }
            self.command.voiceChanged()
            self.emit(); self.onSettingsChanged?()
        }
        self.voiceInput.microphone = { [weak self] in self?.deviceMicrophone }
        self.voiceInput.onTranscript = { [weak self] text in self?.lastDictation = text; self?.deliverDictation(text) }
        self.voiceInput.onPartialTranscript = { [weak self] text in self?.previewDictation(text) }
        self.voiceInput.onCancel = { [weak self] in
            self?.cancelLiveDraft(); self?.dictationTarget = nil; self?.generation &+= 1
        }
        self.inputMethod.onEnded = { [weak self] kept in
            // This may come while the finished text is already on its way, so it is not tied to `liveInput`.
            guard let self, self.dictationTarget != nil else { return }
            // A field that took nothing still gets the finished text, pasted; one that kept its text does not.
            self.liveInput = false
            if kept { self.liveDraftDiverged = true; self.lastDictationFailure = "target-changed" }
        }
        adapter.onStatus = { [weak self] status in
            guard let self else { return }
            self.snapshot.status = status; self.lastDispatch["async"] = status; self.emit()
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }
        languageObserver = NotificationCenter.default.addObserver(forName: L10n.languageDidChange,
            object: L10n.shared, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLanguage() }
            }
        configuration.commandLayer = commandBindings
    }

    deinit {
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
    }

    private func refreshLanguage() {
        voiceInput.refreshLanguage()
        if device is GameControllerInputSource || device is DualSenseMicrophoneSource {
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
        keyboard.onPress = { [weak self] in
            guard let self else { return }
            self.keyboardSpeaking = true; defer { self.keyboardSpeaking = false }
            self.command.begin()
        }
        keyboard.onRelease = { [weak self] in self?.command.end() }
        keyboard.onAbandon = { [weak self] in self?.command.cancelCapture() }
        keyboard.answer = { [weak self] answer in
            guard let self, self.command.hud.capturesControls else { return false }
            // While the coordinator is acting, only Escape is taken from the keyboard.
            if self.command.hud.phase == .working, answer != .stop { return false }
            switch answer {
            case .previous: self.command.move(-1)
            case .next: self.command.move(1)
            case .confirm: self.command.confirm()
            case .stop: self.command.stop()
            }
            return true
        }
        applyKeyboard()
        let gestureTimer = Timer(timeInterval: 0.015, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceGestures() }
        }
        self.gestureTimer = gestureTimer; RunLoop.main.add(gestureTimer, forMode: .common)
        snapshot.demo = demo
        // The keeper of the vocabulary keeps its own hours from here on.
        _ = vocabulary
        inputStarted = true
        unreadySince = ProcessInfo.processInfo.systemUptime
        connectDevice()
        syncCompanions()
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileControllerVoiceRoute(); self?.fallBackToConnectedDevice(); self?.keepControllerAwake(); self?.applyKeyboard(); self?.refresh()
            }
        }
    }

    private func reconcileControllerVoiceRoute() {
        guard inputStarted, dualSenseVoiceEnabled, templates.profile(for: .dualSense) == nil else { return }
        let current = templates.selectedID == .dualSense ? device : companions[.dualSense]
        guard let current, !(current is DualSenseMicrophoneSource) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextVoiceRouteCheck else { return }
        nextVoiceRouteCheck = now + 3
        guard DualSenseMicrophoneSource.hardwareAvailable else { return }
        if templates.selectedID == .dualSense { try? replaceDevice(profile: nil, template: .dualSense) }
        else { dropCompanion(.dualSense); syncCompanions() }
    }

    func stop() {
        inputStarted = false
        syncCompanions()
        device.stop(); cancelAll(); pollTimer?.invalidate(); demoTimer?.invalidate(); gestureTimer?.invalidate(); gestureTimer = nil
        keyboard.stop(); vocabulary.settle(); command.shutdown(); voiceInput.senseVoice.shutdown()
    }

    // MARK: Command mode

    /// A command setting changed: bindings follow, and the next command starts a fresh kernel and conversation.
    private func applyCommandSettings() {
        configuration.commandLayer = commandBindings
        command.endConversation()
        applyKeyboard(); refresh(); onSettingsChanged?()
    }
    /// The keyboard listener needs the Accessibility grant, which may arrive after launch.
    private func applyKeyboard() {
        keyboard.key = command.settings.active && inputStarted ? command.settings.hotkey : .none
        if keyboard.key == .none { keyboard.stop() } else if adapter.trusted { keyboard.start() }
    }

    /// Built-in dictation records from the device whose key started it, when
    /// that device has a microphone. The keyboard has none, so it records from the one
    /// chosen for it. nil leaves the macOS default input in place.
    var deviceMicrophone: String? {
        guard voiceInput.configuration.effectiveMicrophone == .device else { return nil }
        if keyboardSpeaking || device is KeyboardInputSource { return SpeechAudioInput.resolve(voiceInput.configuration.keyboardMicrophone) }
        if device is DualSenseMicrophoneSource { return DualSenseMicrophoneSource.deviceUID }
        if let match = templates.profile()?.match {
            return SpeechAudioInput.deviceUID(vendorID: match.vendorID, productID: match.productID)
        }
        guard templates.selectedID == .vibeKey else { return nil }
        return SpeechAudioInput.deviceUID(vendorID: AU05HIDClient.vendorID, productID: AU05HIDClient.productID)
    }

    // MARK: Controls card

    /// Opens the card on the scene the app in front is in, or closes it. While it is open the device only
    /// turns its pages: a press lights its label up and reaches no app.
    func toggleCard() {
        guard cardScene == nil else { showCard(nil); return }
        // The chat picker's page stands for every list.
        showCard(ControlsCardSnapshot.scenes.contains(presentationScope) ? presentationScope
                 : presentationScope == .global ? .reading : .sessions)
    }
    func showCard(_ scene: GestureScope?) {
        if cardScene == nil, scene != nil { cancelAll() }
        cardScene = scene; cardTried = ""; emit()
    }
    /// The card answers the device the way a list does: forwards and backwards turn its pages, back closes it.
    private func turnCard(_ signal: GestureSignal, scene: GestureScope) {
        let owner: DeviceControl = signal.kind == .heldLeft || signal.kind == .heldRight ? .dial : signal.control
        let scenes = ControlsCardSnapshot.scenes, index = scenes.firstIndex(of: scene) ?? 0
        switch signal.action == .showControls ? .cancelPicker : configuration.action(.models, owner, signal.kind) {
        case .previousCandidate, .contextLeft: cardScene = scenes[max(0, index - 1)]
        case .nextCandidate, .contextRight: cardScene = scenes[min(scenes.count - 1, index + 1)]
        case .cancelPicker, .contextEscape, .escape: cardScene = nil
        default: break
        }
        // What the press would have done on the page it was made on.
        let action = configuration.action(scene, owner, signal.kind)
        let name = HUDGuidance.shortName(owner, template: templates.selectedID)
        cardTried = action == .none ? name : name + " · " + HUDGestureHint(kind: signal.kind, action: action,
            caption: HUDGuidance.caption(action, scope: scene, profile: presentationProfile)).title
        emit()
    }

    // MARK: Device following

    func setFollowsActiveDevice(_ enabled: Bool) {
        guard followsActiveDevice != enabled else { return }
        followsActiveDevice = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoSwitchKey)
        syncCompanions(); refresh(); onSettingsChanged?()
    }

    /// Layouts whose device is connected right now, including the current one.
    var connectedTemplates: Set<DeviceTemplateID> {
        var result = Set(companions.filter { $0.value.connection == .ready }.keys)
        if inputReady { result.insert(templates.selectedID) }
        return result
    }

    private func dropCompanion(_ id: DeviceTemplateID) {
        guard let source = companions.removeValue(forKey: id) else { return }
        source.onEvent = nil; source.onConnection = nil
        (source as? any ControllerPointerEventSource)?.onPointerMotion = nil
        source.stop()
    }

    /// Keeps one listening source for every other layout that can receive
    /// input without further setup. A supplied test source never has companions.
    private func syncCompanions() {
        // The keyboard is not one of them: its combinations are taken from the app in front only while it is the layout in use.
        let wanted: [DeviceTemplateID] = followsActiveDevice && inputStarted && !suppliedSource
            ? DeviceTemplateID.allCases.filter { $0 != templates.selectedID && $0 != .keyboard && templates.readiness(for: $0).hasInputConfiguration }
            : []
        for id in Array(companions.keys) where !wanted.contains(id) { dropCompanion(id) }
        for id in wanted where companions[id] == nil {
            guard let source = try? sourceFactory(templates.profile(for: id), id) else { continue }
            wireCompanion(source, id: id)
            source.start()
        }
    }

    // MARK: Keeping devices awake

    static let keepAwakeKey = "controllerKeepAwake"
    private(set) var keepsControllerAwake = UserDefaults.standard.bool(forKey: BridgeRuntime.keepAwakeKey)
    private var nextNudge: TimeInterval = 0
    func setKeepsControllerAwake(_ enabled: Bool) {
        keepsControllerAwake = enabled
        UserDefaults.standard.set(enabled, forKey: Self.keepAwakeKey)
        nextNudge = 0; onSettingsChanged?()
    }
    private func keepControllerAwake() {
        let now = ProcessInfo.processInfo.systemUptime
        guard keepsControllerAwake, inputStarted, now >= nextNudge else { return }
        nextNudge = now + 40
        for source in [device] + Array(companions.values) { (source as? GameControllerInputSource)?.nudge() }
    }
    /// "82%" or "82% · charging" once the handset has reported a level.
    var vibeKeyBattery: String? {
        guard let level = ([device] + Array(companions.values)).compactMap({ ($0 as? AU05HIDClient)?.battery }).first else { return nil }
        return "\(level.percent)%" + (level.charging ? L10n.tr(" · 充电中", " · charging") : "")
    }

    private var canAutoSwitch: Bool { followsActiveDevice && !autoSwitchSuspended && !captureOnly }
    /// When the current device last stopped being ready (launch counts).
    private var unreadySince = ProcessInfo.processInfo.systemUptime

    /// Called from the poll: once the current device has been gone for a few
    /// seconds, hand over to another layout whose device is still connected.
    private func fallBackToConnectedDevice() {
        guard inputStarted, !inputReady, canAutoSwitch, ProcessInfo.processInfo.systemUptime - unreadySince > 6,
              let fallback = DeviceTemplateID.allCases.first(where: { companions[$0]?.connection == .ready }) else { return }
        promote(fallback)
    }

    /// Swaps roles without restarting either source, so the press that woke a
    /// device is handled by its own layout and nothing is re-primed.
    private func promote(_ id: DeviceTemplateID) {
        guard let next = companions.removeValue(forKey: id) else { return }
        let previousID = templates.selectedID, previous = device
        guard let nextConfiguration = try? templates.select(id, currentConfiguration: configuration) else {
            companions[id] = next; return
        }
        cancelAll()
        previous.onEvent = nil; previous.onConnection = nil
        (previous as? any ControllerPointerEventSource)?.onPointerMotion = nil
        next.onEvent = nil; next.onConnection = nil
        (next as? any ControllerPointerEventSource)?.onPointerMotion = nil
        configuration = nextConfiguration
        device = next
        deviceName = templates.profile(for: id)?.name ?? id.template.title
        snapshot.deviceTemplate = id; snapshot.rotation = 0
        attachDevice()
        inputReady = next.connection == .ready
        if !inputReady { unreadySince = ProcessInfo.processInfo.systemUptime }
        deviceStatus = connectionSummary
        // The previous device keeps listening unless its template lost its backend. The keyboard stops: its
        // combinations go back to the app in front once another device is the one in use.
        if previousID != .keyboard, templates.readiness(for: previousID).hasInputConfiguration { wireCompanion(previous, id: previousID) }
        else { previous.stop() }
        refresh(); onSettingsChanged?()
    }

    private func wireCompanion(_ source: any HIDEventSource, id: DeviceTemplateID) {
        companions[id] = source
        source.onConnection = { [weak self, weak source] state in
            guard let self, let source, self.companions[id] === source else { return }
            // A device that just came online takes over only when the current
            // one has been away for a while, not while it is still connecting.
            if state == .ready, !self.inputReady, self.canAutoSwitch,
               ProcessInfo.processInfo.systemUptime - self.unreadySince > 6 { self.promote(id) }
            else { self.emit(); self.onSettingsChanged?() }
        }
        source.onEvent = { [weak self, weak source] event in
            guard let self, let source, self.companions[id] === source,
                  event.phase == .down || event.phase == .pulse, self.canAutoSwitch else { return }
            self.promote(id)
            self.receiveHardware(event)
        }
        (source as? any ControllerPointerEventSource)?.onPointerMotion = { [weak self, weak source] motion in
            guard let self, let source, self.companions[id] === source, self.canAutoSwitch else { return }
            self.promote(id)
            self.receivePointerMotion(motion)
        }
    }

    static func makeSource(profile: HIDDeviceProfile?, template: DeviceTemplateID) throws -> any HIDEventSource {
        if let profile { return try GenericHIDClient(profile: profile) }
        switch template {
        case .vibeKey: return AU05HIDClient()
        case .dualSense: return UserDefaults.standard.bool(forKey: "dualSenseVoiceEnabled") && DualSenseMicrophoneSource.hardwareAvailable
            ? DualSenseMicrophoneSource() : GameControllerInputSource()
        case .xiaomiRemote: return UnconfiguredHIDSource(template: template.template)
        case .keyboard: return KeyboardInputSource()
        }
    }

    var connectionSummary: String {
        device is GameControllerInputSource || device is DualSenseMicrophoneSource ? controllerConnectionSummary(device.connection) : deviceStatus
    }

    private func controllerConnectionSummary(_ state: AU05Connection) -> String {
        switch state {
        case .ready: return device is DualSenseMicrophoneSource
            ? L10n.tr("蓝牙手柄与麦克风已连接", "Bluetooth controller and microphone connected")
            : L10n.tr("手柄已连接 · USB / 蓝牙自动识别", "Controller connected · automatic USB / Bluetooth input")
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
        // Only one source may own a layout's hardware (the AU05 link is exclusive).
        dropCompanion(template)
        let next = try sourceFactory(profile, template)
        device.onEvent = nil; device.onConnection = nil
        (device as? any ControllerPointerEventSource)?.onPointerMotion = nil
        device.stop(); cancelAll(); inputReady = false; device = next
        unreadySince = ProcessInfo.processInfo.systemUptime
        deviceName = profile?.name ?? template.template.title
        deviceStatus = L10n.tr("等待设备", "Waiting for device")
        snapshot.deviceTemplate = template
        snapshot.rotation = 0
        if inputStarted { connectDevice() }
        syncCompanions()
    }
    func configureDevice(profile: HIDDeviceProfile?) throws {
        try templates.setProfile(profile, for: templates.selectedID)
        try replaceDevice(profile: profile, template: templates.selectedID)
        onSettingsChanged?()
    }
    func selectTemplate(_ id: DeviceTemplateID) throws {
        let profile = templates.profile(for: id)
        // A layout that is already listening becomes current without a reconnect.
        if id != templates.selectedID, companions[id] != nil { promote(id); return }
        let configuration = try templates.select(id, currentConfiguration: self.configuration)
        self.configuration = configuration
        try replaceDevice(profile: profile, template: id)
        refresh()
        onSettingsChanged?()
    }
    func reconnectDevice() {
        device.stop(); cancelAll()
        for id in Array(companions.keys) { dropCompanion(id) }
        if inputStarted { connectDevice(); syncCompanions() }
    }
    func updateConfiguration(_ value: GestureConfiguration) throws {
        try templates.updateConfiguration(value)
        cancelAll(); configuration = value; refresh(); onSettingsChanged?()
    }
    func resetConfiguration() {
        if let value = try? templates.resetConfiguration() { cancelAll(); configuration = value; refresh(); onSettingsChanged?() }
    }
    private func connectDevice() { attachDevice(); device.start() }
    private func attachDevice() {
        device.onConnection = { [weak self] state in
            guard let self else { return }
            if state != .ready, self.inputReady { self.unreadySince = ProcessInfo.processInfo.systemUptime }
            self.inputReady = state == .ready
            if self.device is GameControllerInputSource || self.device is DualSenseMicrophoneSource {
                self.deviceName = self.templates.selectedTemplate.title
                self.deviceStatus = self.controllerConnectionSummary(state)
            } else { self.deviceStatus = state.title }
            if state != .ready { self.cancelAll(); self.snapshot.action = self.deviceStatus }
            else { self.snapshot.action = self.captureOnly ? L10n.tr("只显示物理事件，不发送操作", "Physical events only; no actions sent") : L10n.tr("直连已就绪，等待操作", "Connected; ready for input") }
            self.refresh()
        }
        device.onEvent = { [weak self] event in
            guard let self else { return }
            // A combination that holds the command key's modifier is the keyboard layout's, not a command.
            if self.device is KeyboardInputSource { self.keyboard.abandon() }
            self.receiveHardware(event)
        }
        (device as? any ControllerPointerEventSource)?.onPointerMotion = { [weak self, weak source = device] motion in
            guard let self, let source, self.device === source else { return }
            self.receivePointerMotion(motion)
        }
    }
    func receivePointerMotion(_ motion: ControllerPointerMotion) {
        guard inputStarted, inputReady, templates.selectedID == .dualSense else { return }
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
        let scope = currentScope(observation.context)
        // A press that a long hold turns into a spoken command is listened to from the moment it begins: the
        // hold is only known half a second in, and the sentence starts before that. A short press drops it.
        if phase == .down, !demo, voiceInput.recordsFromMicrophone, command.settings.active,
           configuration.action(scope, control, .long) == .command, configuration.action(scope, control, .hold) == .none {
            SpeechAudioInput.arm(deviceMicrophone); listeningPress = control
        } else if phase != .pulse, listeningPress == control {
            listeningPress = nil; SpeechAudioInput.disarm()
        }
        let signals = gestureEngine.receive(control, phase: phase, now: ProcessInfo.processInfo.systemUptime,
            scope: scope, config: configuration,
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
        if phase == .cancel && dictationHolders.isEmpty { dictation.cancel(); voiceInput.cancel(); dictationTarget = nil }
        if gestureOwners.count > 128 {
            let oldest = gestureOwners.keys.sorted().prefix(gestureOwners.count - 128)
            for token in oldest { gestureOwners.removeValue(forKey: token) }
        }
        emit()
    }
    func advanceGestures(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !captureOnly else { return }
        gestureEngine.tick(now: now).forEach(dispatch)
        if let hold = commandHold, gestureEngine.token(for: hold.control) != hold.token { commandHold = nil; command.end() }
        repeatDelete(now: now)
    }
    /// Like a keyboard's Backspace. Repeats are plain deletions, so emptying the
    /// draft cannot turn the rest of the hold into Escape.
    private func repeatDelete(now: TimeInterval) {
        guard let repeating = deleteRepeat else { return }
        guard gestureEngine.token(for: repeating.signal.control) == repeating.signal.token else { deleteRepeat = nil; return }
        guard now >= repeating.due else { return }
        deleteRepeat?.due = now + Self.deleteRepeatInterval
        if demo { execute(repeating.signal, observation: demoObservation()); return }
        // The last sample is at most one poll old; each repeat asks for the next one.
        let observation = adapter.observe()
        if let identity = observation.identity, identity == gestureOwners[repeating.signal.token]?.identity {
            execute(repeating.signal, observation: observation)
        }
        refresh()
    }
    private var switcherActive: Bool { demo ? demoSwitcherActive : applicationSwitcher.active }
    private func currentScope(_ context: InteractionContext) -> GestureScope {
        if command.hud.capturesControls { return .command }
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
        // The touchpad stays a mouse, so the card's own tabs and close button can be clicked with it.
        if let scene = cardScene, signal.action != .pointerClick {
            if signal.phase == .down || signal.phase == .pulse { turnCard(signal, scene: scene) }
            return
        }
        if signal.action == .showControls {
            if signal.phase == .down || signal.phase == .pulse { toggleCard() }
            return
        }
        if signal.action == .command {
            guard !demo else { return }
            switch (signal.kind, signal.phase) {
            case (.hold, .down): command.begin()
            case (.hold, .up): command.end()
            case (.hold, .cancel): command.cancelCapture()
            // The release of a long press is seen in advanceGestures.
            case (.long, _): command.begin(); commandHold = (signal.control, signal.token)
            // A key that cannot be held starts on one press and ends on the next.
            case (_, .pulse): if command.hud.phase == .listening { command.end() } else { command.begin() }
            default: break
            }
            emit(); return
        }
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
        if command.hud.capturesControls {
            // The device answers the coordinator; nothing is sent to the app in front.
            guard signal.phase == .pulse || signal.phase == .down else { return }
            switch signal.action {
            case .previousCandidate, .contextLeft: command.move(-1)
            case .nextCandidate, .contextRight: command.move(1)
            case .confirmCandidate, .contextConfirm, .contextDial, .enter: command.confirm()
            case .cancelPicker, .contextEscape, .escape: command.stop()
            default: break
            }
            return
        }
        if signal.action == .dictation {
            let wasHeld = !dictationHolders.isEmpty
            if signal.phase == .down { dictationHolders.insert(signal.control) }
            else if signal.phase == .up || signal.phase == .cancel { dictationHolders.remove(signal.control) }
            if !demo && adapter.trusted {
                if voiceInput.configuration.mode == .external {
                    if signal.phase == .pulse { dictation.pulse() }
                    else { dictation.setHeld(!dictationHolders.isEmpty) }
                } else if signal.phase == .cancel {
                    voiceInput.cancel(); dictationTarget = nil
                } else if signal.phase == .pulse {
                    voiceInput.report(L10n.tr("内置听写需要按住并松开的按键", "Built-in dictation needs a hold-and-release button"))
                } else if !wasHeld && !dictationHolders.isEmpty {
                    // The microphone opens at the press; looking at the text field first would cost the first word.
                    if voiceInput.recordsFromMicrophone { SpeechAudioInput.arm(deviceMicrophone) }
                    beginDictation()
                } else if wasHeld && dictationHolders.isEmpty {
                    // Released before the recording was taken up: what the press heard is dropped.
                    if !voiceInput.state.active { SpeechAudioInput.disarm() }
                    voiceInput.end()
                }
            }
            snapshot.action = signal.phase == .down ? L10n.tr("按住 · 听写", "Hold · dictate") : L10n.tr("松开 · 等待听写文字", "Released · waiting for dictated text")
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
                case .switchApplications: dictation.cancel(); voiceInput.cancel(); dictationTarget = nil; applicationSwitcher.begin()
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
            guard let self, self.generation == requestGeneration,
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
        case .contextEscape:
            let reduced = reduce(state: &interaction, control: .escape, context: observation.context)
            // Where a terminal shows no draft the press stays Escape; the hold is still Backspace.
            let holdsInTerminal = signal.kind == .long && observation.context.applicationProfile == .terminal
            effect = reduced == .sendEscape && holdsInTerminal ? .deleteBackward : reduced
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
        if effect == .deleteBackward, signal.kind == .long, deleteRepeat == nil,
           gestureEngine.token(for: signal.control) == signal.token {
            var next = signal; next.action = .deleteBackward
            deleteRepeat = (next, ProcessInfo.processInfo.systemUptime + Self.deleteRepeatInterval)
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
        let data = try JSONSerialization.data(withJSONObject: diagnostics(), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    func diagnostics() throws -> [String: Any] {
        // Diagnostic summary intentionally contains no chat text or credentials.
        var value: [String: Any] = ["mode":snapshot.mode,"action":snapshot.action,"status":snapshot.status,"demo":snapshot.demo,"inputReady":inputReady,"accessibility":adapter.trusted,"device":deviceName,"deviceStatus":deviceStatus,"captureOnly":captureOnly,"eventCounts":eventCounts,"lastDeviceEvent":lastDeviceEvent,"recentActions":recentActions,"lastDispatch":lastDispatch,"appSwitcher":switcherActive,"pressed":snapshot.pressed.map(\.rawValue)]
        value["dockVisible"] = NSApp?.activationPolicy() == .regular
        value["deviceTemplate"] = snapshot.deviceTemplate.rawValue
        value["scope"] = snapshot.scope.rawValue
        value["target"] = snapshot.target
        value["connectedTemplates"] = connectedTemplates.map(\.rawValue).sorted()
        value["autoSwitch"] = followsActiveDevice
        value["keepAwake"] = keepsControllerAwake
        value["vibeKeyBattery"] = vibeKeyBattery ?? ""
        value["selecting"] = !snapshot.selection.isEmpty
        value["speech"] = ["state": String(describing: voiceInput.state), "previewCharacters": voiceInput.liveTranscript.count,
            "liveInsertion": liveDraft != nil || liveInput, "style": voiceInput.configuration.effectiveTextStyle.rawValue,
            "failure": lastDictationFailure, "insertion": lastInsertion, "message": voiceInput.displayMessage, "frontApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""]
        value["inputMethod"] = ["enabled": inputMethod.enabled, "waiting": inputMethod.waiting, "connected": inputMethod.connected, "client": inputMethod.client ?? ""]
        value["vocabulary"] = ["learning": vocabulary.enabled, "waiting": vocabulary.waiting]
        if let controller = device as? GameControllerInputSource {
            value["inputBackend"] = "GameController"
            value["controllerMetrics"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.diagnostics))
        }
        if let au05 = device as? AU05HIDClient {
            value["hidMetrics"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(au05.diagnostics))
        }
        return value
    }

    private func refresh() {
        if !demo && !captureOnly { adapter.requestRefresh { [weak self] _ in self?.updateObservedState() } }
        updateObservedState()
    }

    private func updateObservedState() {
        if voiceInput.state.active, let target = dictationTarget,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid {
            voiceInput.cancel(); dictationTarget = nil
            voiceInput.report(L10n.tr("已切换应用，听写已取消", "App changed; dictation canceled"))
        }
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
        presentationProfile = context.applicationProfile
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
        command.cancelCapture(); commandHold = nil
        cancelLiveDraft()
        generation &+= 1
        adapter.reset()
        _ = gestureEngine.reset(); gestureOwners.removeAll(); dictationHolders.removeAll()
        dictation.cancel(); voiceInput.cancel(); dictationTarget = nil; applicationSwitcher.cancel(); demoSwitcherActive = false; hardwarePressed.removeAll()
        hardwarePulseTimers.values.forEach { $0.invalidate() }; hardwarePulseTimers.removeAll()
        pulseTimers.values.forEach { $0.invalidate() }; pulseTimers.removeAll()
        snapshot.pressed.removeAll()
    }
    private func emit() {
        snapshot.voice = VoiceHUDSnapshot(enabled: voiceInput.configuration.mode == .builtIn,
            state: voiceInput.state, style: voiceInput.configuration.effectiveTextStyle,
            text: voiceInput.liveTranscript, status: voiceInput.displayMessage,
            kept: !lastDictation.isEmpty && !voiceInput.state.active)
        if voiceInput.configuration.mode == .builtIn && !demo && !captureOnly &&
           (voiceInput.state != .idle || !voiceInput.message.isEmpty) {
            snapshot.status = voiceInput.displayMessage
        }
        snapshot.command = command.hud
        // A question from the coordinator needs the device back.
        if command.hud.capturesControls { cardScene = nil }
        snapshot.card = cardScene.map { ControlsCardSnapshot(scene: $0, hints: HUDGuidance.hints(template: templates.selectedTemplate,
            configuration: configuration, scope: $0, profile: presentationProfile), tried: cardTried) }
        snapshot.deviceTemplate = templates.selectedID
        snapshot.connectedTemplates = connectedTemplates
        snapshot.selection = demo || captureOnly ? "" : adapter.selectionTitle
        snapshot.scope = presentationScope
        snapshot.controlHints = HUDGuidance.hints(template: templates.selectedTemplate,
            configuration: configuration, scope: presentationScope, profile: presentationProfile)
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
    private func beginDictation(replay: Bool = false) {
        command.cancelCapture()
        vocabulary.settle()
        cancelLiveDraft()
        generation &+= 1
        dictationTarget = nil; dictationApp = nil; liveDraftDiverged = false
        lastDictationFailure = ""; lastInsertion = ""
        let token = generation
        guard let app = NSWorkspace.shared.frontmostApplication else {
            voiceInput.report(L10n.tr("请先切到要输入的应用", "Bring the app you want to type into to the front")); return
        }
        let bundleID = app.bundleIdentifier ?? ""
        // An input method that was restarted is joined again here, in time to say which text field it faces.
        inputMethod.connect()
        dictationTargetAdapter.requestRefresh { [weak self] observation in
            guard let self, self.generation == token, replay || !self.dictationHolders.isEmpty else { return }
            guard observation.pid != nil, let identity = observation.identity else {
                self.voiceInput.report(L10n.tr("当前应用暂时无法输入，请重试", "This app is not ready for input; try again")); return
            }
            guard !observation.secureField else {
                self.voiceInput.report(L10n.tr("密码框不接收听写", "Dictation is not typed into password fields")); return
            }
            guard !observation.context.compositionActive else {
                self.voiceInput.report(L10n.tr("请先完成输入法候选", "Finish the input method candidate first")); return
            }
            self.dictationTarget = identity
            self.dictationApp = (identity.pid, bundleID)
            // Text appears in the field while speaking through VibeWand's input method where that is switched
            // on, and otherwise where a direct accessibility write is known to work; other apps get one paste
            // at the end.
            if TextInserter.method == .automatic, self.inputMethod.begin(bundleID) { self.liveInput = true }
            else if let editor = observation.editor, TextInserter.supportsDirectWrites(bundleID) {
                self.liveDraft = LiveDictationDraft(field: AccessibilityDictationField(element: editor, pid: identity.pid),
                                                    settlementTimeout: 0.6)
            }
            // What a command was still saying would be recorded with the dictation.
            self.command.speech?.stop()
            self.voiceInput.begin()
        }
    }
    private func previewDictation(_ text: String) {
        guard dictationTarget != nil, liveInput || liveDraft != nil else { return }
        typewriter.aim(text)
        guard typing == nil else { return }
        typing = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.type() } }
    }
    /// One step of the text growing in the field: a recogniser's phrases are typed, not dropped in whole.
    private func type() {
        guard liveInput || liveDraft != nil, let text = typewriter.advance() else { typing?.invalidate(); typing = nil; return }
        if liveInput { inputMethod.show(text) } else { pendingDictationPreview = text; flushDictationDraft() }
    }
    private func stopTyping() { typing?.invalidate(); typing = nil; typewriter = TranscriptTypewriter() }
    private func deliverDictation(_ text: String) {
        guard dictationTarget != nil else { return }
        stopTyping()
        if liveInput {
            // The finished text takes the place of everything shown so far, in one step.
            liveInput = false
            let token = generation
            // An input method's line break is a pressed Return to a terminal, so text with lines in it is
            // pasted, as it always was.
            guard text == UnicodeTextDelivery.safeCharacters(text) else {
                inputMethod.cancel { [weak self] in if let self, self.generation == token { self.insertFinal(text) } }
                return
            }
            inputMethod.commit(text) { [weak self] written in
                guard let self, self.generation == token else { return }
                guard written else { self.deliverDictation(text); return }
                self.lastInsertion = "input-method"
                self.dictationWritten(text)
            }
            return
        }
        if liveDraft != nil { pendingDictationFinal = text; flushDictationDraft(); return }
        if liveDraftDiverged {
            finishDictation(L10n.tr("草稿在听写时被修改，已保留写入的文字", "The draft changed while dictating; the text already written was kept"))
            return
        }
        insertFinal(text)
    }
    /// One insertion at the caret of the app that owned key-down.
    private func insertFinal(_ text: String) {
        guard let app = dictationApp, adapter.trusted else { finishDictation(L10n.tr("请先开启辅助功能权限", "Enable Accessibility permission first")); return }
        let token = generation
        dictationTargetAdapter.requestRefresh { [weak self] observation in
            guard let self, self.generation == token, self.dictationApp?.pid == app.pid else { return }
            guard observation.pid == app.pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid else {
                self.lastDictationFailure = "app-changed"
                self.finishDictation(L10n.tr("已切换应用，文字未插入", "App changed; the text was not inserted")); return
            }
            guard !observation.secureField else {
                self.finishDictation(L10n.tr("密码框不接收听写", "Dictation is not typed into password fields")); return
            }
            // A terminal's text area is its whole scrollback; it is pasted into, never read back.
            let editor = ApplicationProfile.resolve(bundleID: app.bundleID) == .terminal ? nil : observation.editor
            self.inserter.insert(text, pid: app.pid, bundleID: app.bundleID, editor: editor) { [weak self] outcome in
                guard let self, self.generation == token else { return }
                switch outcome {
                case .inserted(let via, let verified):
                    self.lastInsertion = via + (verified ? "" : "-unverified")
                    self.dictationWritten(text)
                case .failed:
                    self.lastDictationFailure = "insert-failed"
                    self.finishDictation(L10n.tr("文字未能写入，请重新聚焦输入框后重试", "The text could not be inserted; refocus the field and retry"))
                }
            }
        }
    }
    /// The text is in its field. With the user's leave the field is read back from here on, to learn from what
    /// they change in it.
    private func dictationWritten(_ text: String) {
        if let app = dictationApp { vocabulary.written(text, pid: app.pid, bundleID: app.bundleID) }
        finishDictation(vocabulary.hint() ?? L10n.tr("听写已完成，请检查后发送", "Dictation complete; review before sending"))
    }
    private func finishDictation(_ message: String) {
        liveDraft = nil; liveInput = false; dictationTarget = nil; dictationApp = nil; liveDraftDiverged = false
        pendingDictationPreview = nil; pendingDictationFinal = nil; draftUpdateInFlight = false
        voiceInput.report(message)
    }
    private func flushDictationDraft() {
        guard !draftUpdateInFlight, let target = dictationTarget, let draft = liveDraft,
              let text = pendingDictationFinal ?? pendingDictationPreview else { return }
        let isFinal = pendingDictationFinal != nil, token = generation
        if isFinal { pendingDictationFinal = nil; pendingDictationPreview = nil } else { pendingDictationPreview = nil }
        draftUpdateInFlight = true
        dictationTargetAdapter.requestRefresh { [weak self] observation in
            guard let self, self.generation == token, self.dictationTarget == target else { return }
            self.draftUpdateInFlight = false
            guard DictationDelivery.accepts(target: target, observation: observation,
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, ownsWrite: draft.ownsWrite) else {
                self.lastDictationFailure = "target-changed"; self.abandonLiveDraft(draft, final: isFinal ? text : nil); return
            }
            switch draft.update(text) {
            case .applied:
                if isFinal {
                    self.lastInsertion = "accessibility-live"
                    self.dictationWritten(text)
                } else { self.flushDictationDraft() }
            case .pending:
                if isFinal { self.pendingDictationFinal = text }
                else if self.pendingDictationPreview == nil { self.pendingDictationPreview = text }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    guard let self, self.generation == token else { return }; self.flushDictationDraft()
                }
            case .conflict, .unavailable:
                self.lastDictationFailure = draft.failureReason; self.abandonLiveDraft(draft, final: isFinal ? text : nil)
            }
        }
    }
    /// Live preview is a convenience. When the field stops cooperating the
    /// recording continues, and the finished text is inserted once instead.
    private func abandonLiveDraft(_ draft: LiveDictationDraft, final: String?) {
        if !draft.hasWritten {
            // Nothing of ours is in the field: this app does not take direct writes.
            if draft.failureReason != "value-changed" && draft.failureReason != "selection-changed", let app = dictationApp {
                TextInserter.markPasteOnly(app.bundleID)
            }
        } else if !draft.rollback() { liveDraftDiverged = true }
        liveDraft = nil; pendingDictationPreview = nil; draftUpdateInFlight = false
        let text = final ?? pendingDictationFinal
        pendingDictationFinal = nil
        if let text { deliverDictation(text) }
    }
    private func cancelLiveDraft() {
        if liveInput { inputMethod.cancel(); liveInput = false }
        stopTyping()
        if let target = dictationTarget, let draft = liveDraft,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
           dictationStillFocused(target) { _ = draft.rollback() }
        liveDraft = nil; pendingDictationPreview = nil; pendingDictationFinal = nil; draftUpdateInFlight = false
        liveDraftDiverged = false; inserter.cancel()
    }
    private func dictationStillFocused(_ target: TargetIdentity) -> Bool {
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.02)
        var focus: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focus) == .success else { return false }
        for _ in 0..<8 {
            guard let candidate = focus, CFGetTypeID(candidate) == AXUIElementGetTypeID() else { return false }
            if CFHash(candidate) == target.focusedHash { return true }
            let element = unsafeBitCast(candidate, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(element, 0.02)
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success else { return false }
            focus = parent
        }
        return false
    }
    /// Writes the last dictation into the text field in front, for when it did not arrive there the first
    /// time: the field had lost the focus, the app was switched, or the write was refused.
    func reinsertDictation() {
        guard !lastDictation.isEmpty, !voiceInput.state.active, adapter.trusted, let app = NSWorkspace.shared.frontmostApplication else { return }
        let text = lastDictation, pid = app.processIdentifier, bundleID = app.bundleIdentifier ?? ""
        dictationTargetAdapter.requestRefresh { [weak self] observation in
            guard let self else { return }
            guard observation.pid == pid, !observation.secureField else {
                self.voiceInput.report(L10n.tr("请先点一下要写入的输入框", "Click the field to write into first")); return
            }
            let editor = ApplicationProfile.resolve(bundleID: bundleID) == .terminal ? nil : observation.editor
            self.inserter.insert(text, pid: pid, bundleID: bundleID, editor: editor) { [weak self] outcome in
                if case .inserted = outcome { self?.voiceInput.report(L10n.tr("已再次写入，请检查后发送", "Written again; review before sending")) }
                else { self?.voiceInput.report(L10n.tr("文字未能写入，请重新聚焦输入框后重试", "The text could not be inserted; refocus the field and retry")) }
            }
        }
    }
    func toggleSpeechTextStyle() {
        do { try voiceInput.toggleTextStyle() }
        catch { voiceInput.report((error as? SpeechInputError)?.displayMessage ?? error.localizedDescription) }
    }
    func replaySpeech(duration: Double) {
        guard !demo, !captureOnly else { return }
        adapter.requestRefresh { [weak self] _ in
            guard let self else { return }
            self.beginDictation(replay: true)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((duration + 2) * 1_000_000_000))
                guard let self, self.voiceInput.state == .recording else { return }; self.voiceInput.end()
            }
        }
    }
    func updateSpeechConfiguration(_ value: SpeechConfiguration) throws {
        cancelAll(); try voiceInput.update(value); onSettingsChanged?()
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
