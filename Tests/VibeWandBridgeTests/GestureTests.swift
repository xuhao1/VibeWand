import XCTest
@testable import VibeWandBridge

final class GestureTests: XCTestCase {
    private let config = GestureConfiguration()
    func testDoubleDialDoesNotAlsoOpenSession() {
        var engine = GestureEngine()
        XCTAssertTrue(engine.receive(.dial, phase: .down, now: 0, scope: .editing, config: config).isEmpty)
        XCTAssertTrue(engine.receive(.dial, phase: .up, now: 0.05, scope: .editing, config: config).isEmpty)
        XCTAssertTrue(engine.receive(.dial, phase: .down, now: 0.15, scope: .editing, config: config).isEmpty)
        let actions = engine.receive(.dial, phase: .up, now: 0.2, scope: .editing, config: config)
        XCTAssertEqual(actions.map(\.action), [.switchApplications])
        XCTAssertTrue(engine.tick(now: 1).isEmpty)
    }
    func testSecondDownSuppressesSingleEvenIfSecondReleaseIsLater() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .reading, config: config)
        _ = engine.receive(.dial, phase: .up, now: 0.05, scope: .reading, config: config)
        _ = engine.receive(.dial, phase: .down, now: 0.25, scope: .reading, config: config)
        XCTAssertTrue(engine.tick(now: 0.4).isEmpty)
        XCTAssertEqual(engine.receive(.dial, phase: .up, now: 0.5, scope: .reading, config: config).map(\.action), [.switchApplications])
    }
    func testSingleWaitsOnlyWhenDoubleIsConfigured() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .editing, config: config)
        _ = engine.receive(.dial, phase: .up, now: 0.05, scope: .editing, config: config)
        XCTAssertTrue(engine.tick(now: 0.3).isEmpty)
        XCTAssertEqual(engine.tick(now: 0.34).map(\.action), [.contextDial])
        _ = engine.receive(.ok, phase: .down, now: 1, scope: .editing, config: config)
        XCTAssertEqual(engine.receive(.ok, phase: .up, now: 1.1, scope: .editing, config: config).map(\.action), [.contextConfirm])
    }
    func testLongPressDoesNotThenClickOrDouble() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .editing, config: config)
        XCTAssertEqual(engine.tick(now: 0.6).map(\.action), [.models])
        XCTAssertTrue(engine.receive(.dial, phase: .up, now: 0.7, scope: .editing, config: config).isEmpty)
        XCTAssertTrue(engine.tick(now: 2).isEmpty)
    }
    func testHeldRotationSuppressesDialTapAndLongPress() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .editing, config: config)
        let turn = engine.receive(.left, phase: .pulse, now: 0.1, scope: .editing, config: config)
        XCTAssertEqual(turn.map(\.action), [.cursorLeft])
        XCTAssertEqual(turn.map(\.kind), [.heldLeft])
        XCTAssertTrue(engine.tick(now: 1).isEmpty)
        XCTAssertTrue(engine.receive(.dial, phase: .up, now: 1.1, scope: .editing, config: config).isEmpty)
    }
    func testCancelRemovesDueSingleWithoutManufacturingTap() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .reading, config: config)
        _ = engine.receive(.dial, phase: .up, now: 0.1, scope: .reading, config: config)
        XCTAssertTrue(engine.receive(.dial, phase: .cancel, now: 1, scope: .reading, config: config).isEmpty)
        XCTAssertTrue(engine.tick(now: 2).isEmpty)
    }
    func testResetReleasesHoldWithCancelAndDiscardsClicks() {
        var engine = GestureEngine()
        XCTAssertEqual(engine.receive(.voice, phase: .down, now: 0, scope: .reading, config: config).map(\.phase), [.down])
        _ = engine.receive(.dial, phase: .down, now: 0.1, scope: .reading, config: config)
        _ = engine.receive(.dial, phase: .up, now: 0.15, scope: .reading, config: config)
        let cancelled = engine.reset()
        XCTAssertEqual(cancelled.map(\.action), [.dictation])
        XCTAssertEqual(cancelled.map(\.phase), [.cancel])
        XCTAssertTrue(engine.tick(now: 2).isEmpty)
    }
    func testHoldConsumesShortLongAndCancelledPressesWithoutConfirming() {
        var config = config
        config.set(.global, .ok, .hold, .dictation)
        config.set(.global, .ok, .double, .switchApplications)
        config.set(.global, .ok, .long, .escape)
        for release in [InputPhase.up, .cancel] {
            for duration in [0.1, 0.9] {
                var engine = GestureEngine()
                let began = engine.receive(.ok, phase: .down, now: 0, scope: .editing, config: config)
                XCTAssertEqual(began.map(\.action), [.dictation])
                XCTAssertEqual(began.map(\.phase), [.down])
                XCTAssertTrue(engine.tick(now: duration).isEmpty)
                let ended = engine.receive(.ok, phase: release, now: duration, scope: .editing, config: config)
                XCTAssertEqual(ended.map(\.action), [.dictation])
                XCTAssertEqual(ended.map(\.phase), [release])
                XCTAssertTrue(engine.tick(now: 2).isEmpty, "Hold release must not send Confirm or a delayed click")
            }
        }
    }
    func testBeginningHoldDiscardsPendingTapBeforeAdvancingClock() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .reading, config: config)
        _ = engine.receive(.dial, phase: .up, now: 0.05, scope: .reading, config: config)
        var holdConfig = config
        holdConfig.set(.editing, .dial, .hold, .dictation)
        let began = engine.receive(.dial, phase: .down, now: 0.5, scope: .editing, config: holdConfig)
        XCTAssertEqual(began.map(\.action), [.dictation])
        XCTAssertEqual(engine.receive(.dial, phase: .cancel, now: 0.6, scope: .editing, config: holdConfig).map(\.phase), [.cancel])
        XCTAssertTrue(engine.tick(now: 2).isEmpty)
    }
    func testPulseOnlyHoldDoesNotFallThroughToClickAndNavigationStillWorks() {
        var engine = GestureEngine()
        var config = config
        config.set(.global, .ok, .hold, .dictation)
        XCTAssertTrue(engine.receive(.ok, phase: .pulse, now: 0, scope: .editing, config: config).isEmpty)
        _ = engine.receive(.ok, phase: .down, now: 0.1, scope: .editing, config: config)
        let navigation = engine.receive(.left, phase: .pulse, now: 0.2, scope: .editing, config: config)
        XCTAssertEqual(navigation.map(\.action), [.cursorLeft])
        XCTAssertEqual(navigation.map(\.kind), [.rotate])
        XCTAssertEqual(engine.receive(.ok, phase: .up, now: 0.3, scope: .editing, config: config).map(\.action), [.dictation])
        XCTAssertTrue(engine.tick(now: 2).isEmpty)
    }
    func testIndependentControllerAndRemoteNavigationDoesNotUseHiddenDialChord() {
        for template in [DeviceTemplateID.dualSense, .xiaomiRemote] {
            var engine = GestureEngine()
            var config = template.template.defaultConfiguration
            config.set(.global, .right, .rotate, .toggleOverlay)
            config.set(.global, .dial, .heldRight, .deleteBackward)
            _ = engine.receive(.dial, phase: .down, now: 0, scope: .reading, config: config, allowHeldRotation: false)
            let navigation = engine.receive(.right, phase: .pulse, now: 0.1, scope: .reading, config: config, allowHeldRotation: false)
            XCTAssertEqual(navigation.map(\.action), [.toggleOverlay])
            XCTAssertEqual(navigation.map(\.kind), [.rotate])
            let release = engine.receive(.dial, phase: .up, now: 0.2, scope: .reading, config: config, allowHeldRotation: false)
            XCTAssertEqual((release + engine.tick(now: 0.6)).map(\.action), [config.action(.reading, .dial, .single)])
        }
    }
    func testConfigurationOverridesEachGestureAndScopeIndependently() throws {
        var config = GestureConfiguration()
        config.set(.models, .left, .rotate, .scrollUp)
        config.set(.global, .dial, .double, .models)
        XCTAssertEqual(config.action(.models, .left, .rotate), .scrollUp)
        XCTAssertEqual(config.action(.editing, .left, .rotate), .cursorLeft)
        XCTAssertEqual(config.action(.editing, .dial, .double), .models)
        XCTAssertEqual(config.action(.applications, .dial, .single), .confirmApplication)
        XCTAssertEqual(config.action(.applications, .dial, .double), .none)
        XCTAssertEqual(config.action(.applications, .left, .rotate), .previousApplication)
        config.set(.models, .left, .rotate, nil)
        XCTAssertEqual(config.action(.models, .left, .rotate), .previousCandidate)
        try config.validate()
        let restored = try JSONDecoder().decode(GestureConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored.overrides, config.overrides)
    }
    func testInvalidTimingAndUnknownBindingKeysAreRejected() {
        var config = GestureConfiguration(); config.doubleClickInterval = 2
        XCTAssertThrowsError(try config.validate())
        config = GestureConfiguration(); config.overrides["global.execute.shell"] = .enter
        XCTAssertThrowsError(try config.validate())
    }
    func testApplicationConfirmationHasNoDoubleClickDelay() {
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .applications, config: config)
        XCTAssertEqual(engine.receive(.dial, phase: .up, now: 0.1, scope: .applications, config: config).map(\.action), [.confirmApplication])
    }

    func testOptionalControllerButtonsStayUnassignedUntilConfigured() throws {
        let controls: [DeviceControl] = [.l1, .l2, .r1, .r2, .leftStickPress, .rightStickPress,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .options, .create, .home, .touchpad, .mute,
            .power, .volumeUp, .volumeDown]
        for scope in GestureScope.allCases {
            for control in controls {
                // A direction's step is the one thing that comes assigned.
                for kind in GestureKind.allCases where control.direction == nil || kind != .rotate {
                    XCTAssertEqual(config.action(scope, control, kind), .none, "\(scope).\(control).\(kind)")
                }
            }
        }
        var customized = config
        customized.set(.global, .rightStickPress, .hold, .dictation)
        customized.set(.reading, .touchpad, .single, .switchApplications)
        try customized.validate()
        let restored = try JSONDecoder().decode(GestureConfiguration.self, from: JSONEncoder().encode(customized))
        var engine = GestureEngine()
        XCTAssertEqual(engine.receive(.rightStickPress, phase: .down, now: 0, scope: .reading, config: restored).map(\.action), [.dictation])
        XCTAssertEqual(engine.receive(.rightStickPress, phase: .cancel, now: 0.1, scope: .reading, config: restored).map(\.phase), [.cancel])
        XCTAssertEqual(engine.receive(.touchpad, phase: .pulse, now: 0.2, scope: .reading, config: restored).map(\.action), [.switchApplications])
        XCTAssertTrue(engine.receive(.touchpad, phase: .pulse, now: 0.3, scope: .editing, config: restored).isEmpty)
    }

    func testAllControllerButtonsCanHaveBindingsInEveryScope() throws {
        var customized = config
        for scope in GestureScope.allCases {
            for control in DeviceControl.allCases {
                for kind in [GestureKind.single, .double, .long, .hold] {
                    customized.set(scope, control, kind, .openSettings)
                }
            }
        }
        XCTAssertGreaterThan(customized.overrides.count, 200)
        try customized.validate()
        let restored = try JSONDecoder().decode(GestureConfiguration.self, from: JSONEncoder().encode(customized))
        XCTAssertEqual(restored.overrides, customized.overrides)
    }
}

extension GestureTests {
    func testAButtonsStepFiresOnTheWayDownRepeatsWhileHeldAndNeverClicks() {
        var config = DeviceTemplateID.dualSense.template.defaultConfiguration
        var engine = GestureEngine()
        let first = engine.receive(.dpadDown, phase: .down, now: 0, scope: .reading, config: config)
        XCTAssertEqual(first.map(\.action), [.scrollDown])
        XCTAssertEqual(first.map(\.kind), [.rotate])
        XCTAssertTrue(engine.tick(now: 0.34).isEmpty)
        XCTAssertEqual(engine.tick(now: 0.35).map(\.action), [.scrollDown])
        XCTAssertTrue(engine.tick(now: 0.40).isEmpty)
        XCTAssertEqual(engine.tick(now: 0.44).map(\.action), [.scrollDown])
        // A late tick steps once and never catches up.
        XCTAssertEqual(engine.tick(now: 100).count, 1)
        XCTAssertTrue(engine.tick(now: 100).isEmpty)
        XCTAssertTrue(engine.receive(.dpadDown, phase: .up, now: 100.1, scope: .reading, config: config).isEmpty)
        XCTAssertTrue(engine.tick(now: 200).isEmpty)
        // Cancelled, it stops without a last step.
        _ = engine.receive(.dpadDown, phase: .down, now: 300, scope: .reading, config: config)
        XCTAssertTrue(engine.receive(.dpadDown, phase: .cancel, now: 300.1, scope: .reading, config: config).isEmpty)
        XCTAssertTrue(engine.tick(now: 400).isEmpty)

        // Given a press of its own, a direction-pad button is that and no longer a step.
        config.set(.global, .dpadDown, .single, .enter)
        XCTAssertEqual(config.action(.reading, .dpadDown, .rotate), .none)
        XCTAssertEqual(config.action(.sessions, .dpadDown, .rotate), .none)
        XCTAssertEqual(config.action(.reading, .dpadUp, .rotate), .scrollUp)
        XCTAssertTrue(engine.receive(.dpadDown, phase: .down, now: 500, scope: .reading, config: config).isEmpty)
        XCTAssertEqual(engine.receive(.dpadDown, phase: .up, now: 500.1, scope: .reading, config: config).map(\.action), [.enter])
        // A step chosen on top of that comes first, and the press stays silent.
        config.set(.global, .dpadDown, .rotate, .scrollDown)
        XCTAssertEqual(engine.receive(.dpadDown, phase: .down, now: 600, scope: .reading, config: config).map(\.action), [.scrollDown])
        XCTAssertTrue(engine.receive(.dpadDown, phase: .up, now: 600.1, scope: .reading, config: config).isEmpty)
        XCTAssertTrue(engine.tick(now: 700).isEmpty)
        XCTAssertEqual(config.live(.reading, .dpadDown, [.rotate, .single, .long, .hold]), [.rotate, .hold])
        // And a hold comes before both.
        config.set(.global, .dpadDown, .hold, .dictation)
        XCTAssertEqual(engine.receive(.dpadDown, phase: .down, now: 800, scope: .reading, config: config).map(\.kind), [.hold])
        XCTAssertTrue(engine.tick(now: 801).isEmpty)
        XCTAssertEqual(config.live(.reading, .dpadDown, [.rotate, .single, .long, .hold]), [.hold])
    }

    func testControllerShouldersTakeEveryGestureAButtonCan() {
        var config = DeviceTemplateID.dualSense.template.defaultConfiguration
        config.commandLayer = DeviceTemplateID.dualSense.template.commandBindings
        var engine = GestureEngine()
        // L1: a press answers on release, a long press does not also press.
        XCTAssertTrue(engine.receive(.l1, phase: .down, now: 0, scope: .reading, config: config).isEmpty)
        XCTAssertEqual(engine.receive(.l1, phase: .up, now: 0.1, scope: .reading, config: config).map(\.action), [.contextDial])
        _ = engine.receive(.l1, phase: .down, now: 1, scope: .reading, config: config)
        XCTAssertEqual(engine.tick(now: 1.7).map(\.action), [.models])
        XCTAssertTrue(engine.receive(.l1, phase: .up, now: 1.8, scope: .reading, config: config).isEmpty)
        // L2 is held like ⌘Tab: down opens, up chooses.
        XCTAssertEqual(engine.receive(.l2, phase: .down, now: 2, scope: .reading, config: config).map(\.phase), [.down])
        let released = engine.receive(.l2, phase: .up, now: 2.1, scope: .applications, config: config)
        XCTAssertEqual(released.map(\.action), [.switchApplications])
        XCTAssertEqual(released.map(\.phase), [.up])
        // R1 and R2 are held to speak, however long, and let go to finish.
        for (button, action) in [(DeviceControl.r1, GestureAction.command), (.r2, .dictation)] {
            let began = engine.receive(button, phase: .down, now: 10, scope: .editing, config: config)
            XCTAssertEqual(began.map(\.action), [action])
            XCTAssertEqual(began.map(\.phase), [.down])
            XCTAssertTrue(engine.tick(now: 15).isEmpty)
            XCTAssertEqual(engine.receive(button, phase: .up, now: 15.1, scope: .editing, config: config).map(\.phase), [.up])
        }
        // R1 takes clicks like any button once its hold is given up: press, double press and long press.
        config.set(.global, .r1, .hold, GestureAction.none)
        config.set(.global, .r1, .single, .contextDial)
        config.set(.global, .r1, .double, .toggleOverlay)
        config.set(.global, .r1, .long, .models)
        _ = engine.receive(.r1, phase: .down, now: 20, scope: .reading, config: config)
        XCTAssertTrue(engine.receive(.r1, phase: .up, now: 20.05, scope: .reading, config: config).isEmpty)
        _ = engine.receive(.r1, phase: .down, now: 20.15, scope: .reading, config: config)
        XCTAssertEqual(engine.receive(.r1, phase: .up, now: 20.2, scope: .reading, config: config).map(\.action), [.toggleOverlay])
        _ = engine.receive(.r1, phase: .down, now: 21, scope: .reading, config: config)
        _ = engine.receive(.r1, phase: .up, now: 21.05, scope: .reading, config: config)
        XCTAssertEqual(engine.tick(now: 21.4).map(\.action), [.contextDial])
        _ = engine.receive(.r1, phase: .down, now: 22, scope: .reading, config: config)
        XCTAssertEqual(engine.tick(now: 22.7).map(\.action), [.models])
        XCTAssertTrue(engine.receive(.r1, phase: .up, now: 22.8, scope: .reading, config: config).isEmpty)
        // And a step, which makes it the arrow key it used to be, now with a repeat.
        config.set(.reading, .r1, .rotate, .scrollDown)
        XCTAssertEqual(engine.receive(.r1, phase: .down, now: 30, scope: .reading, config: config).map(\.action), [.scrollDown])
        XCTAssertEqual(engine.tick(now: 30.4).map(\.action), [.scrollDown])
        XCTAssertTrue(engine.receive(.r1, phase: .up, now: 30.5, scope: .reading, config: config).isEmpty)
    }
}

final class ApplicationSwitcherTests: XCTestCase {
    func testNativeCommandIsReleasedAfterConfirmAndCancel() async {
        await MainActor.run {
            let switcher = ApplicationSwitcher()
            var events: [(UInt16, Bool)] = []
            switcher.send = { code, down, _ in events.append((code, down)) }
            switcher.begin(); switcher.move(1); switcher.move(-1); switcher.confirm()
            XCTAssertFalse(switcher.active)
            XCTAssertEqual(events.filter { $0.0 == 55 }.map { $0.1 }, [true, false])
            XCTAssertEqual(events.filter { $0.0 == 48 }.count, 6)
            switcher.begin(); switcher.cancel(); switcher.cancel()
            XCTAssertFalse(switcher.active)
            XCTAssertEqual(events.filter { $0.0 == 55 }.map { $0.1 }, [true, false, true, false])
            XCTAssertEqual(events.filter { $0.0 == 53 }.count, 2)
        }
    }
    func testDemoDoubleDialSwitchesApplicationsWithoutSendingNativeKeys() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            var posted = 0; runtime.applicationSwitcher.send = { _, _, _ in posted += 1 }
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("切换应用", "Switch apps"))
            XCTAssertEqual(posted, 0)
            runtime.handle(.right, phase: .pulse)
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            XCTAssertNotEqual(runtime.snapshot.mode, L10n.tr("切换应用", "Switch apps"))
            XCTAssertEqual(posted, 0)
            runtime.stop()
        }
    }
}

extension GestureTests {
    func testStickTiltRepeatsThroughRotateBindingWithoutReleaseClickOrHeldDialGesture() {
        var customized = config
        customized.set(.global, .rightStickLeft, .rotate, .cursorLeft)
        // Imported obsolete tap bindings must not manufacture a click when a
        // continuously held axis returns to center.
        customized.set(.global, .rightStickLeft, .single, .enter)
        customized.set(.global, .rightStickLeft, .long, .models)
        customized.set(.global, .rightStickLeft, .hold, .dictation)
        var engine = GestureEngine()
        XCTAssertTrue(engine.receive(.dial, phase: .down, now: 0, scope: .reading, config: customized).isEmpty)
        XCTAssertTrue(engine.receive(.rightStickLeft, phase: .down, now: 0.1, scope: .reading, config: customized).isEmpty)
        let initial = engine.receive(.rightStickLeft, phase: .pulse, now: 0.1, scope: .reading, config: customized)
        XCTAssertEqual(initial.map(\.kind), [.rotate])
        XCTAssertEqual(initial.map(\.control), [.rightStickLeft])
        XCTAssertEqual(initial.map(\.action), [.cursorLeft])
        XCTAssertEqual(engine.receive(.rightStickLeft, phase: .pulse, now: 0.45, scope: .reading, config: customized).map(\.action), [.cursorLeft])
        _ = engine.receive(.dial, phase: .cancel, now: 0.5, scope: .reading, config: customized)
        XCTAssertTrue(engine.tick(now: 3).isEmpty)
        XCTAssertTrue(engine.receive(.rightStickLeft, phase: .up, now: 3.1, scope: .reading, config: customized).isEmpty)
        XCTAssertTrue(engine.tick(now: 4).isEmpty)
        XCTAssertTrue(engine.held.isEmpty)
    }

    func testStickCancelDropsHeldStateAndScopeChangesChooseCurrentBinding() {
        var engine = GestureEngine()
        XCTAssertTrue(engine.receive(.rightStickDown, phase: .down, now: 0, scope: .reading, config: config).isEmpty)
        XCTAssertEqual(engine.receive(.rightStickDown, phase: .pulse, now: 0, scope: .reading, config: config).map(\.action), [.scrollDown])
        XCTAssertEqual(engine.receive(.rightStickDown, phase: .pulse, now: 0.4, scope: .models, config: config).map(\.action), [.nextCandidate])
        XCTAssertTrue(engine.receive(.rightStickDown, phase: .cancel, now: 0.5, scope: .models, config: config).isEmpty)
        XCTAssertTrue(engine.held.isEmpty)
        XCTAssertTrue(engine.tick(now: 5).isEmpty)
    }

    func testPublishedDefaultPresetMatchesCompiledDefaults() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("profiles/default-gestures.json"))
        let published = try JSONDecoder().decode(GestureConfiguration.self, from: data)
        try published.validate()
        for scope in GestureScope.allCases {
            for control in [DeviceControl.dial, .left, .right, .voice, .ok, .escape] {
                let kinds: [GestureKind] = control == .left || control == .right ? [.rotate] : [.single, .double, .long, .hold]
                for kind in kinds {
                    XCTAssertEqual(published.action(scope, control, kind), config.action(scope, control, kind), "\(scope).\(control).\(kind)")
                }
            }
        }
    }
    func testEmptyingDraftImmediatelySwitchesRotationToReading() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.ok, phase: .down); runtime.handle(.ok, phase: .up)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("阅读会话", "Reading"))
            runtime.handle(.left, phase: .pulse)
            XCTAssertEqual(runtime.snapshot.action, L10n.tr("向下滚动", "Scroll down"))
            runtime.handle(.voice, phase: .down); runtime.handle(.voice, phase: .up)
            runtime.handle(.right, phase: .pulse)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("编辑文字", "Editing text"))
            XCTAssertEqual(runtime.snapshot.action, L10n.tr("光标向右一个字符", "Move cursor one character right"))
            runtime.stop()
        }
    }
}
