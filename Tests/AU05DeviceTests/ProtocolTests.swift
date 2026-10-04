import XCTest
@testable import AU05Device

final class ProtocolTests: XCTestCase {
    func testCodecRejectsWrongFramingAndKeepsCompleteBlocks() {
        let payload: [UInt8] = [0x8b, 0x10, 0x6e, 1, 3]
        let report = AU05Codec.encode(payload)
        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(AU05Codec.decode(report), payload + Array(repeating: 0, count: 51))
        XCTAssertNil(AU05Codec.decode(Array(report.dropLast())))
        XCTAssertNil(AU05Codec.decode([0] + Array(report.dropFirst())))
    }
    func testAllButtonsDeduplicateAndCancelInsteadOfClicking() {
        var decoder = AU05KeyDecoder()
        let codes: [UInt8] = [0x6f, 0x70, 0x71, 0x6e]
        let controls: [AU05Control] = [.voice, .ok, .escape, .dial]
        for index in 0..<4 {
            let report: [UInt8] = [0x8b, 0x10, codes[index], 1, UInt8(index)]
            XCTAssertEqual(decoder.consume(report), [AU05Transition(control: controls[index], phase: .down)])
            XCTAssertTrue(decoder.consume(report).isEmpty)
        }
        let cancelled = decoder.reset()
        XCTAssertEqual(Set(cancelled.map(\.control)), Set(controls))
        XCTAssertTrue(cancelled.allSatisfy { $0.phase == .cancel })
        XCTAssertTrue(decoder.consume([0x8b, 0x10, 0x6e, 0, 3]).isEmpty)
    }
    func testTurnsAreIndependentDetentsAndWrongControlCodeIsIgnored() {
        var decoder = AU05KeyDecoder()
        for _ in 0..<3 {
            XCTAssertEqual(decoder.consume([0x8b, 0x10, 0x72, 1, 4]), [AU05Transition(control: .right, phase: .pulse)])
        }
        XCTAssertEqual(decoder.consume([0x8b, 0x10, 0x73, 1, 5]), [AU05Transition(control: .left, phase: .pulse)])
        XCTAssertTrue(decoder.consume([0x8b, 0x10, 0x72, 0, 4]).isEmpty)
        XCTAssertTrue(decoder.consume([0x8b, 0x10, 0x72, 1, 3]).isEmpty)
        XCTAssertTrue(decoder.consume([0x8b, 0x10, 0x72, 2, 4]).isEmpty)
        // Extra logical controller buttons must never expand the AU05 wire map.
        for index in UInt8(6)...UInt8.max {
            XCTAssertTrue(decoder.consume([0x8b, 0x10, 0x72, 1, index]).isEmpty)
        }
    }
    func testButtonsCannotConfirmSessionBeforeACK() {
        var gate = AU05SessionGate(); gate.begin(now: 10)
        let down = AU05Codec.encode([0x8b, 0x10, 0x6f, 1, 0])
        XCTAssertTrue(gate.receive(down, now: 11).isEmpty)
        XCTAssertFalse(gate.ready)
        _ = gate.receive(AU05Codec.encode([1, 11, 0x89, 0x10, 1]), now: 11)
        XCTAssertTrue(gate.ready)
        XCTAssertEqual(gate.receive(down, now: 12), [AU05Transition(control: .voice, phase: .down)])
        XCTAssertEqual(gate.receive(AU05Codec.encode([1, 11, 0x89, 0x10, 0]), now: 13), [AU05Transition(control: .voice, phase: .cancel)])
        XCTAssertFalse(gate.requested)
        XCTAssertTrue(gate.receive(down, now: 14).isEmpty)
    }
    func testPendingAndReadyHaveDistinctTimeouts() {
        var gate = AU05SessionGate(); gate.begin(now: 10)
        _ = gate.receive(AU05Codec.encode([6, 1, 0x23]), now: 13)
        XCTAssertTrue(gate.expired(now: 14.1)) // Heartbeat cannot waive missing ACK.
        gate.begin(now: 20)
        _ = gate.receive(AU05Codec.encode([1, 11, 0x89, 0x10, 1]), now: 21)
        XCTAssertFalse(gate.expired(now: 25))
        _ = gate.receive(AU05Codec.encode([6, 1, 0x23]), now: 25)
        XCTAssertFalse(gate.expired(now: 29))
        XCTAssertTrue(gate.expired(now: 30.1))
    }
}
