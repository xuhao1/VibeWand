import XCTest
@testable import VibeKeyBridge

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
        let controls: [DeviceControl] = [.l1, .l2, .leftStickPress, .rightStickPress,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .options, .create, .home, .touchpad, .mute,
            .power, .volumeUp, .volumeDown]
        for scope in GestureScope.allCases {
            for control in controls {
                for kind in GestureKind.allCases {
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
        XCTAssertEqual(engine.receive(.rightStickDown, phase: .pulse, now: 0, scope: .reading, config: config).map(\.action), [.scrollUp])
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
