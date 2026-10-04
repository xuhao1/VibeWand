import XCTest
@testable import AU05Device

final class GenericHIDTests: XCTestCase {
    func profile(_ bindings: String, exclusive: Bool = true) throws -> HIDDeviceProfile {
        let text = """
        {"name":"Test controller","match":{"vendorID":1234,"productID":1,"usagePage":1,"usage":6},"exclusiveAccess":\(exclusive),"bindings":\(bindings)}
        """
        return try JSONDecoder().decode(HIDDeviceProfile.self, from: Data(text.utf8))
    }
    func testProfileRejectsDuplicateUsageAndUnseizedKeyboard() throws {
        let binding = #"{"usagePage":7,"usage":40,"kind":"button","control":"ok"}"#
        XCTAssertThrowsError(try profile("[\(binding),\(binding)]").validate())
        XCTAssertThrowsError(try profile("[\(binding)]", exclusive: false).validate())
        XCTAssertNoThrow(try profile("[\(binding)]").validate())
    }
    func testTwoButtonsSharingControlReleaseOnlyWhenBothAreUp() throws {
        var decoder = HIDValueDecoder(profile: try profile(#"[{"usagePage":7,"usage":40,"kind":"button","control":"ok"},{"usagePage":7,"usage":41,"kind":"button","control":"ok"}]"#))
        XCTAssertEqual(decoder.consume(page: 7, usage: 40, value: 1), [AU05Transition(control: .ok, phase: .down)])
        XCTAssertTrue(decoder.consume(page: 7, usage: 41, value: 1).isEmpty)
        XCTAssertTrue(decoder.consume(page: 7, usage: 40, value: 0).isEmpty)
        XCTAssertEqual(decoder.consume(page: 7, usage: 41, value: 0), [AU05Transition(control: .ok, phase: .up)])
    }
    func testRelativeAndAbsoluteTurnsDoNotReplayInitialPosition() throws {
        var decoder = HIDValueDecoder(profile: try profile(#"[{"usagePage":1,"usage":56,"kind":"relative","inverted":true},{"usagePage":1,"usage":48,"kind":"absolute"}]"#))
        XCTAssertEqual(decoder.consume(page: 1, usage: 56, value: 2).map(\.control), [.left, .left])
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: 99).isEmpty)
        XCTAssertEqual(decoder.consume(page: 1, usage: 48, value: 98), [AU05Transition(control: .left, phase: .pulse)])
        XCTAssertEqual(decoder.consume(page: 1, usage: 56, value: Int.min).count, 32)
        _ = decoder.reset()
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: 4).isEmpty)
    }

    func testExtendedControllerButtonsImportAndReleaseIndependently() throws {
        let controls: [AU05Control] = [.l1, .l2, .leftStickPress, .rightStickPress,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .options, .create, .home, .touchpad, .mute,
            .power, .volumeUp, .volumeDown]
        let bindings = controls.enumerated().map { index, control in
            #"{"usagePage":9,"usage":\#(index + 1),"kind":"button","control":"\#(control.rawValue)"}"#
        }.joined(separator: ",")
        let imported = try profile("[\(bindings)]")
        try imported.validate()
        let restored = try JSONDecoder().decode(HIDDeviceProfile.self, from: JSONEncoder().encode(imported))
        XCTAssertEqual(restored, imported)
        var decoder = HIDValueDecoder(profile: restored)
        for (index, control) in controls.enumerated() {
            XCTAssertEqual(decoder.consume(page: 9, usage: index + 1, value: 1),
                           [AU05Transition(control: control, phase: .down)])
        }
        XCTAssertEqual(decoder.consume(page: 9, usage: 1, value: 0), [AU05Transition(control: .l1, phase: .up)])
        let cancelled = decoder.reset()
        XCTAssertEqual(Set(cancelled.map(\.control)), Set(controls.dropFirst()))
        XCTAssertTrue(cancelled.allSatisfy { $0.phase == .cancel })
        XCTAssertTrue(decoder.consume(page: 9, usage: 2, value: 0).isEmpty)
    }

    private var stickBinding: String {
        #"[{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickRight","deadZone":0.22,"releaseZone":0.16}]"#
    }

    func testStickDeadZoneHysteresisAndReturnToCenter() throws {
        let imported = try profile(stickBinding)
        try imported.validate()
        XCTAssertEqual(try JSONDecoder().decode(HIDDeviceProfile.self, from: JSONEncoder().encode(imported)), imported)
        var decoder = HIDValueDecoder(profile: imported)
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: 128, logicalMin: 0, logicalMax: 255, now: 0).isEmpty)
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: 150, logicalMin: 0, logicalMax: 255, now: 0.1).isEmpty)
        XCTAssertEqual(decoder.consume(page: 1, usage: 48, value: 160, logicalMin: 0, logicalMax: 255, now: 0.2), [
            AU05Transition(control: .rightStickRight, phase: .down), AU05Transition(control: .rightStickRight, phase: .pulse)])
        // Dropping below the activation threshold remains held until the
        // smaller release threshold is reached, avoiding center chatter.
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: 151, logicalMin: 0, logicalMax: 255, now: 0.3).isEmpty)
        XCTAssertEqual(decoder.consume(page: 1, usage: 48, value: 147, logicalMin: 0, logicalMax: 255, now: 0.4), [
            AU05Transition(control: .rightStickRight, phase: .up)])
        XCTAssertTrue(decoder.repeatTransitions(now: 20).isEmpty)
    }

    func testStickRepeatsWhileHeldWithoutReportFloodOrCatchupBurst() throws {
        var decoder = HIDValueDecoder(profile: try profile(stickBinding))
        _ = decoder.consume(page: 1, usage: 48, value: 255, logicalMin: 0, logicalMax: 255, now: 1)
        XCTAssertTrue(decoder.repeatTransitions(now: 1.34).isEmpty)
        XCTAssertEqual(decoder.repeatTransitions(now: 1.35), [AU05Transition(control: .rightStickRight, phase: .pulse)])
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: 254, logicalMin: 0, logicalMax: 255, now: 1.36).isEmpty)
        XCTAssertTrue(decoder.repeatTransitions(now: 1.4).isEmpty)
        XCTAssertEqual(decoder.repeatTransitions(now: 100), [AU05Transition(control: .rightStickRight, phase: .pulse)])
        XCTAssertTrue(decoder.repeatTransitions(now: 100.01).isEmpty)
        XCTAssertEqual(decoder.reset(), [AU05Transition(control: .rightStickRight, phase: .cancel)])
        XCTAssertTrue(decoder.repeatTransitions(now: 200).isEmpty)
    }

    func testStickReversalReleasesOldDirectionAndRejectsInvalidRange() throws {
        var decoder = HIDValueDecoder(profile: try profile(stickBinding))
        _ = decoder.consume(page: 1, usage: 48, value: -32768, logicalMin: -32768, logicalMax: 32767, now: 0)
        XCTAssertEqual(decoder.consume(page: 1, usage: 48, value: 32767, logicalMin: -32768, logicalMax: 32767, now: 1), [
            AU05Transition(control: .rightStickLeft, phase: .up),
            AU05Transition(control: .rightStickRight, phase: .down), AU05Transition(control: .rightStickRight, phase: .pulse)])
        XCTAssertEqual(decoder.consume(page: 1, usage: 48, value: 0, logicalMin: 0, logicalMax: 0, now: 2), [
            AU05Transition(control: .rightStickRight, phase: .up)])
        XCTAssertTrue(decoder.repeatTransitions(now: 20).isEmpty)
        XCTAssertTrue(decoder.consume(page: 1, usage: 48, value: Int.max, logicalMin: 0, logicalMax: 255, now: 3).isEmpty)
    }

    func testIndependentStickAxesAndInversion() throws {
        let bindings = #"[{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickRight"},{"usagePage":1,"usage":49,"kind":"axis","negativeControl":"rightStickUp","positiveControl":"rightStickDown","inverted":true}]"#
        let imported = try profile(bindings)
        try imported.validate()
        var decoder = HIDValueDecoder(profile: imported)
        _ = decoder.consume(page: 1, usage: 48, value: 255, logicalMin: 0, logicalMax: 255, now: 0)
        XCTAssertEqual(decoder.consume(page: 1, usage: 49, value: 255, logicalMin: 0, logicalMax: 255, now: 0).map(\.control), [.rightStickUp, .rightStickUp])
        XCTAssertEqual(Set(decoder.repeatTransitions(now: 0.4).map(\.control)), [.rightStickRight, .rightStickUp])
        _ = decoder.consume(page: 1, usage: 48, value: 128, logicalMin: 0, logicalMax: 255, now: 0.5)
        XCTAssertEqual(decoder.repeatTransitions(now: 0.6), [AU05Transition(control: .rightStickUp, phase: .pulse)])
    }

    func testAxisProfilesRejectMalformedDirectionAndThresholdMappings() throws {
        for binding in [
            #"{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"ok"}"#,
            #"{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickRight","deadZone":0.1,"releaseZone":0.2}"#,
            #"{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickRight","deadZone":0}"#,
            #"{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickLeft"}"#,
            #"{"usagePage":1,"usage":48,"kind":"axis","control":"ok"}"#,
            #"{"usagePage":9,"usage":1,"kind":"button","control":"rightStickLeft"}"#
        ] { XCTAssertThrowsError(try profile("[\(binding)]").validate()) }
        let duplicated = #"[{"usagePage":1,"usage":48,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickRight"},{"usagePage":1,"usage":49,"kind":"axis","negativeControl":"rightStickLeft","positiveControl":"rightStickRight"}]"#
        XCTAssertThrowsError(try profile(duplicated).validate())
    }
}
