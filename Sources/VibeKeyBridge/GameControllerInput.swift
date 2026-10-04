import AppKit
import AU05Device
import GameController

struct GameControllerTransition: Equatable {
    let control: AU05Control
    let phase: AU05Phase
}

/// Device-independent decoding is shared by live input and snapshot tests. A
/// stick produces an initial step and bounded repeats, with hysteresis around
/// neutral. Releasing or cancelling it never creates an extra gesture.
struct GameControllerDecoder {
    enum Axis: String, CaseIterable {
        case leftX, leftY, rightX, rightY
        var negative: AU05Control {
            switch self {
            case .leftX: return .leftStickLeft
            case .leftY: return .leftStickDown
            case .rightX: return .rightStickLeft
            case .rightY: return .rightStickDown
            }
        }
        var positive: AU05Control {
            switch self {
            case .leftX: return .leftStickRight
            case .leftY: return .leftStickUp
            case .rightX: return .rightStickRight
            case .rightY: return .rightStickUp
            }
        }
    }
    struct Sample {
        var buttons: [AU05Control: Bool] = [:]
        var axes: [Axis: Float] = [:]
    }
    private struct AxisState { var control: AU05Control; var nextRepeat: TimeInterval }
    private var buttons: Set<AU05Control> = []
    private var suppressedButtons: Set<AU05Control> = []
    private var axes: [Axis: AxisState] = [:]
    private var suppressedAxes: Set<Axis> = []
    static let deadZone: Float = 0.22
    static let releaseZone: Float = 0.16
    static let repeatDelay: TimeInterval = 0.35
    static let repeatInterval: TimeInterval = 0.09

    /// Changing templates or reconnecting while a button is already held must
    /// not act on the foreground app. Wait for release/neutral before arming it.
    mutating func prime(_ sample: Sample) {
        _ = reset()
        suppressedButtons = Set(sample.buttons.filter { $0.value }.map(\.key))
        suppressedAxes = Set(sample.axes.filter { abs($0.value) > Self.releaseZone }.map(\.key))
    }

    mutating func consume(_ sample: Sample, now: TimeInterval) -> [GameControllerTransition] {
        var events: [GameControllerTransition] = []
        for control in Set(sample.buttons.keys).union(buttons).union(suppressedButtons).sorted(by: { $0.rawValue < $1.rawValue }) {
            let down = sample.buttons[control] ?? false
            if suppressedButtons.contains(control) {
                if !down { suppressedButtons.remove(control) }
                continue
            }
            if down, buttons.insert(control).inserted {
                events.append(GameControllerTransition(control: control, phase: control == .left || control == .right ? .pulse : .down))
            } else if !down, buttons.remove(control) != nil, control != .left, control != .right {
                events.append(GameControllerTransition(control: control, phase: .up))
            }
        }
        for axis in Axis.allCases {
            let value = sample.axes[axis] ?? 0
            if suppressedAxes.contains(axis) {
                if !value.isFinite || abs(value) <= Self.releaseZone { suppressedAxes.remove(axis) }
                continue
            }
            let previous = axes[axis]?.control
            let next: AU05Control?
            if !value.isFinite || abs(value) > 1 { next = nil }
            else if previous == axis.negative, value < -Self.releaseZone { next = previous }
            else if previous == axis.positive, value > Self.releaseZone { next = previous }
            else if value <= -Self.deadZone { next = axis.negative }
            else if value >= Self.deadZone { next = axis.positive }
            else { next = nil }
            guard previous != next else { continue }
            if let previous {
                axes.removeValue(forKey: axis)
                events.append(GameControllerTransition(control: previous, phase: .up))
            }
            if let next {
                axes[axis] = AxisState(control: next, nextRepeat: now + Self.repeatDelay)
                events += [GameControllerTransition(control: next, phase: .down), GameControllerTransition(control: next, phase: .pulse)]
            }
        }
        return events
    }

    mutating func repeats(now: TimeInterval) -> [GameControllerTransition] {
        var events: [GameControllerTransition] = []
        for axis in Axis.allCases {
            guard var state = axes[axis], now >= state.nextRepeat else { continue }
            state.nextRepeat = now + Self.repeatInterval
            axes[axis] = state
            events.append(GameControllerTransition(control: state.control, phase: .pulse))
        }
        return events
    }

    mutating func reset() -> [GameControllerTransition] {
        let held = buttons.filter { $0 != .left && $0 != .right }.union(axes.values.map(\.control))
        buttons.removeAll(); axes.removeAll(); suppressedButtons.removeAll(); suppressedAxes.removeAll()
        return held.sorted { $0.rawValue < $1.rawValue }.map { GameControllerTransition(control: $0, phase: .cancel) }
    }
}

struct GameControllerDiagnostics: Codable {
    var availableControllers = 0
    var supportedControllers = 0
    var selectedName: String?
    var touchpadAvailable = false
    var events: UInt64 = 0
    var pointerMovements: UInt64 = 0
}

struct ControllerPointerMotion: Equatable {
    var dx: Double
    var dy: Double
}

@MainActor
protocol ControllerPointerEventSource: HIDEventSource {
    var onPointerMotion: ((ControllerPointerMotion) -> Void)? { get set }
}

/// Finger coordinates are relative to the pad, not the desktop. Re-anchor on
/// first contact, lift, reconnection, stale samples or a contact-ID jump.
struct ControllerTouchpadDecoder {
    struct Contact: Equatable { var x: Float; var y: Float }
    private var previous: Contact?
    private var sampledAt: TimeInterval?

    mutating func prime(_ contact: Contact?, now: TimeInterval) {
        previous = contact; sampledAt = now
    }
    mutating func reset() { previous = nil; sampledAt = nil }
    mutating func consume(_ contact: Contact?, now: TimeInterval) -> ControllerPointerMotion? {
        guard let contact, contact.x.isFinite, contact.y.isFinite,
              abs(contact.x) <= 1, abs(contact.y) <= 1 else { reset(); return nil }
        defer { previous = contact; sampledAt = now }
        guard let previous, let sampledAt, now >= sampledAt, now - sampledAt <= 0.18 else { return nil }
        let dx = Double(contact.x - previous.x), dy = Double(contact.y - previous.y)
        guard abs(dx) <= 0.65, abs(dy) <= 0.65,
              abs(dx) > 0.0005 || abs(dy) > 0.0005 else { return nil }
        // Apple's Y points up; Quartz desktop coordinates point down. The pad
        // is roughly twice as wide as it is tall, so use equal physical gain.
        return ControllerPointerMotion(dx: dx * 700, dy: -dy * 350)
    }
}

/// Native macOS controller input. macOS handles supported USB/Bluetooth device
/// identification; this source never guesses HID IDs, seizes an interface,
/// pairs a device, or touches its audio endpoint.
@MainActor
final class GameControllerInputSource: ControllerPointerEventSource {
    private(set) var connection: AU05Connection = .stopped
    private(set) var diagnostics = GameControllerDiagnostics()
    var connectedName: String? { diagnostics.selectedName }
    var onConnection: ((AU05Connection) -> Void)?
    var onEvent: ((AU05Event) -> Void)?
    var onPointerMotion: ((ControllerPointerMotion) -> Void)?

    private let controllers: () -> [GCController]
    private let notifications: NotificationCenter
    private let workspaceNotifications: NotificationCenter
    private let readTouchpad: @MainActor (GCExtendedGamepad) -> ControllerTouchpadDecoder.Contact?
    private var controller: GCController?
    private var decoder = GameControllerDecoder()
    private var touchpadDecoder = ControllerTouchpadDecoder()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var running = false
    private var sleeping = false
    private var generation: UInt64 = 0
    private var previousBackgroundMonitoring = false
    private var nextInventoryRefresh: TimeInterval = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(controllers: @escaping () -> [GCController] = { GCController.controllers().filter { !$0.isSnapshot } },
         notifications: NotificationCenter = .default,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         readTouchpad: @escaping @MainActor (GCExtendedGamepad) -> ControllerTouchpadDecoder.Contact? = { GameControllerInputSource.touchpadContact($0) }) {
        self.controllers = controllers
        self.notifications = notifications
        self.workspaceNotifications = workspaceNotifications
        self.readTouchpad = readTouchpad
    }

    func start() {
        guard !running else { return }
        running = true; sleeping = false
        previousBackgroundMonitoring = GCController.shouldMonitorBackgroundEvents
        GCController.shouldMonitorBackgroundEvents = true
        observe(.GCControllerDidConnect, center: notifications) { source, _ in source.refreshControllers() }
        observe(.GCControllerDidDisconnect, center: notifications) { source, notification in
            source.refreshControllers(excluding: notification.object as? GCController)
        }
        observe(.GCControllerUserCustomizationsDidChange, center: notifications) { source, notification in
            guard let changed = notification.object as? GCController, source.controller === changed else { return }
            source.detach(); source.set(.waiting); source.refreshControllers()
        }
        observe(NSWorkspace.willSleepNotification, center: workspaceNotifications) { source, _ in source.suspend() }
        observe(NSWorkspace.didWakeNotification, center: workspaceNotifications) { source, _ in source.resume() }
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running, !self.sleeping else { return }
                let now = self.now
                if now >= self.nextInventoryRefresh {
                    self.nextInventoryRefresh = now + 1
                    self.refreshControllers()
                }
                self.pollInput(now: now)
            }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        refreshControllers()
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate(); timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        detach()
        GCController.shouldMonitorBackgroundEvents = previousBackgroundMonitoring
        set(.stopped)
    }

    /// Keep the currently selected controller when another connects or the
    /// enumeration order changes. Never merge presses from multiple devices.
    func refreshControllers(excluding removed: GCController? = nil) {
        guard running, !sleeping else { return }
        let available = controllers().filter { $0 !== removed }
        let supported = available.filter { $0.extendedGamepad != nil }
        diagnostics.availableControllers = available.count
        diagnostics.supportedControllers = supported.count
        if let controller, supported.contains(where: { $0 === controller }) { return }
        detach()
        set(.waiting)
        guard let next = supported.first, let gamepad = next.extendedGamepad else { return }
        controller = next
        next.handlerQueue = .main
        diagnostics.selectedName = next.vendorName?.isEmpty == false ? next.vendorName :
            (next.productCategory.isEmpty ? "Controller" : next.productCategory)
        diagnostics.touchpadAvailable = Self.touchpadButton(gamepad) != nil
        decoder.prime(Self.sample(gamepad))
        touchpadDecoder.prime(readTouchpad(gamepad), now: now)
        let generation = generation
        gamepad.valueChangedHandler = { [weak self, weak next] _, _ in
            MainActor.assumeIsolated {
                guard let self, let next, self.running, !self.sleeping,
                      self.generation == generation, self.controller === next else { return }
                self.pollInput(now: self.now)
            }
        }
        set(.ready)
    }

    /// A Bluetooth controller powers itself off after a quiet spell. Writing
    /// its light bar counts as host activity; the colour change is too small to see.
    private var nudged = false
    func nudge() {
        guard running, !sleeping, connection == .ready, let light = controller?.light else { return }
        nudged.toggle()
        light.color = GCColor(red: 0, green: 0.02, blue: nudged ? 0.42 : 0.40)
    }

    func suspend() {
        guard running, !sleeping else { return }
        sleeping = true; detach(); set(.waiting)
    }

    func resume() {
        guard running, sleeping else { return }
        sleeping = false; refreshControllers()
    }

    func pollInput(now: TimeInterval) {
        guard running, !sleeping, connection == .ready, let gamepad = controller?.extendedGamepad else { return }
        deliver(decoder.consume(Self.sample(gamepad), now: now), now: now)
        deliver(decoder.repeats(now: now), now: now)
        if let motion = touchpadDecoder.consume(readTouchpad(gamepad), now: now) {
            diagnostics.pointerMovements &+= 1
            onPointerMotion?(motion)
        }
    }

    private func detach() {
        generation &+= 1
        controller?.extendedGamepad?.valueChangedHandler = nil
        controller = nil
        deliver(decoder.reset(), now: now)
        touchpadDecoder.reset()
        diagnostics.selectedName = nil; diagnostics.touchpadAvailable = false
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter,
                         handler: @escaping (GameControllerInputSource, Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { if let self { handler(self, notification) } }
        }
        observers.append((center, token))
    }

    private func deliver(_ events: [GameControllerTransition], now: TimeInterval) {
        for event in events {
            diagnostics.events &+= 1
            onEvent?(AU05Event(control: event.control, phase: event.phase, sequence: diagnostics.events, uptime: now))
        }
    }

    private func set(_ value: AU05Connection) {
        guard connection != value else { return }
        connection = value; onConnection?(value)
    }

    private static func touchpadButton(_ gamepad: GCExtendedGamepad) -> GCControllerButtonInput? {
        if let profile = gamepad as? GCDualSenseGamepad { return profile.touchpadButton }
        if let profile = gamepad as? GCDualShockGamepad { return profile.touchpadButton }
        return nil
    }

    static func touchpadContact(_ gamepad: GCExtendedGamepad) -> ControllerTouchpadDecoder.Contact? {
        let pad: GCControllerDirectionPad?
        if let profile = gamepad as? GCDualSenseGamepad { pad = profile.touchpadPrimary }
        else if let profile = gamepad as? GCDualShockGamepad { pad = profile.touchpadPrimary }
        else { pad = nil }
        guard let pad else { return nil }
        let x = pad.xAxis.value, y = pad.yAxis.value
        // The legacy profile has no contact flag: macOS reports (0, 0) when
        // lifted. The exact center also re-anchors instead of jumping.
        guard x != 0 || y != 0 else { return nil }
        return .init(x: x, y: y)
    }

    static func sample(_ gamepad: GCExtendedGamepad) -> GameControllerDecoder.Sample {
        var buttons: [AU05Control: Bool] = [
            .ok: gamepad.buttonA.isPressed, .escape: gamepad.buttonB.isPressed,
            .dial: gamepad.buttonX.isPressed, .voice: gamepad.buttonY.isPressed,
            .left: gamepad.rightShoulder.isPressed, .right: gamepad.rightTrigger.isPressed,
            .l1: gamepad.leftShoulder.isPressed, .l2: gamepad.leftTrigger.isPressed,
            .dpadUp: gamepad.dpad.up.isPressed, .dpadDown: gamepad.dpad.down.isPressed,
            .dpadLeft: gamepad.dpad.left.isPressed, .dpadRight: gamepad.dpad.right.isPressed,
            .options: gamepad.buttonMenu.isPressed,
            .create: gamepad.buttonOptions?.isPressed ?? false,
            .home: gamepad.buttonHome?.isPressed ?? false,
            .leftStickPress: gamepad.leftThumbstickButton?.isPressed ?? false,
            .rightStickPress: gamepad.rightThumbstickButton?.isPressed ?? false,
            .touchpad: touchpadButton(gamepad)?.isPressed ?? false
        ]
        // Some controllers expose a separate Share button instead of Options.
        if let share = gamepad.buttons[GCInputButtonShare] { buttons[.create] = buttons[.create] == true || share.isPressed }
        return GameControllerDecoder.Sample(buttons: buttons, axes: [
            .leftX: gamepad.leftThumbstick.xAxis.value, .leftY: gamepad.leftThumbstick.yAxis.value,
            .rightX: gamepad.rightThumbstick.xAxis.value, .rightY: gamepad.rightThumbstick.yAxis.value
        ])
    }
}
