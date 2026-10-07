import XCTest
import AU05Device
@testable import VibeWandBridge

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
                // A controller has nothing to turn: its shoulders are buttons of their own.
                expected.subtract([.left, .right])
                expected.formUnion([.l1, .l2, .r1, .r2, .leftStickPress, .rightStickPress,
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

    func testControllerDefaultGivesEveryButtonOneJob() {
        let template = DeviceTemplateID.dualSense.template
        var config = template.defaultConfiguration
        // The right shoulder talks, the left one switches.
        XCTAssertEqual(config.action(.reading, .r2, .hold), .dictation)
        XCTAssertEqual(config.action(.reading, .r1, .hold), .none)
        XCTAssertEqual(config.action(.reading, .l1, .single), .contextDial)
        XCTAssertEqual(config.action(.reading, .l1, .long), .models)
        XCTAssertEqual(config.action(.editing, .l2, .hold), .switchApplications)
        XCTAssertEqual(config.action(.reading, .options, .single), .showControls)
        config.commandLayer = template.commandBindings
        XCTAssertEqual(config.action(.reading, .r1, .hold), .command)
        // Nothing waits out a double press, and no button but L1 hides a second job behind a long one.
        for item in template.controls {
            for scope in GestureScope.allCases {
                XCTAssertEqual(config.action(scope, item.control, .double), .none, "\(scope).\(item.control)")
                guard ![.l1, .dial].contains(item.control) else { continue }
                XCTAssertEqual(config.action(scope, item.control, .long), .none, "\(scope).\(item.control)")
            }
        }
        func reach(_ controls: Set<DeviceControl>) -> Set<GestureAction> {
            Set(template.controls.filter { controls.contains($0.control) }.flatMap { item in
                item.gestures.map { config.action(.editing, item.control, $0) }
            })
        }
        // One hand on the right side reads, speaks, corrects and sends; the left hand switches.
        let right = reach([.r1, .r2, .dial, .ok, .escape, .voice, .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight])
        for required in [GestureAction.scrollUp, .scrollDown, .cursorLeft, .cursorRight, .command, .dictation,
                         .contextConfirm, .deleteBackward, .escape] {
            XCTAssertTrue(right.contains(required), "The right hand must reach \(required)")
        }
        XCTAssertTrue(reach([.l1, .l2]).isSuperset(of: [.contextDial, .models, .switchApplications]))
        for control in [DeviceControl.leftStickPress, .rightStickPress, .create, .home, .mute] {
            let item = template.controls.first { $0.control == control }!
            XCTAssertTrue(item.gestures.allSatisfy { config.action(.global, control, $0) == .none }, control.rawValue)
        }
    }

    func testDirectionsMoveTheWayTheyPointAndPreserveSavedOverrides() throws {
        let legacy = #"{"schemaVersion":1,"doubleClickInterval":0.32,"longPressInterval":0.65,"overrides":{"editing.rightStickLeft.rotate":"openSettings"}}"#
        let config = try JSONDecoder().decode(GestureConfiguration.self, from: Data(legacy.utf8))
        // Up, down, left, right of both sticks and of the direction pad.
        for group in [[DeviceControl.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight],
                      [.rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight],
                      [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]] {
            XCTAssertEqual(config.action(.reading, group[0], .rotate), .scrollUp)
            XCTAssertEqual(config.action(.editing, group[1], .rotate), .scrollDown)
            XCTAssertEqual(config.action(.editing, group[3], .rotate), .cursorRight)
            // No draft, no caret to move.
            XCTAssertEqual(config.action(.reading, group[2], .rotate), .none)
            XCTAssertEqual(config.action(.models, group[0], .rotate), .previousCandidate)
            XCTAssertEqual(config.action(.sessions, group[1], .rotate), .nextCandidate)
            XCTAssertEqual(config.action(.efforts, group[3], .rotate), .nextCandidate)
            XCTAssertEqual(config.action(.applications, group[2], .rotate), .previousApplication)
            XCTAssertEqual(config.action(.applications, group[3], .rotate), .nextApplication)
            XCTAssertEqual(config.action(.command, group[0], .rotate), .previousCandidate)
        }
        XCTAssertEqual(config.action(.editing, .rightStickLeft, .rotate), .openSettings)
        XCTAssertEqual(config.action(.editing, .leftStickLeft, .rotate), .cursorLeft)
        let controls = DeviceTemplateID.dualSense.template.controls
        let sticks = controls.filter { $0.control.isStickDirection }
        XCTAssertEqual(sticks.count, 8)
        XCTAssertTrue(sticks.allSatisfy { $0.gestures == [.rotate] })
        // A direction-pad button is a step first, and can be given clicks or a hold instead.
        let pad = controls.filter { $0.control.direction != nil && !$0.control.isStickDirection }
        XCTAssertEqual(pad.count, 4)
        XCTAssertTrue(pad.allSatisfy { $0.gestures.first == .rotate && $0.gestures.contains(.long) && $0.gestures.contains(.hold) })
    }

    func testControllerFaceButtonsMeanTheSameInEveryScene() {
        let config = DeviceTemplateID.dualSense.template.defaultConfiguration
        XCTAssertEqual(config.action(.editing, .escape, .single), .contextConfirm) // Circle
        XCTAssertEqual(config.action(.editing, .dial, .single), .deleteBackward) // Square
        XCTAssertEqual(config.action(.editing, .dial, .long), .deleteBackward)
        XCTAssertEqual(config.action(.editing, .ok, .single), .escape) // Cross
        XCTAssertEqual(config.action(.global, .touchpad, .single), .pointerClick)
        for scope in [GestureScope.sessions, .models, .efforts, .applications] {
            let apps = scope == .applications
            XCTAssertEqual(config.action(scope, .escape, .single), apps ? .confirmApplication : .confirmCandidate)
            XCTAssertEqual(config.action(scope, .ok, .single), apps ? .cancelApplication : .cancelPicker)
            XCTAssertEqual(config.action(scope, .dial, .single), .none)
            XCTAssertEqual(config.action(scope, .dial, .long), .none)
            XCTAssertEqual(config.action(scope, .l1, .single), apps ? .nextApplication : .nextCandidate)
            // Inside an effort popover, holding L1 again continues to the model list.
            XCTAssertEqual(config.action(scope, .l1, .long), scope == .efforts ? .models : .none)
        }
        var engine = GestureEngine()
        _ = engine.receive(.dial, phase: .down, now: 0, scope: .editing, config: config)
        XCTAssertEqual(engine.receive(.dial, phase: .up, now: 0.05, scope: .editing, config: config).map(\.action), [.deleteBackward])
        XCTAssertTrue(engine.tick(now: 1).isEmpty, "Backspace must not also open a chat or app switcher")
        // × answers on release: there is no double press to wait for any more.
        _ = engine.receive(.ok, phase: .down, now: 2, scope: .reading, config: config)
        XCTAssertEqual(engine.receive(.ok, phase: .up, now: 2.05, scope: .reading, config: config).map(\.action), [.escape])
    }

    func testSavedControllerLayoutMovesToTheNewOneAndKeepsWhatTheUserChanged() throws {
        let defaults = isolatedDefaults()
        // A layout as 0.10.1 and earlier saved it, with the changes its owner had made: R1 starts and ends a command (the most
        // a button without a release could do), R2 confirms, the command key on L2 is off, and two direction-pad
        // buttons open chats and the app switcher. Also a long press of ×, and a step for R1 while reading.
        var saved = GestureConfiguration()
        saved.doubleClickInterval = 0.4; saved.longPressInterval = 0.9
        saved.overrides = DeviceTemplateStore.formerControllerPreset
        XCTAssertEqual(saved.action(.sessions, .ok, .single), .confirmCandidate)
        saved.set(.global, .left, .rotate, .command)
        saved.set(.reading, .left, .rotate, .scrollUp)
        saved.set(.global, .right, .rotate, .contextConfirm)
        saved.set(.global, .l2, .hold, GestureAction.none)
        saved.set(.global, .dpadUp, .single, .sessions)
        saved.set(.global, .dpadDown, .single, .switchApplications)
        saved.set(.global, .ok, .long, .toggleOverlay)
        let blob = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "presetRevision": 5, "selectedID": "dualSense",
            "configurations": ["dualSense": try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))], "profiles": [String: Any]()])
        defaults.set(blob, forKey: DeviceTemplateStore.storageKey)
        let store = DeviceTemplateStore(defaults: defaults)
        var config = store.configuration()
        config.commandLayer = DeviceTemplateID.dualSense.template.commandBindings
        // What R1 and R2 were given is theirs still, on the gesture that suits it, and nothing new sits beside it.
        XCTAssertEqual(config.action(.editing, .r1, .hold), .command)
        XCTAssertEqual(config.action(.reading, .r1, .rotate), .scrollUp)
        XCTAssertEqual(config.action(.editing, .r1, .rotate), .none)
        XCTAssertEqual(config.action(.editing, .r2, .single), .contextConfirm)
        XCTAssertEqual(config.action(.editing, .r2, .hold), .none, "A new hold would silence the press the user chose")
        XCTAssertNil(config.explicit(.global, .left, .rotate))
        XCTAssertNil(config.explicit(.global, .right, .rotate))
        // A button they had switched off stays off, and their direction-pad presses are not turned into steps.
        XCTAssertEqual(config.action(.reading, .l2, .hold), .none)
        XCTAssertEqual(config.action(.reading, .dpadUp, .single), .sessions)
        XCTAssertEqual(config.action(.reading, .dpadUp, .rotate), .none)
        XCTAssertEqual(config.action(.editing, .dpadDown, .single), .switchApplications)
        XCTAssertEqual(config.action(.sessions, .dpadDown, .rotate), .none)
        XCTAssertEqual(config.action(.editing, .dpadLeft, .rotate), .cursorLeft)
        XCTAssertEqual(config.action(.reading, .ok, .long), .toggleOverlay)
        // What was left as it came is now the new layout.
        XCTAssertEqual(config.action(.sessions, .escape, .single), .confirmCandidate)
        XCTAssertEqual(config.action(.sessions, .ok, .single), .cancelPicker)
        XCTAssertEqual(config.action(.reading, .ok, .double), .none)
        XCTAssertEqual(config.action(.reading, .escape, .long), .none)
        XCTAssertEqual(config.action(.efforts, .escape, .long), .none)
        XCTAssertEqual(config.action(.editing, .l1, .single), .contextDial)
        XCTAssertEqual(config.action(.editing, .l1, .long), .models)
        XCTAssertEqual(config.action(.editing, .options, .single), .showControls)
        XCTAssertEqual(config.doubleClickInterval, 0.4)
        XCTAssertEqual(config.longPressInterval, 0.9)
        // Held, the migrated command key speaks once and ends on release, where it used to toggle.
        var engine = GestureEngine()
        XCTAssertEqual(engine.receive(.r1, phase: .down, now: 0, scope: .editing, config: config).map(\.phase), [.down])
        XCTAssertTrue(engine.tick(now: 3).isEmpty)
        XCTAssertEqual(engine.receive(.r1, phase: .up, now: 3.1, scope: .editing, config: config).map(\.phase), [.up])
        // Once only: a later choice of the user's is not moved again.
        var custom = store.configuration()
        custom.set(.sessions, .ok, .single, .confirmCandidate)
        try store.updateConfiguration(custom)
        XCTAssertEqual(DeviceTemplateStore(defaults: defaults).configuration().action(.sessions, .ok, .single), .confirmCandidate)
    }

    func testLayoutsWrittenByALaterVersionLoseOnlyWhatThisOneCannotRead() throws {
        let defaults = isolatedDefaults()
        // An action this version does not have on the controller, and a button it does not have on the remote.
        let later = #"{"schemaVersion":1,"presetRevision":9,"selectedID":"dualSense","configurations":{"vibeKey":{"schemaVersion":1,"doubleClickInterval":0.4,"longPressInterval":0.55,"overrides":{"global.ok.single":"escape"}},"dualSense":{"schemaVersion":1,"doubleClickInterval":0.32,"longPressInterval":0.65,"overrides":{"global.l1.single":"teleport","global.r2.single":"contextConfirm"}},"xiaomiRemote":{"schemaVersion":1,"doubleClickInterval":0.32,"longPressInterval":0.65,"overrides":{"global.paddle.single":"enter"}}},"profiles":{}}"#
        defaults.set(Data(later.utf8), forKey: DeviceTemplateStore.storageKey)
        let store = DeviceTemplateStore(defaults: defaults)
        // The device in use and the other devices' layouts are still there.
        XCTAssertEqual(store.selectedID, .dualSense)
        XCTAssertEqual(store.configuration(for: .vibeKey).action(.reading, .ok, .single), .escape)
        XCTAssertEqual(store.configuration(for: .vibeKey).doubleClickInterval, 0.4)
        // The one binding that could not be read is gone; its neighbour is not.
        XCTAssertEqual(store.configuration().action(.reading, .r2, .single), .contextConfirm)
        XCTAssertEqual(store.configuration().action(.reading, .l1, .single), .none)
        // A layout that names a button this version does not have is given up as a whole, and only that one.
        XCTAssertEqual(store.configuration(for: .xiaomiRemote).action(.reading, .dial, .single), .contextConfirm)
    }

    func testOlderRevisionsReachTheNewLayoutThroughEveryStep() throws {
        let defaults = isolatedDefaults()
        let old = #"{"schemaVersion":1,"presetRevision":2,"selectedID":"dualSense","configurations":{"dualSense":{"schemaVersion":1,"doubleClickInterval":0.32,"longPressInterval":0.65,"overrides":{"sessions.ok.single":"cancelPicker","sessions.escape.single":"confirmCandidate","editing.ok.single":"openSettings","models.ok.single":"cancelPicker"}}},"profiles":{}}"#
        defaults.set(Data(old.utf8), forKey: DeviceTemplateStore.storageKey)
        let store = DeviceTemplateStore(defaults: defaults)
        XCTAssertEqual(store.configuration().action(.sessions, .ok, .single), .cancelPicker)
        XCTAssertEqual(store.configuration().action(.sessions, .escape, .single), .confirmCandidate)
        XCTAssertEqual(store.configuration().action(.editing, .ok, .single), .openSettings)
        XCTAssertEqual(store.configuration().action(.models, .ok, .single), .cancelPicker)
        XCTAssertEqual(store.configuration().action(.reading, .l1, .single), .contextDial)
        let custom = old.replacingOccurrences(of: "\"sessions.ok.single\":\"cancelPicker\"", with: "\"sessions.ok.single\":\"toggleGuide\"")
        defaults.set(Data(custom.utf8), forKey: DeviceTemplateStore.storageKey)
        XCTAssertEqual(DeviceTemplateStore(defaults: defaults).configuration().action(.sessions, .ok, .single), .toggleGuide)
    }

    @MainActor
    func testL1OpensChatsStepsThroughThemAndCircleConfirmsWithoutWaiting() async throws {
        let store = DeviceTemplateStore(defaults: isolatedDefaults())
        try store.select(.dualSense)
        let runtime = BridgeRuntime(templates: store)
        runtime.demo = true
        func tap(_ control: DeviceControl) { runtime.handle(control, phase: .down); runtime.handle(control, phase: .up) }
        tap(.l1)
        XCTAssertEqual(runtime.snapshot.scope, .sessions)
        XCTAssertEqual(HUDGuidance.primary(.escape, snapshot: runtime.snapshot)?.action, .confirmCandidate)
        XCTAssertTrue(HUDGuidance.nextStep(runtime.snapshot).hasPrefix("○"))
        tap(.l1)
        tap(.escape)
        XCTAssertEqual(runtime.snapshot.scope, .reading)
        XCTAssertEqual(runtime.snapshot.target, L10n.tr("修复登录问题", "Fix sign-in issue"))
        // A long press of the same button is the model picker; × leaves it.
        runtime.handle(.l1, phase: .down)
        runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 0.7)
        runtime.handle(.l1, phase: .up)
        XCTAssertEqual(runtime.snapshot.scope, .models)
        tap(.ok)
        XCTAssertEqual(runtime.snapshot.scope, .reading)
        runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertEqual(runtime.snapshot.scope, .reading)
        runtime.stop()
    }

    @MainActor
    func testDirectionPadStepsAndRepeatsAndL2HeldSwitchesApps() async throws {
        let store = DeviceTemplateStore(defaults: isolatedDefaults())
        try store.select(.dualSense)
        let runtime = BridgeRuntime(templates: store)
        runtime.demo = true
        var posted = 0; runtime.applicationSwitcher.send = { _, _, _ in posted += 1 }
        func steps() throws -> Int { try XCTUnwrap(runtime.diagnostics()["recentActions"] as? [String]).count }
        // One step on the way down, more while it stays down, none on the way up.
        runtime.handle(.dpadLeft, phase: .down)
        XCTAssertEqual(try steps(), 1)
        XCTAssertEqual(runtime.snapshot.action, L10n.tr("光标向左一个字符", "Move cursor one character left"))
        runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 0.4)
        XCTAssertEqual(try steps(), 2)
        runtime.handle(.dpadLeft, phase: .up)
        runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 5)
        XCTAssertEqual(try steps(), 2)
        // L2 held shows the apps; a direction chooses, letting go switches.
        runtime.handle(.l2, phase: .down)
        XCTAssertEqual(runtime.snapshot.scope, .applications)
        XCTAssertEqual(runtime.snapshot.mode, L10n.tr("切换应用", "Switch apps"))
        runtime.handle(.rightStickRight, phase: .down); runtime.handle(.rightStickRight, phase: .pulse); runtime.handle(.rightStickRight, phase: .up)
        XCTAssertEqual(runtime.snapshot.status, L10n.tr("演示应用 2 / 3", "Demo app 2 / 3"))
        runtime.handle(.dpadRight, phase: .down); runtime.handle(.dpadRight, phase: .up)
        XCTAssertEqual(runtime.snapshot.status, L10n.tr("演示应用 3 / 3", "Demo app 3 / 3"))
        runtime.handle(.l2, phase: .up)
        XCTAssertNotEqual(runtime.snapshot.scope, .applications)
        XCTAssertEqual(posted, 0, "The demo sends no keys")
        runtime.stop()
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
