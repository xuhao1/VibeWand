import Foundation
import AU05Device
import CoreAudio
import AppKit
import IOKit.hid

/// Owns the experimental audio helper while the controller-voice option is on.
/// The helper owns HID; normal reports come back here so hold/release controls
/// continue to work during microphone capture.
@MainActor
final class DualSenseMicrophoneSource: HIDEventSource {
    static let deviceUID = "local.vibewand.dualsense-mic.experimental"
    var connection: AU05Connection = .stopped { didSet { onConnection?(connection) } }
    var onConnection: ((AU05Connection) -> Void)?
    var onEvent: ((AU05Event) -> Void)?
    private var process: Process?
    private var output: Pipe?
    private var pending = Data()
    private var decoder = GameControllerDecoder()
    private var sequence: UInt64 = 0
    private var retry: Timer?
    private var stopped = true
    private var generation = 0
    private var lastReport = 0.0
    private var watchdog: Timer?

    static var supported: Bool {
        #if arch(arm64)
        return FileManager.default.isExecutableFile(atPath: helperURL.path)
        #else
        return false
        #endif
    }
    static var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VibeWandMic") }

    func start() {
        stopped = false
        guard Self.supported else {
            connection = .failed("当前构建未包含兼容的 DualSense 麦克风组件")
            return
        }
        if Self.hardwareAvailable { launch() } else { connection = .waiting; scheduleRetry() }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                if case .ready = self.connection, ProcessInfo.processInfo.systemUptime - self.lastReport > 3 {
                    self.connection = .waiting
                    self.process?.terminate()
                }
            }
        }
    }
    static var hardwareAvailable: Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x054c,
            kIOHIDProductIDKey: 0x0ce6, kIOHIDTransportKey: "Bluetooth"] as CFDictionary)
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count == 1
    }
    private func scheduleRetry() {
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopped, Self.hardwareAvailable else { return }
                self.retry?.invalidate(); self.retry = nil; self.launch()
            }
        }
    }
    private func launch() {
        guard !stopped, process == nil else { return }
        connection = .connecting
        // The earlier standalone prototype owns the same HID stream and UID.
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.vibewand.dualsense-mic.experimental")
            .forEach { _ = $0.terminate() }
        let task = Process(), pipe = Pipe()
        task.executableURL = Self.helperURL
        task.arguments = ["--headless"]
        task.standardOutput = pipe
        task.standardError = pipe
        generation += 1
        let token = generation
        output = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.pending.append(data)
                while let end = self.pending.firstIndex(of: 10) {
                    let line = String(data: self.pending[..<end], encoding: .utf8) ?? ""
                    self.pending.removeSubrange(...end)
                    self.receive(line)
                }
                if self.pending.count > 8192 { self.pending.removeAll() }
            }
        }
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.output = nil; self.process = nil; self.pending.removeAll()
                for transition in self.decoder.reset() { self.emit(transition) }
                if !self.stopped {
                    self.connection = .waiting
                    self.scheduleRetry()
                }
            }
        }
        do { try task.run(); process = task }
        catch { connection = .failed("无法启动手柄麦克风：\(error.localizedDescription)") }
    }
    private func receive(_ line: String) {
        if line.hasPrefix("CONTROL "), let report = Data(base64Encoded: String(line.dropFirst(8))) {
            receiveControl(report)
        } else if line.hasPrefix("Start failed:") || line.hasPrefix("Prepare failed:") {
            connection = .failed(line)
        }
    }
    static func sample(from report: Data) -> GameControllerDecoder.Sample? {
        guard report.count == 78, report[0] == 0x31, report[1] & 3 == 1 else { return nil }
        let state = 2
        let b0 = report[state + 7], b1 = report[state + 8], b2 = report[state + 9]
        var buttons: [AU05Control: Bool] = [:]
        let hat = b0 & 15
        buttons[.dpadUp] = [0,1,7].contains(hat)
        buttons[.dpadRight] = [1,2,3].contains(hat)
        buttons[.dpadDown] = [3,4,5].contains(hat)
        buttons[.dpadLeft] = [5,6,7].contains(hat)
        for (control, down) in [(.dial,b0 & 0x10 != 0),(.ok,b0 & 0x20 != 0),(.escape,b0 & 0x40 != 0),(.voice,b0 & 0x80 != 0),
                                (.l1,b1 & 0x01 != 0),(.left,b1 & 0x02 != 0),(.l2,report[state+4] > 32),(.right,report[state+5] > 32),
                                (.create,b1 & 0x10 != 0),(.options,b1 & 0x20 != 0),(.leftStickPress,b1 & 0x40 != 0),(.rightStickPress,b1 & 0x80 != 0),
                                (.home,b2 & 0x01 != 0),(.touchpad,b2 & 0x02 != 0),(.mute,b2 & 0x04 != 0)] as [(AU05Control,Bool)] {
            buttons[control] = down
        }
        func axis(_ index: Int) -> Float { (Float(report[state+index]) - 127.5) / 127.5 }
        return GameControllerDecoder.Sample(buttons: buttons, axes: [.leftX:axis(0),.leftY:-axis(1),.rightX:axis(2),.rightY:-axis(3)])
    }

    private func receiveControl(_ report: Data) {
        guard let sample = Self.sample(from: report) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if case .ready = connection {} else { decoder.prime(sample); connection = .ready }
        lastReport = now
        for transition in decoder.consume(sample, now: now) { emit(transition) }
        for transition in decoder.repeats(now: now) { emit(transition) }
    }
    private func emit(_ transition: GameControllerTransition) {
        sequence += 1
        onEvent?(AU05Event(control:transition.control,phase:transition.phase,sequence:sequence,uptime:ProcessInfo.processInfo.systemUptime))
    }
    func stop() {
        stopped = true; generation += 1
        retry?.invalidate();retry = nil;watchdog?.invalidate();watchdog = nil
        output?.fileHandleForReading.readabilityHandler = nil; output = nil
        process?.terminate(); process = nil
        for transition in decoder.reset() { emit(transition) }
        connection = .stopped
    }
}
