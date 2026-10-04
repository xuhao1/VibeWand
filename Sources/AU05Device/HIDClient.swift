import AppKit
import IOKit.hid
import Darwin

public struct AU05Diagnostics: Codable, Sendable {
    public var reports = 0
    public var acceptedReports = 0
    public var lastLength = 0
    public var lastResult: Int32 = 0
    public var senderMatches = false
    public var lastCommand: [UInt8] = []
}

/// Native macOS AU05 input SDK. All callbacks arrive on the main run loop.
/// Owns only the vendor HID interface and a temporary key-capture session.
@MainActor
public final class AU05HIDClient {
    nonisolated public static let vendorID = 0xfff1
    nonisolated public static let productID = 0x00dd
    nonisolated public static let usagePage = 0xfffc
    public private(set) var connection: AU05Connection = .stopped
    public private(set) var diagnostics = AU05Diagnostics()
    public var onConnection: ((AU05Connection) -> Void)?
    public var onEvent: ((AU05Event) -> Void)?
    /// Last battery level the handset reported, if any.
    public private(set) var battery: AU05Battery?
    private var lastBatteryQuery = -Double.infinity
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private var gate = AU05SessionGate()
    private var running = false
    private var scheduled = false
    private var sleeping = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lockFD: Int32 = -1
    private var lastAttempt = -Double.infinity
    private var lastHeartbeat = -Double.infinity
    private var sequence: UInt64 = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var studioRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "ulanzi.UlanziStudio").isEmpty
    }
    public init() {}

    public func start() {
        guard !running else { return }
        guard acquireLock() else { set(.blocked(DeviceLocalization.tr("另一实例正在使用 AU05 直连", "Another instance is using the AU05 connection"))); return }
        running = true
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID, kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: 1] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            MainActor.assumeIsolated { Unmanaged<AU05HIDClient>.fromOpaque(context).takeUnretainedValue().tick() }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, removed in
            guard let context else { return }
            MainActor.assumeIsolated {
                let client = Unmanaged<AU05HIDClient>.fromOpaque(context).takeUnretainedValue()
                if let current = client.device, CFEqual(current, removed) {
                    client.detach(restore: false); client.device = nil; client.set(.waiting)
                }
            }
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, _, _, buffer, count in
            guard let context else { return }
            MainActor.assumeIsolated {
                let client = Unmanaged<AU05HIDClient>.fromOpaque(context).takeUnretainedValue()
                client.diagnostics.reports += 1
                client.diagnostics.lastLength = count; client.diagnostics.lastResult = result
                client.diagnostics.senderMatches = client.device.map { Unmanaged.passUnretained($0).toOpaque() == sender } ?? false
                guard result == kIOReturnSuccess, count == 64 else { return }
                let report = Array(UnsafeBufferPointer(start: buffer, count: count))
                if let data = AU05Codec.decode(report) {
                    // Protocol command IDs only; never expose packet payloads.
                    client.diagnostics.lastCommand = [data[0] & 31, data[1], data[2]]
                    if let level = AU05Battery.parse(data) { client.battery = level }
                }
                guard client.diagnostics.senderMatches else { return }
                client.diagnostics.acceptedReports += 1
                client.receive(report)
            }
        }, context)
        openManager()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true; self.detach(restore: !self.studioRunning); self.closeManager(); self.set(.waiting)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false; self.lastAttempt = -Double.infinity; self.openManager()
            }
        })
        tick()
    }
    public func stop() {
        timer?.invalidate(); timer = nil
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observers.removeAll()
        detach(restore: !studioRunning); closeManager(); running = false
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
        set(.stopped)
    }
    public func reconnect() { detach(restore: !studioRunning); lastAttempt = -Double.infinity; tick() }

    private func openManager() {
        guard running, !scheduled else { return }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        scheduled = true
        let result = IOHIDManagerOpen(manager, 0) // Never seize the receiver or audio interface.
        if result != kIOReturnSuccess { set(.failed(DeviceLocalization.tr("HID 打开失败：\(result)", "Failed to open HID: \(result)"))) }
        else { set(.waiting) }
    }
    private func closeManager() {
        guard scheduled else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, 0); scheduled = false; device = nil
    }
    private func tick() {
        guard running, !sleeping, scheduled else { return }
        if studioRunning { detach(restore: false); set(.blocked(DeviceLocalization.tr("请退出 Ulanzi Studio 后使用直连", "Quit Ulanzi Studio to use the direct connection"))); return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        guard devices.count == 1, let next = devices.first else {
            detach(restore: true); device = nil
            set(devices.isEmpty ? .waiting : .blocked(DeviceLocalization.tr("检测到多个 AU05；请仅连接一个接收器", "Multiple AU05 receivers found; connect only one"))); return
        }
        if let device, !CFEqual(device, next) { detach(restore: true) }
        device = next
        if gate.expired(now: now) {
            detach(restore: true); set(.failed(DeviceLocalization.tr("AU05 未确认通道或心跳中断，正在重连", "AU05 channel or heartbeat lost; reconnecting"))); lastAttempt = now
        }
        if !gate.requested {
            guard now - lastAttempt >= 3 else { return }
            lastAttempt = now; gate.begin(now: now); set(.connecting)
            let payloads = [AU05Commands.handshake(UInt32.random(in: 0...UInt32.max)), AU05Commands.heartbeat, AU05Commands.hooks(true)]
            for payload in payloads {
                let result = send(payload)
                if result != kIOReturnSuccess { detach(restore: true); set(.failed(DeviceLocalization.tr("AU05 通信失败：\(result)", "AU05 communication failed: \(result)"))); return }
            }
            lastHeartbeat = now
        } else if now - lastHeartbeat >= 1 {
            lastHeartbeat = now
            let result = send(AU05Commands.heartbeat)
            if result != kIOReturnSuccess { detach(restore: true); set(.failed(DeviceLocalization.tr("AU05 心跳发送失败：\(result)", "AU05 heartbeat failed: \(result)"))) }
            else if gate.ready, now - lastBatteryQuery >= 60 { lastBatteryQuery = now; _ = send(AU05Commands.batteryQuery) }
        }
    }
    private func receive(_ report: [UInt8]) {
        guard running, !sleeping, !studioRunning, gate.requested else { return }
        let events = gate.receive(report, now: now)
        if gate.ready { set(.ready) }
        else if !gate.requested { set(.failed(DeviceLocalization.tr("AU05 关闭了按键通道，正在重连", "AU05 input channel closed; reconnecting"))); lastAttempt = now }
        deliver(events)
    }
    private func detach(restore: Bool) {
        let requested = gate.requested
        deliver(gate.reset())
        if restore, requested, device != nil { _ = send(AU05Commands.hooks(false)) }
    }
    private func deliver(_ events: [AU05Transition]) {
        for event in events {
            sequence &+= 1
            onEvent?(AU05Event(control: event.control, phase: event.phase, sequence: sequence, uptime: now))
        }
    }
    private func send(_ payload: [UInt8]) -> IOReturn {
        guard let device else { return kIOReturnNoDevice }
        let report = AU05Codec.encode(payload)
        return report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x55, $0.baseAddress!, $0.count)
        }
    }
    private func set(_ state: AU05Connection) {
        guard state != connection else { return }
        connection = state; onConnection?(state)
    }
    private func acquireLock() -> Bool {
        let path = "/tmp/vibekey-au05-\(getuid()).lock"
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        lockFD = fd; return true
    }
}
