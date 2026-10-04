import XCTest
import AU05Device
@testable import VibeKeyBridge

final class DeviceTemplateTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let name = "VibeWand.DeviceTemplateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testPresetsHaveValidCompleteLogicalControlsAndSafeVoiceDefaults() throws {
        for template in DeviceTemplate.catalog {
            try template.defaultConfiguration.validate()
            var expected: Set<DeviceControl> = [.dial, .left, .right, .ok, .escape, .voice]
            if template.id == .dualSense {
                expected.formUnion([.l1, .l2, .leftStickPress, .rightStickPress,
                    .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
                    .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
                    .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .options, .create, .home, .touchpad, .mute])
            } else if template.id == .xiaomiRemote {
                expected.formUnion([.power, .volumeUp, .volumeDown, .home, .dpadUp, .dpadDown])
            }
            XCTAssertEqual(Set(template.controls.map(\.control)), expected)
            XCTAssertEqual(Set(template.controls.map(\.id)).count, template.controls.count)
            XCTAssertEqual(template.defaultConfiguration.action(.global, .voice, .hold), .dictation)
            XCTAssertEqual(template.defaultConfiguration.action(.global, .voice, .single), .none)
            XCTAssertTrue(template.controls.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        }
    }

    func testRemoteCenterAndMenuBehaveAsRemoteControls() {
        let config = DeviceTemplateID.xiaomiRemote.template.defaultConfiguration
        XCTAssertEqual(config.action(.reading, .dial, .single), .contextConfirm)
        XCTAssertEqual(config.action(.editing, .dial, .long), .sessions)
        XCTAssertEqual(config.action(.reading, .ok, .single), .contextDial)
        XCTAssertEqual(config.action(.reading, .ok, .long), .models)
        XCTAssertEqual(config.action(.models, .ok, .single), .confirmCandidate)
        XCTAssertEqual(config.action(.models, .dial, .long), .none)
        XCTAssertEqual(config.action(.models, .ok, .long), .none)
        XCTAssertEqual(config.action(.applications, .dial, .single), .confirmApplication)
        XCTAssertEqual(config.action(.applications, .ok, .single), .confirmApplication)
        XCTAssertEqual(config.action(.applications, .dial, .long), .none)
        XCTAssertEqual(config.action(.applications, .ok, .long), .none)
    }

    func testControllerDefaultCoversEveryOperationWithRightHandControls() {
        let template = DeviceTemplateID.dualSense.template
        let primaryControls: Set<DeviceControl> = [.left, .right, .dial, .ok, .escape, .voice]
        let rightHandControls = template.controls.filter { primaryControls.contains($0.control) }
        XCTAssertEqual(Set(rightHandControls.map(\.control)), primaryControls)
        let actions = Set(rightHandControls.flatMap { control in
            control.gestures.map { template.defaultConfiguration.action(.global, control.control, $0) }
        })
        for required in [GestureAction.contextLeft, .contextRight, .contextDial, .models,
                         .switchApplications, .contextConfirm, .deleteBackward, .escape, .dictation] {
            XCTAssertTrue(actions.contains(required), "Right-hand mapping must include \(required)")
        }
        for control in template.controls where !primaryControls.contains(control.control) && !control.control.isStickDirection && control.control != .touchpad {
            XCTAssertTrue(control.gestures.allSatisfy { template.defaultConfiguration.action(.global, control.control, $0) == .none })
        }
    }

    func testControllerStickDefaultsNavigateImmediatelyAndPreserveSavedOverrides() throws {
        let legacy = #"{"schemaVersion":1,"doubleClickInterval":0.32,"longPressInterval":0.65,"overrides":{"editing.rightStickLeft.rotate":"openSettings"}}"#
        let config = try JSONDecoder().decode(GestureConfiguration.self, from: Data(legacy.utf8))
        for stick in [[DeviceControl.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight],
                      [.rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight]] {
            XCTAssertEqual(config.action(.editing, stick[0], .rotate), .scrollDown)
            XCTAssertEqual(config.action(.reading, stick[1], .rotate), .scrollUp)
            XCTAssertEqual(config.action(.models, stick[0], .rotate), .previousCandidate)
            XCTAssertEqual(config.action(.sessions, stick[1], .rotate), .nextCandidate)
            XCTAssertEqual(config.action(.applications, stick[2], .rotate), .previousApplication)
            XCTAssertEqual(config.action(.applications, stick[3], .rotate), .nextApplication)
        }
        XCTAssertEqual(config.action(.editing, .rightStickLeft, .rotate), .openSettings)
        XCTAssertEqual(config.action(.editing, .leftStickLeft, .rotate), .contextLeft)
        let directions = DeviceTemplateID.dualSense.template.controls.filter { $0.control.isStickDirection }
        XCTAssertEqual(directions.count, 8)
        XCTAssertTrue(directions.allSatisfy { $0.gestures == [.rotate] })
    }

    func testControllerTextButtonsConfirmWithCircleAndDeleteWithSquare() {
        let config = DeviceTemplateID.dualSense.template.defaultConfiguration
        XCTAssertEqual(config.action(.editing, .escape, .single), .contextConfirm) // Circle
        XCTAssertEqual(config.action(.editing, .dial, .single), .deleteBackward) // Square
        XCTAssertEqual(config.action(.editing, .ok, .single), .escape) // Cross
        XCTAssertEqual(config.action(.reading, .ok, .double), .switchApplications)
        XCTAssertEqual(config.action(.reading, .ok, .long), .contextDial)
        XCTAssertEqual(config.action(.reading, .escape, .long), .models)
        XCTAssertEqual(config.action(.global, .touchpad, .single), .pointerClick)
        for scope in [GestureScope.sessions, .models, .efforts, .applications] {
            XCTAssertEqual(config.action(scope, .escape, .single), scope == .applications ? .confirmApplication : .confirmCandidate)
            XCTAssertEqual(config.action(scope, .ok, .single), scope == .applications ? .cancelApplication : .cancelPicker)
            XCTAssertEqual(config.action(scope, .dial, .single), .none)
            XCTAssertEqual(config.action(scope, .ok, .double), .none)
            XCTAssertEqual(config.action(scope, .escape, .long), .none)
        }
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .editing, config: config)
        XCTAssertEqual(engine.receive(.dial, phase: .up, now: 0.05, scope: .editing, config: config).map(\.action), [.deleteBackward])
        XCTAssertTrue(engine.tick(now: 1).isEmpty, "Backspace must not also open a chat or app switcher")
    }

    func testOldPresetMigrationPreservesCustomMappingsAndOnlyRunsOnce() throws {
        let defaults = isolatedDefaults()
        let old = #"{"schemaVersion":1,"selectedID":"dualSense","configurations":{"vibeKey":{"schemaVersion":1,"doubleClickInterval":0.28,"longPressInterval":0.55,"overrides":{"reading.left.rotate":"scrollUp","editing.left.rotate":"cursorRight"}},"dualSense":{"schemaVersion":1,"doubleClickInterval":0.4,"longPressInterval":0.9,"overrides":{"global.dial.single":"contextDial","global.ok.single":"openSettings","global.voice.hold":"none","reading.rightStickUp.rotate":"scrollUp","reading.rightStickDown.rotate":"toggleOverlay"}}},"profiles":{}}"#
        defaults.set(Data(old.utf8), forKey: DeviceTemplateStore.storageKey)
        let store = DeviceTemplateStore(defaults: defaults)
        let config = store.configuration()
        XCTAssertEqual(config.action(.editing, .dial, .single), .deleteBackward)
        XCTAssertEqual(config.action(.editing, .escape, .single), .contextConfirm)
        XCTAssertEqual(config.action(.editing, .ok, .single), .openSettings)
        XCTAssertEqual(config.action(.editing, .voice, .hold), .none)
        XCTAssertEqual(config.action(.reading, .rightStickUp, .rotate), .scrollDown)
        XCTAssertEqual(config.action(.reading, .rightStickDown, .rotate), .toggleOverlay)
        XCTAssertEqual(config.doubleClickInterval, 0.4)
        XCTAssertEqual(config.longPressInterval, 0.9)
        XCTAssertEqual(store.configuration(for: .vibeKey).action(.reading, .left, .rotate), .scrollDown)
        XCTAssertEqual(store.configuration(for: .vibeKey).action(.editing, .left, .rotate), .cursorRight)
        var custom = config
        custom.set(.global, .dial, .single, .contextDial)
        try store.updateConfiguration(custom)
        XCTAssertEqual(DeviceTemplateStore(defaults: defaults).configuration().action(.editing, .dial, .single), .contextDial)
    }

    func testSwitchingAndRelaunchKeepIndependentOverridesAndTimings() throws {
        let defaults = isolatedDefaults()
        let store = DeviceTemplateStore(defaults: defaults)
        var vibeKey = store.configuration()
        vibeKey.set(.reading, .dial, .single, .models)
        vibeKey.doubleClickInterval = 0.4
        try store.select(.dualSense, currentConfiguration: vibeKey)
        XCTAssertEqual(store.configuration().action(.reading, .dial, .single), .deleteBackward)
        var dualSense = store.configuration()
        dualSense.set(.reading, .dial, .single, .escape)
        try store.updateConfiguration(dualSense)
        try store.select(.xiaomiRemote)

        let restored = DeviceTemplateStore(defaults: defaults)
        XCTAssertEqual(restored.selectedID, .xiaomiRemote)
        XCTAssertEqual(restored.configuration(for: .vibeKey).action(.reading, .dial, .single), .models)
        XCTAssertEqual(restored.configuration(for: .vibeKey).doubleClickInterval, 0.4)
        XCTAssertEqual(restored.configuration(for: .dualSense).action(.reading, .dial, .single), .escape)
        XCTAssertEqual(restored.configuration().action(.reading, .dial, .single), .contextConfirm)
    }

    func testResetOnlyResetsActiveTemplateToItsOwnDefaults() throws {
        let store = DeviceTemplateStore(defaults: isolatedDefaults())
        var vibeKey = store.configuration()
        vibeKey.set(.global, .ok, .single, .escape)
        try store.select(.xiaomiRemote, currentConfiguration: vibeKey)
        var remote = store.configuration()
        remote.set(.global, .dial, .single, GestureAction.none)
        try store.updateConfiguration(remote)
        let reset = try store.resetConfiguration()
        XCTAssertEqual(reset.action(.global, .dial, .single), .contextConfirm)
        XCTAssertEqual(store.configuration(for: .vibeKey).action(.global, .ok, .single), .escape)
    }

    func testInvalidConfigurationDoesNotChangeSelectionOrSavedConfiguration() throws {
        let store = DeviceTemplateStore(defaults: isolatedDefaults())
        var invalid = store.configuration()
        invalid.doubleClickInterval = 10
        XCTAssertThrowsError(try store.select(.dualSense, currentConfiguration: invalid))
        XCTAssertThrowsError(try store.updateConfiguration(invalid))
        XCTAssertEqual(store.selectedID, .vibeKey)
        XCTAssertEqual(store.configuration().doubleClickInterval, 0.28)
    }

    func testLegacyGestureConfigurationMigratesOnceAndOnlyToVibeKey() throws {
        let defaults = isolatedDefaults()
        var legacy = GestureConfiguration()
        legacy.set(.global, .dial, .single, .models)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "gestureConfiguration")
        let store = DeviceTemplateStore(defaults: defaults)
        XCTAssertEqual(store.configuration().action(.global, .dial, .single), .models)
        XCTAssertEqual(store.configuration(for: .dualSense).action(.global, .dial, .single), .deleteBackward)
        try store.resetConfiguration()
        XCTAssertEqual(DeviceTemplateStore(defaults: defaults).configuration().action(.global, .dial, .single), .contextDial)
    }

    func testLegacyInputMappingsPreserveHoldsAndDisabledInputs() throws {
        let defaults = isolatedDefaults()
        defaults.set(Data(#"{"bindings":{"ok":"voice","voice":"disabled","left":"right"}}"#.utf8), forKey: "inputMappings")
        let config = DeviceTemplateStore(defaults: defaults).configuration()
        XCTAssertEqual(config.action(.global, .ok, .hold), .dictation)
        XCTAssertEqual(config.action(.global, .ok, .single), .none)
        XCTAssertEqual(config.action(.global, .voice, .hold), .none)
        XCTAssertEqual(config.action(.global, .left, .rotate), .contextRight)
        try config.validate()
    }

    func testImportedProfileIsScopedPersistedAndDoesNotClaimConnection() throws {
        let defaults = isolatedDefaults()
        let store = DeviceTemplateStore(defaults: defaults)
        XCTAssertEqual(store.readiness(), .builtIn)
        XCTAssertEqual(store.readiness(for: .dualSense), .automatic)
        XCTAssertTrue(store.readiness(for: .dualSense).hasInputConfiguration)
        XCTAssertFalse(DeviceTemplateID.dualSense.template.requiresHIDProfile)
        let profile = try JSONDecoder().decode(HIDDeviceProfile.self, from: Data(#"{"name":"Test interface","match":{"vendorID":4660,"productID":1,"usagePage":1,"usage":5},"exclusiveAccess":true,"bindings":[{"usagePage":9,"usage":1,"kind":"button","control":"voice"}]}"#.utf8))
        try store.setProfile(profile, for: .dualSense)
        let restored = DeviceTemplateStore(defaults: defaults)
        XCTAssertEqual(restored.profile(for: .dualSense), profile)
        XCTAssertEqual(restored.readiness(for: .dualSense), .profileConfigured)
        XCTAssertEqual(restored.readiness(for: .xiaomiRemote), .needsProfile)
        try restored.setProfile(nil, for: .dualSense)
        XCTAssertEqual(restored.readiness(for: .dualSense), .automatic)
        XCTAssertNil(restored.profile(for: .dualSense))
    }

    func testCorruptSavedEntryFallsBackWithoutLosingOtherTemplate() throws {
        let defaults = isolatedDefaults()
        let blob = #"{"schemaVersion":1,"selectedID":"xiaomiRemote","configurations":{"vibeKey":{"schemaVersion":1,"doubleClickInterval":10,"longPressInterval":0.55,"overrides":{}},"dualSense":{"schemaVersion":1,"doubleClickInterval":0.4,"longPressInterval":0.65,"overrides":{}}},"profiles":{}}"#
        defaults.set(Data(blob.utf8), forKey: DeviceTemplateStore.storageKey)
        let store = DeviceTemplateStore(defaults: defaults)
        XCTAssertEqual(store.selectedID, .xiaomiRemote)
        XCTAssertEqual(store.configuration(for: .vibeKey).doubleClickInterval, 0.28)
        XCTAssertEqual(store.configuration(for: .dualSense).doubleClickInterval, 0.4)
    }

    func testPendingSourceEmitsBlockedStatusWithoutHardwareEvents() async {
        await MainActor.run {
            let source = UnconfiguredHIDSource(template: DeviceTemplateID.xiaomiRemote.template)
            var states: [AU05Connection] = []
            var events: [AU05Event] = []
            source.onConnection = { states.append($0) }
            source.onEvent = { events.append($0) }
            source.start()
            if case .blocked(let reason) = source.connection { XCTAssertTrue(reason.contains("HID")) }
            else { XCTFail("An unconfigured preset must not claim it is ready") }
            source.stop()
            XCTAssertEqual(states.count, 2)
            XCTAssertEqual(source.connection, .stopped)
            XCTAssertTrue(events.isEmpty)
        }
    }
}
