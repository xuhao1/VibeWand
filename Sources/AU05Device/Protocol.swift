import Foundation

public enum AU05Control: String, Codable, CaseIterable, Sendable {
    case voice, ok, escape, dial, right, left
    // Additional logical controls are available to imported generic HID profiles.
    // AU05KeyDecoder continues to decode only its original six wire inputs.
    case l1, l2, leftStickPress, rightStickPress
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case options, create, home, touchpad, mute
    case power, volumeUp, volumeDown

    var isStickDirection: Bool {
        switch self {
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight: return true
        default: return false
        }
    }
}
public enum AU05Phase: String, Codable, Sendable { case down, up, pulse, cancel }
public struct AU05Event: Codable, Equatable, Sendable {
    public let control: AU05Control
    public let phase: AU05Phase
    public let sequence: UInt64
    public let uptime: TimeInterval
    public init(control: AU05Control, phase: AU05Phase, sequence: UInt64, uptime: TimeInterval) {
        self.control = control; self.phase = phase; self.sequence = sequence; self.uptime = uptime
    }
}
public enum AU05Connection: Equatable, Sendable {
    case stopped, waiting, connecting, ready, blocked(String), failed(String)
    public var title: String {
        switch self {
        case .stopped: return DeviceLocalization.tr("直连已停止", "Device connection stopped")
        case .waiting: return DeviceLocalization.tr("等待 AU05 接收器", "Waiting for device")
        case .connecting: return DeviceLocalization.tr("AU05 正在确认按键通道", "AU05 verifying input channel")
        case .ready: return DeviceLocalization.tr("AU05 直连已就绪", "Device connected")
        case .blocked(let text), .failed(let text): return text
        }
    }
}

// Codec and command formats adapted from AU05 Keys, MIT, pinned in
// third-party/README.md. Copyright (c) 2026 AU05 Keys contributors.
enum AU05Codec {
    private static let key: [UInt32] = [3399858890, 3156904557, 3394936506, 2612562890]
    static func encode(_ payload: [UInt8]) -> [UInt8] {
        precondition(payload.count <= 56)
        let plain = payload + Array(repeating: UInt8(0), count: 64 - payload.count)
        var encoded: [UInt8] = []
        for offset in stride(from: 0, to: 64, by: 8) {
            var a = word(plain, offset), b = word(plain, offset + 4), sum: UInt32 = 0
            for _ in 0..<32 {
                sum = sum &+ 0x9e3779b9
                a = a &+ (((b << 4) &+ key[0]) ^ (b &+ sum) ^ ((b >> 5) &+ key[1]))
                b = b &+ (((a << 4) &+ key[2]) ^ (a &+ sum) ^ ((a >> 5) &+ key[3]))
            }
            encoded += bytes(a) + bytes(b)
        }
        // The final encrypted block is incomplete on wire; decode only the
        // seven complete blocks. No copied buffer is read past its end.
        return [0x55] + encoded.prefix(63)
    }
    static func decode(_ report: [UInt8]) -> [UInt8]? {
        guard report.count == 64, report[0] == 0x55 else { return nil }
        var plain: [UInt8] = []
        for offset in stride(from: 1, to: 57, by: 8) {
            var a = word(report, offset), b = word(report, offset + 4), sum: UInt32 = 0xc6ef3720
            for _ in 0..<32 {
                b = b &- (((a << 4) &+ key[2]) ^ (a &+ sum) ^ ((a >> 5) &+ key[3]))
                a = a &- (((b << 4) &+ key[0]) ^ (b &+ sum) ^ ((b >> 5) &+ key[1]))
                sum = sum &- 0x9e3779b9
            }
            plain += bytes(a) + bytes(b)
        }
        return plain
    }
    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    private static func bytes(_ word: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
    }
}
enum AU05Commands {
    static let heartbeat: [UInt8] = [6, 1, 0x23, 0, 1]
    static let batteryQuery: [UInt8] = [1, 1, 2, 1]
    static func hooks(_ enabled: Bool) -> [UInt8] { [1, 11, 0x89, 4, enabled ? 1 : 0] }
    static func handshake(_ nonce: UInt32) -> [UInt8] {
        [6, 2, 5, 1, UInt8(nonce & 15)] + (0..<4).map { UInt8(truncatingIfNeeded: nonce >> ($0 * 8)) }
    }
    static func acknowledgement(_ data: [UInt8]) -> Bool? {
        guard data.count >= 5, data[0] & 31 == 1, data[1] & 15 == 11,
              data[2] == 0x89, data[3] == 0x10, data[4] <= 1 else { return nil }
        return data[4] == 1
    }
    static func isHeartbeat(_ data: [UInt8]) -> Bool {
        data.count >= 3 && data[0] & 31 == 6 && data[1] == 1 && data[2] == 0x23
    }
}

/// Battery reports, in both layouts the handset uses (reply and unsolicited).
public struct AU05Battery: Equatable, Sendable {
    public let percent: Int
    public let charging: Bool
    static func parse(_ data: [UInt8]) -> AU05Battery? {
        guard data.count >= 12 else { return nil }
        if data[0] & 0x1f == 1, data[1] & 0x0f == 1, data[2] == 2, data[3] & 0x10 != 0 {
            let voltage = Int(data[4]) | Int(data[5]) << 8, percent = Int(data[6]) | Int(data[7]) << 8
            guard percent <= 100, (2000...5000).contains(voltage) else { return nil }
            return AU05Battery(percent: percent, charging: data[10] != 0)
        }
        guard data[0] & 0x1f == 0x0b, data[1] == 0x7b, data[5] <= 100 else { return nil }
        let voltage = Int(data[2]) | Int(data[3]) << 8
        guard (2000...5000).contains(voltage) else { return nil }
        return AU05Battery(percent: Int(data[5]), charging: data[4] & 8 != 0)
    }
}

struct AU05Transition: Equatable {
    let control: AU05Control
    let phase: AU05Phase
}
struct AU05KeyDecoder {
    private(set) var held: Set<AU05Control> = []
    mutating func consume(_ data: [UInt8]) -> [AU05Transition] {
        let codes: [UInt8] = [0x6f, 0x70, 0x71, 0x6e, 0x72, 0x73]
        let controls: [AU05Control] = [.voice, .ok, .escape, .dial, .right, .left]
        guard data.count >= 5, data[0] == 0x8b, data[1] == 0x10,
              data[4] < 6, data[3] <= 1, data[2] == codes[Int(data[4])] else { return [] }
        let control = controls[Int(data[4])]
        if data[4] >= 4 { return data[3] == 1 ? [AU05Transition(control: control, phase: .pulse)] : [] }
        if data[3] == 1 {
            guard held.insert(control).inserted else { return [] }
            return [AU05Transition(control: control, phase: .down)]
        }
        guard held.remove(control) != nil else { return [] }
        return [AU05Transition(control: control, phase: .up)]
    }
    mutating func reset() -> [AU05Transition] {
        let result = held.sorted { $0.rawValue < $1.rawValue }.map { AU05Transition(control: $0, phase: .cancel) }
        held.removeAll()
        return result
    }
}

// A write acknowledgement is required before dispatch. Incoming button reports
// never promote a pending connection to ready by themselves.
struct AU05SessionGate {
    private(set) var requested = false
    private(set) var ready = false
    private(set) var requestedAt: TimeInterval = 0
    private(set) var lastReply: TimeInterval = 0
    private var decoder = AU05KeyDecoder()
    mutating func begin(now: TimeInterval) {
        _ = reset(); requested = true; requestedAt = now; lastReply = now
    }
    mutating func receive(_ report: [UInt8], now: TimeInterval) -> [AU05Transition] {
        guard requested, let data = AU05Codec.decode(report) else { return [] }
        if let enabled = AU05Commands.acknowledgement(data) {
            if enabled { ready = true; lastReply = now; return [] }
            return reset()
        }
        if AU05Commands.isHeartbeat(data) { lastReply = now; return [] }
        guard ready else { return [] }
        let events = decoder.consume(data)
        if !events.isEmpty { lastReply = now }
        return events
    }
    func expired(now: TimeInterval) -> Bool {
        requested && (ready ? now - lastReply > 5 : now - requestedAt > 4)
    }
    mutating func reset() -> [AU05Transition] {
        requested = false; ready = false
        return decoder.reset()
    }
}
