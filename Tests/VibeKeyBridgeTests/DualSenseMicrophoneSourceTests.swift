import XCTest
import AU05Device
@testable import VibeKeyBridge

final class DualSenseMicrophoneSourceTests: XCTestCase {
    private func report() -> Data {
        var data = Data(repeating: 0, count: 78)
        data[0] = 0x31
        data[1] = 1
        data[9] = 8 // Neutral D-pad.
        for index in 2...5 { data[index] = 128 }
        return data
    }

    @MainActor
    func testBluetoothVoiceShoulderMappingMatchesNativeController() throws {
        var r1 = report()
        r1[10] = 0x02
        let shoulder = try XCTUnwrap(DualSenseMicrophoneSource.sample(from: r1))
        XCTAssertEqual(shoulder.buttons[.left], true)
        XCTAssertEqual(shoulder.buttons[.right], false)

        var r2 = report()
        r2[7] = 255
        let trigger = try XCTUnwrap(DualSenseMicrophoneSource.sample(from: r2))
        XCTAssertEqual(trigger.buttons[.left], false)
        XCTAssertEqual(trigger.buttons[.right], true)

        var decoder = GameControllerDecoder()
        XCTAssertEqual(decoder.consume(shoulder, now: 0).filter { $0.control == .left },
                       [GameControllerTransition(control: .left, phase: .pulse)])
        _ = decoder.consume(try XCTUnwrap(DualSenseMicrophoneSource.sample(from: report())), now: 0.1)
        XCTAssertEqual(decoder.consume(trigger, now: 0.2).filter { $0.control == .right },
                       [GameControllerTransition(control: .right, phase: .pulse)])
    }

    @MainActor
    func testRejectsShortAndNonControlReports() {
        XCTAssertNil(DualSenseMicrophoneSource.sample(from: Data(repeating: 0, count: 77)))
        var packet = report()
        packet[1] = 2
        XCTAssertNil(DualSenseMicrophoneSource.sample(from: packet))
        packet[1] = 1
        packet[0] = 0x01
        XCTAssertNil(DualSenseMicrophoneSource.sample(from: packet))
    }
}
