import XCTest
import AppKit
import AU05Device
import GameController
@testable import VibeWandBridge

final class GameControllerInputTests: XCTestCase {
    private func transition(_ control: AU05Control, _ phase: AU05Phase) -> GameControllerTransition {
        GameControllerTransition(control: control, phase: phase)
    }

    func testAllEightStickDirectionsHaveCorrectPolarityAndRelease() {
        for axis in GameControllerDecoder.Axis.allCases {
            for (value, control) in [(Float(-0.8), axis.negative), (Float(0.8), axis.positive)] {
                var decoder = GameControllerDecoder()
                XCTAssertEqual(decoder.consume(.init(axes: [axis: value]), now: 0),
                               [transition(control, .down), transition(control, .pulse)])
                XCTAssertEqual(decoder.consume(.init(axes: [axis: 0]), now: 0.1), [transition(control, .up)])
                XCTAssertTrue(decoder.repeats(now: 100).isEmpty)
            }
        }
    }

    func testStickNoiseHysteresisAndDirectDirectionChange() {
        var decoder = GameControllerDecoder()
        XCTAssertTrue(decoder.consume(.init(axes: [.rightY: 0.2]), now: 0).isEmpty)
        XCTAssertEqual(decoder.consume(.init(axes: [.rightY: 0.3]), now: 0.1),
                       [transition(.rightStickUp, .down), transition(.rightStickUp, .pulse)])
        XCTAssertTrue(decoder.consume(.init(axes: [.rightY: 0.18]), now: 0.2).isEmpty)
        XCTAssertEqual(decoder.consume(.init(axes: [.rightY: -0.6]), now: 0.3),
                       [transition(.rightStickUp, .up), transition(.rightStickDown, .down), transition(.rightStickDown, .pulse)])
        XCTAssertEqual(decoder.consume(.init(axes: [.rightY: -0.15]), now: 0.4), [transition(.rightStickDown, .up)])
    }

    func testRepeatNeverCatchesUpAfterDelayedTick() {
        var decoder = GameControllerDecoder()
        _ = decoder.consume(.init(axes: [.leftX: -1, .rightY: 1]), now: 0)
        XCTAssertTrue(decoder.repeats(now: 0.34).isEmpty)
        XCTAssertEqual(decoder.repeats(now: 0.35), [transition(.leftStickLeft, .pulse), transition(.rightStickUp, .pulse)])
        XCTAssertEqual(decoder.repeats(now: 100), [transition(.leftStickLeft, .pulse), transition(.rightStickUp, .pulse)])
        XCTAssertTrue(decoder.repeats(now: 100).isEmpty)
        XCTAssertTrue(decoder.repeats(now: 100.01).isEmpty)
    }

    func testInvalidAxesReleaseMovement() {
        for invalid in [Float.nan, Float.infinity, Float(-2), Float(1.1)] {
            var decoder = GameControllerDecoder()
            _ = decoder.consume(.init(axes: [.leftY: 0.9]), now: 0)
            XCTAssertEqual(decoder.consume(.init(axes: [.leftY: invalid]), now: 1), [transition(.leftStickUp, .up)])
            XCTAssertTrue(decoder.repeats(now: 2).isEmpty)
        }
    }

    func testEveryButtonHasABalancedPressTheShouldersIncluded() {
        var decoder = GameControllerDecoder()
        XCTAssertEqual(decoder.consume(.init(buttons: [.voice: true]), now: 0), [transition(.voice, .down)])
        XCTAssertTrue(decoder.consume(.init(buttons: [.voice: true]), now: 0.1).isEmpty)
        XCTAssertEqual(decoder.consume(.init(), now: 0.2), [transition(.voice, .up)])
        XCTAssertEqual(decoder.consume(.init(buttons: [.r1: true, .r2: true]), now: 1),
                       [transition(.r1, .down), transition(.r2, .down)])
        XCTAssertTrue(decoder.consume(.init(buttons: [.r1: true, .r2: true]), now: 2).isEmpty)
        XCTAssertEqual(decoder.consume(.init(buttons: [.r2: true]), now: 3), [transition(.r1, .up)])
        XCTAssertEqual(decoder.consume(.init(), now: 4), [transition(.r2, .up)])
    }

    func testAttachSuppressesAlreadyHeldInputUntilReleaseAndNeutral() {
        var decoder = GameControllerDecoder()
        let held = GameControllerDecoder.Sample(buttons: [.voice: true, .r2: true], axes: [.rightY: 0.9])
        decoder.prime(held)
        XCTAssertTrue(decoder.consume(held, now: 0).isEmpty)
        XCTAssertTrue(decoder.repeats(now: 2).isEmpty)
        XCTAssertTrue(decoder.consume(.init(), now: 3).isEmpty)
        XCTAssertEqual(decoder.consume(held, now: 4), [transition(.r2, .down), transition(.voice, .down),
                       transition(.rightStickUp, .down), transition(.rightStickUp, .pulse)])
    }

    func testCancellationNeverCompletesPendingTapOrRepeats() {
        var decoder = GameControllerDecoder()
        _ = decoder.consume(.init(buttons: [.voice: true, .r1: true], axes: [.rightX: 1]), now: 0)
        XCTAssertEqual(decoder.reset(), [transition(.r1, .cancel), transition(.rightStickRight, .cancel), transition(.voice, .cancel)])
        XCTAssertTrue(decoder.repeats(now: 100).isEmpty)
        XCTAssertTrue(decoder.consume(.init(), now: 100).isEmpty)
    }

    @MainActor
    func testNativeSnapshotButtonAndAxisMapping() async throws {
        let controller = GCController.withExtendedGamepad()
        let gamepad = try XCTUnwrap(controller.extendedGamepad)
        gamepad.buttonA.setValue(1); gamepad.buttonB.setValue(1)
        gamepad.buttonX.setValue(1); gamepad.buttonY.setValue(1)
        gamepad.rightShoulder.setValue(1); gamepad.rightTrigger.setValue(1)
        gamepad.leftShoulder.setValue(1); gamepad.leftTrigger.setValue(1)
        gamepad.dpad.setValueForXAxis(-1, yAxis: 1)
        gamepad.rightThumbstick.setValueForXAxis(0.8, yAxis: -0.9)
        let sample = GameControllerInputSource.sample(gamepad)
        for control: AU05Control in [.ok, .escape, .dial, .voice, .r1, .r2, .l1, .l2, .dpadUp, .dpadLeft] {
            XCTAssertEqual(sample.buttons[control], true, control.rawValue)
        }
        XCTAssertEqual(sample.buttons[.dpadDown], false)
        XCTAssertEqual(try XCTUnwrap(sample.axes[.rightX]), 0.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(sample.axes[.rightY]), -0.9, accuracy: 0.001)
    }

    @MainActor
    func testSourceWaitsForSupportedControllerAndKeepsItsSelection() async throws {
        let first = GCController.withExtendedGamepad(), second = GCController.withExtendedGamepad()
        var connected = [GCController.withMicroGamepad()]
        let center = NotificationCenter()
        let source = GameControllerInputSource(controllers: { connected }, notifications: center,
                                               workspaceNotifications: NotificationCenter())
        var events: [AU05Event] = []
        source.onEvent = { events.append($0) }
        source.start(); defer { source.stop() }
        XCTAssertEqual(source.connection, .waiting)
        XCTAssertNil(source.connectedName)
        XCTAssertEqual(source.diagnostics.availableControllers, 1)
        XCTAssertEqual(source.diagnostics.supportedControllers, 0)
        connected += [first, second]
        center.post(name: .GCControllerDidConnect, object: first)
        XCTAssertEqual(source.connection, .ready)
        XCTAssertEqual(source.diagnostics.supportedControllers, 2)
        connected = [second, first]
        source.refreshControllers()
        first.extendedGamepad?.buttonY.setValue(1)
        source.pollInput(now: 1)
        XCTAssertEqual(events.map(\.control), [.voice])
        XCTAssertEqual(events.map(\.phase), [.down])
        events.removeAll()
        second.extendedGamepad?.buttonA.setValue(1)
        source.pollInput(now: 2)
        XCTAssertTrue(events.isEmpty, "Another controller must not inject into the selected input stream")
        connected = [second]
        center.post(name: .GCControllerDidDisconnect, object: first)
        XCTAssertEqual(events.map(\.phase), [.cancel])
        XCTAssertEqual(source.connection, .ready)
        events.removeAll()
        source.pollInput(now: 3)
        XCTAssertTrue(events.isEmpty, "A newly selected controller's already held buttons must be suppressed")
    }

    @MainActor
    func testSourceSleepDisconnectAndStopCancelHeldState() async throws {
        let controller = GCController.withExtendedGamepad()
        var connected = [controller]
        let center = NotificationCenter(), workspace = NotificationCenter()
        let source = GameControllerInputSource(controllers: { connected }, notifications: center, workspaceNotifications: workspace)
        var events: [AU05Event] = []
        source.onEvent = { events.append($0) }
        source.start(); defer { source.stop() }
        controller.extendedGamepad?.buttonY.setValue(1)
        source.pollInput(now: 1)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(source.connection, .waiting)
        XCTAssertEqual(events.map(\.phase), [.down, .cancel])
        events.removeAll()
        source.pollInput(now: 100)
        XCTAssertTrue(events.isEmpty)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(source.connection, .ready)
        source.pollInput(now: 101)
        XCTAssertTrue(events.isEmpty)
        controller.extendedGamepad?.buttonY.setValue(0)
        source.pollInput(now: 102)
        controller.extendedGamepad?.buttonY.setValue(1)
        source.pollInput(now: 103)
        connected = []
        center.post(name: .GCControllerDidDisconnect, object: controller)
        XCTAssertEqual(events.map(\.phase), [.down, .cancel])
        XCTAssertEqual(source.connection, .waiting)
        XCTAssertNil(source.connectedName)
        events.removeAll()
        controller.extendedGamepad?.buttonA.setValue(1)
        source.pollInput(now: 104)
        XCTAssertTrue(events.isEmpty)
        source.stop()
        XCTAssertEqual(source.connection, .stopped)
        connected = [controller]
        center.post(name: .GCControllerDidConnect, object: controller)
        XCTAssertEqual(source.connection, .stopped)
    }

    @MainActor
    func testStopCancelsDictationAndStickAndRejectsQueuedCallback() async throws {
        let controller = GCController.withExtendedGamepad()
        let gamepad = try XCTUnwrap(controller.extendedGamepad)
        let source = GameControllerInputSource(controllers: { [controller] }, notifications: NotificationCenter(),
                                               workspaceNotifications: NotificationCenter())
        var events: [AU05Event] = []
        source.onEvent = { events.append($0) }
        source.start()
        let queuedCallback = gamepad.valueChangedHandler
        gamepad.buttonY.setValue(1)
        gamepad.rightThumbstick.setValueForXAxis(1, yAxis: 0)
        source.pollInput(now: 1)
        events.removeAll()
        source.stop()
        XCTAssertEqual(events.map(\.control), [.rightStickRight, .voice])
        XCTAssertEqual(events.map(\.phase), [.cancel, .cancel])
        XCTAssertNil(gamepad.valueChangedHandler)
        events.removeAll()
        gamepad.buttonA.setValue(1)
        queuedCallback?(gamepad, gamepad.buttonA)
        source.pollInput(now: 10)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(source.connection, .stopped)
    }
}
