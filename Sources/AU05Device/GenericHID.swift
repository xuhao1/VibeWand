import AppKit
import IOKit.hid

@MainActor
public protocol HIDEventSource: AnyObject {
    var connection: AU05Connection { get }
    var onConnection: ((AU05Connection) -> Void)? { get set }
    var onEvent: ((AU05Event) -> Void)? { get set }
    func start()
    func stop()
}
extension AU05HIDClient: HIDEventSource {}

/// A profile selects one explicit interface; there is no global keyboard match.
public struct HIDDeviceProfile: Codable, Equatable, Sendable {
    public struct Match: Codable, Equatable, Sendable {
        public let vendorID: Int
        public let productID: Int
        public let usagePage: Int
        public let usage: Int
    }
    public struct Binding: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case button, pulse, relative, absolute, axis }
        public let usagePage: Int
        public let usage: Int
        public let kind: Kind
        public let control: AU05Control?
        public let inverted: Bool?
        /// Bipolar stick axis: values below/above the HID logical midpoint.
        public let negativeControl: AU05Control?
        public let positiveControl: AU05Control?
        /// Fractions of the half-range, not raw HID units. A smaller release
        /// zone provides hysteresis so center noise never creates rapid taps.
        public let deadZone: Double?
        public let releaseZone: Double?
    }
    public let name: String
    public let match: Match
    public let exclusiveAccess: Bool
    public let bindings: [Binding]
    public func validate() throws {
        guard !name.isEmpty, name.count <= 100,
              (1...65535).contains(match.vendorID), (0...65535).contains(match.productID),
              (1...65535).contains(match.usagePage), (1...65535).contains(match.usage),
              !bindings.isEmpty, bindings.count <= 64 else { throw ProfileError.invalid }
        var seen: Set<String> = []
        var axisControls: Set<AU05Control> = []
        for binding in bindings {
            guard (1...65535).contains(binding.usagePage), (1...65535).contains(binding.usage),
                  seen.insert("\(binding.usagePage):\(binding.usage)").inserted else { throw ProfileError.invalid }
            if binding.kind == .button || binding.kind == .pulse {
                guard let control = binding.control,
                      binding.kind != .button || (control != .left && control != .right && !control.isStickDirection)
                else { throw ProfileError.invalid }
            } else if binding.control != nil { throw ProfileError.invalid }
            if binding.kind == .axis {
                guard let negative = binding.negativeControl, let positive = binding.positiveControl,
                      negative.isStickDirection, positive.isStickDirection, negative != positive,
                      axisControls.insert(negative).inserted, axisControls.insert(positive).inserted,
                      (0.05...0.8).contains(binding.deadZone ?? 0.22),
                      (0...(binding.deadZone ?? 0.22)).contains(binding.releaseZone ?? 0.16)
                else { throw ProfileError.invalid }
            } else if binding.negativeControl != nil || binding.positiveControl != nil || binding.deadZone != nil || binding.releaseZone != nil {
                throw ProfileError.invalid
            }
        }
        // Keyboard/consumer interfaces produce OS keys unless seized. Requiring
        // explicit exclusive access prevents the same press reaching two paths.
        if match.usagePage == 1 || match.usagePage == 7 || match.usagePage == 12 {
            guard exclusiveAccess else { throw ProfileError.exclusiveRequired }
        }
        if match.vendorID == AU05HIDClient.vendorID && match.productID == AU05HIDClient.productID {
            throw ProfileError.useAU05
        }
    }
    public enum ProfileError: LocalizedError {
        case invalid, exclusiveRequired, useAU05
        public var errorDescription: String? {
            switch self {
            case .invalid: return DeviceLocalization.tr("设备配置缺少标识、存在重复 usage 或按键类型不合法。", "Invalid device identifiers, duplicate HID usages, or unsupported button type.")
            case .exclusiveRequired: return DeviceLocalization.tr("键盘 / Consumer 接口需要 exclusiveAccess=true，避免系统和 Bridge 重复执行。", "Keyboard / Consumer interfaces require exclusiveAccess=true to prevent duplicate input.")
            case .useAU05: return DeviceLocalization.tr("AU05 请使用内置协议，不能按通用 HID 配置接管。", "Use the built-in AU05 protocol for this device, not a generic HID profile.")
            }
        }
    }
}

struct HIDValueDecoder {
    let profile: HIDDeviceProfile
    private var values: [String: Int] = [:]
    private var held: Set<AU05Control> = []
    private struct AxisState { var control: AU05Control; var nextRepeat: TimeInterval }
    private var axes: [String: AxisState] = [:]
    static let axisRepeatDelay: TimeInterval = 0.35
    static let axisRepeatInterval: TimeInterval = 0.09
    init(profile: HIDDeviceProfile) { self.profile = profile }
    mutating func consume(page: Int, usage: Int, value: Int,
                          logicalMin: Int = 0, logicalMax: Int = 0,
                          now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [AU05Transition] {
        guard let binding = profile.bindings.first(where: { $0.usagePage == page && $0.usage == usage }) else { return [] }
        let key = "\(page):\(usage)", previous = values[key]
        values[key] = value
        switch binding.kind {
        case .axis:
            return consumeAxis(binding, key: key, value: value, logicalMin: logicalMin, logicalMax: logicalMax, now: now)
        case .button:
            guard let control = binding.control else { return [] }
            // Multiple usages can map to one logical input. Release only when
            // every physical usage assigned to that control is released.
            let down = profile.bindings.contains {
                $0.kind == .button && $0.control == control && (values["\($0.usagePage):\($0.usage)"] ?? 0) != 0
            }
            if down, held.insert(control).inserted { return [AU05Transition(control: control, phase: .down)] }
            if !down, held.remove(control) != nil { return [AU05Transition(control: control, phase: .up)] }
            return []
        case .pulse:
            guard value != 0, previous == nil || previous == 0, let control = binding.control else { return [] }
            return [AU05Transition(control: control, phase: .pulse)]
        case .relative, .absolute:
            let delta: Int
            if binding.kind == .absolute {
                guard let previous else { return [] } // Initial position is not a turn.
                let result = value.subtractingReportingOverflow(previous)
                guard !result.overflow else { return [] }
                delta = result.partialValue
            } else { delta = value }
            guard delta != 0 else { return [] }
            let left = (delta < 0) != (binding.inverted ?? false)
            // Bound pathological reports; never turn a malformed report into
            // an unbounded stream of cursor movement.
            let count = min(delta.magnitude, 32)
            return (0..<count).map { _ in AU05Transition(control: left ? .left : .right, phase: .pulse) }
        }
    }

    private mutating func consumeAxis(_ binding: HIDDeviceProfile.Binding, key: String, value: Int,
                                      logicalMin: Int, logicalMax: Int, now: TimeInterval) -> [AU05Transition] {
        let minimum = Double(logicalMin), maximum = Double(logicalMax)
        guard maximum > minimum, value >= logicalMin, value <= logicalMax else {
            // A bad range/report must stop motion, never guess an axis scale.
            return releaseAxis(key)
        }
        let midpoint = minimum + (maximum - minimum) / 2
        var normalized = (Double(value) - midpoint) / ((maximum - minimum) / 2)
        if binding.inverted == true { normalized = -normalized }
        let deadZone = binding.deadZone ?? 0.22, releaseZone = binding.releaseZone ?? 0.16
        let old = axes[key]?.control
        let next: AU05Control?
        if old == binding.negativeControl, normalized < -releaseZone { next = old }
        else if old == binding.positiveControl, normalized > releaseZone { next = old }
        else if normalized <= -deadZone { next = binding.negativeControl }
        else if normalized >= deadZone { next = binding.positiveControl }
        else { next = nil }
        guard old != next else { return [] }
        var events = releaseAxis(key)
        if let next {
            axes[key] = AxisState(control: next, nextRepeat: now + Self.axisRepeatDelay)
            held.insert(next)
            events += [AU05Transition(control: next, phase: .down), AU05Transition(control: next, phase: .pulse)]
        }
        return events
    }

    private mutating func releaseAxis(_ key: String) -> [AU05Transition] {
        guard let previous = axes.removeValue(forKey: key) else { return [] }
        held.remove(previous.control)
        return [AU05Transition(control: previous.control, phase: .up)]
    }

    /// Sticks remain active even when hardware only reports changed values.
    /// At most one repeat per active direction per tick: never catch up with a
    /// burst after the main run loop was busy or the computer was suspended.
    mutating func repeatTransitions(now: TimeInterval) -> [AU05Transition] {
        var events: [AU05Transition] = []
        for key in axes.keys.sorted() {
            guard var axis = axes[key], now >= axis.nextRepeat else { continue }
            axis.nextRepeat = now + Self.axisRepeatInterval
            axes[key] = axis
            events.append(AU05Transition(control: axis.control, phase: .pulse))
        }
        return events
    }

    mutating func reset() -> [AU05Transition] {
        let events = held.sorted { $0.rawValue < $1.rawValue }.map { AU05Transition(control: $0, phase: .cancel) }
        held.removeAll(); values.removeAll(); axes.removeAll(); return events
    }
}

@MainActor
public final class GenericHIDClient: HIDEventSource {
    public let profile: HIDDeviceProfile
    public private(set) var connection: AU05Connection = .stopped
    public var onConnection: ((AU05Connection) -> Void)?
    public var onEvent: ((AU05Event) -> Void)?
    // Discover without automatically opening devices: the selected interface
    // must be opened once, with the explicit seize option from its profile.
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
    private var device: IOHIDDevice?
    private var running = false
    private var decoder: HIDValueDecoder
    private var timer: Timer?
    private var axisTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var sequence: UInt64 = 0
    public init(profile: HIDDeviceProfile) throws {
        try profile.validate(); self.profile = profile; decoder = HIDValueDecoder(profile: profile)
    }
    public func start() {
        guard !running else { return }; running = true
        let match = profile.match
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: match.vendorID,
            kIOHIDProductIDKey: match.productID, kIOHIDPrimaryUsagePageKey: match.usagePage,
            kIOHIDPrimaryUsageKey: match.usage] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                let client = Unmanaged<GenericHIDClient>.fromOpaque(context).takeUnretainedValue()
                if let current = client.device, CFEqual(current, device) { client.detach(); client.set(.waiting) }
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        if result != kIOReturnSuccess { set(.failed(DeviceLocalization.tr("通用 HID 打开失败：\(result)", "Failed to open generic HID: \(result)"))) }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        if profile.bindings.contains(where: { $0.kind == .axis }) {
            let axisTimer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.running, !self.sleeping, self.connection == .ready else { return }
                    self.deliver(self.decoder.repeatTransitions(now: ProcessInfo.processInfo.systemUptime))
                }
            }
            self.axisTimer = axisTimer; RunLoop.main.add(axisTimer, forMode: .common)
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeping = true; self?.detach(); self?.set(.waiting) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeping = false; self?.tick() }
        })
        tick()
    }
    public func stop() {
        timer?.invalidate(); timer = nil
        axisTimer?.invalidate(); axisTimer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observers.removeAll()
        detach()
        if running {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        running = false; set(.stopped)
    }
    private func tick() {
        guard running, !sleeping else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        guard devices.count == 1, let next = devices.first else {
            detach(); set(devices.isEmpty ? .waiting : .blocked(DeviceLocalization.tr("通用配置匹配多个接口，请只连接一个目标设备", "Multiple HID interfaces match; connect only one target device"))); return
        }
        if let device, CFEqual(device, next) { return }
        detach()
        let options = profile.exclusiveAccess ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0
        let result = IOHIDDeviceOpen(next, options)
        guard result == kIOReturnSuccess else { set(.failed(DeviceLocalization.tr("无法接管目标 HID：\(result)；检查输入监测权限或设备占用", "Unable to open target HID: \(result). Check Input Monitoring permission and device use."))); return }
        device = next
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(next, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            MainActor.assumeIsolated {
                let client = Unmanaged<GenericHIDClient>.fromOpaque(context).takeUnretainedValue()
                guard client.running, !client.sleeping, client.connection == .ready, let device = client.device else { return }
                let element = IOHIDValueGetElement(value)
                guard CFEqual(IOHIDElementGetDevice(element), device) else { return }
                client.deliver(client.decoder.consume(page: Int(IOHIDElementGetUsagePage(element)),
                    usage: Int(IOHIDElementGetUsage(element)), value: IOHIDValueGetIntegerValue(value),
                    logicalMin: IOHIDElementGetLogicalMin(element), logicalMax: IOHIDElementGetLogicalMax(element)))
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(next, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        set(.ready)
    }
    private func detach() {
        deliver(decoder.reset())
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceClose(device, 0)
        }
        device = nil
    }
    private func deliver(_ transitions: [AU05Transition]) {
        for transition in transitions {
            sequence &+= 1
            onEvent?(AU05Event(control: transition.control, phase: transition.phase,
                              sequence: sequence, uptime: ProcessInfo.processInfo.systemUptime))
        }
    }
    private func set(_ state: AU05Connection) {
        guard state != connection else { return }; connection = state; onConnection?(state)
    }
}
