import XCTest
import AU05Device
@testable import VibeKeyBridge

final class DeviceInputTests: XCTestCase {
    func testRemappingLatchesUntilReleaseAndCanDisableAControl() {
        var mappings = InputMappings()
        mappings.bindings["voice"] = "ok"
        XCTAssertEqual(mappings.route(.voice, phase: .down).first?.0, .ok)
        mappings.bindings["voice"] = "escape"
        XCTAssertEqual(mappings.route(.voice, phase: .up).first?.0, .ok)
        mappings.bindings["right"] = "disabled"
        XCTAssertTrue(mappings.route(.right, phase: .pulse).isEmpty)
    }
    func testMultiplePhysicalKeysSharingVoiceHaveOneRelease() {
        var mappings = InputMappings()
        mappings.bindings["ok"] = "voice"
        XCTAssertEqual(mappings.route(.voice, phase: .down).count, 1)
        XCTAssertTrue(mappings.route(.ok, phase: .down).isEmpty)
        XCTAssertTrue(mappings.route(.voice, phase: .up).isEmpty)
        XCTAssertEqual(mappings.route(.ok, phase: .cancel).first?.1, .cancel)
        XCTAssertTrue(mappings.route(.ok, phase: .up).isEmpty)
    }
    func testFnCancellationAlwaysReleasesAndDemoNeverInjects() async {
        await MainActor.run {
            let runtime = BridgeRuntime()
            var sent: [Bool] = []; runtime.dictation.send = { sent.append($0) }
            runtime.dictation.setHeld(true); runtime.dictation.setHeld(true)
            runtime.handle(.voice, phase: .cancel)
            XCTAssertEqual(sent, [true, false])
            runtime.demo = true
            runtime.handle(.voice, phase: .down); runtime.handle(.voice, phase: .up)
            XCTAssertEqual(sent, [true, false])
            runtime.stop()
        }
    }
}

@MainActor
private final class FakeHID: HIDEventSource {
    var connection: AU05Connection = .stopped
    var onConnection: ((AU05Connection) -> Void)?
    var onEvent: ((AU05Event) -> Void)?
    func start() { connection = .ready; onConnection?(.ready) }
    func stop() { connection = .stopped; onConnection?(.stopped) }
    func emit(_ control: AU05Control, _ phase: AU05Phase) {
        onEvent?(AU05Event(control: control, phase: phase, sequence: 1, uptime: 1))
    }
}

extension DeviceInputTests {
    func testCaptureDisplaysPhysicalMicrophoneWithoutInjectingFn() async {
        await MainActor.run {
            let input = FakeHID(), runtime = BridgeRuntime(source: input)
            var injected: [Bool] = []; runtime.dictation.send = { injected.append($0) }
            runtime.captureOnly = true; runtime.start(demo: true)
            input.emit(.voice, .down)
            XCTAssertTrue(runtime.snapshot.pressed.contains(.voice))
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("采集物理事件", "Capture physical input"))
            input.emit(.voice, .up)
            XCTAssertFalse(runtime.snapshot.pressed.contains(.voice))
            XCTAssertTrue(injected.isEmpty)
            runtime.stop()
        }
    }
    @MainActor
    func testPhysicalRotationHighlightExpiresInMappedMode() async throws {
        let input = FakeHID(), runtime = BridgeRuntime(source: input)
        runtime.start(demo: true)
        input.emit(.right, .pulse)
        XCTAssertTrue(runtime.snapshot.pressed.contains(.right))
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(runtime.snapshot.pressed.contains(.right))
        runtime.stop()
    }
    @MainActor
    func testPhysicalStickRemainsHeldThroughRepeatDelayAndClearsAtCenter() async throws {
        let input = FakeHID(), runtime = BridgeRuntime(source: input)
        runtime.captureOnly = true
        runtime.start(demo: true)
        input.emit(.rightStickDown, .down)
        input.emit(.rightStickDown, .pulse)
        XCTAssertTrue(runtime.snapshot.pressed.contains(.rightStickDown))
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(runtime.snapshot.pressed.contains(.rightStickDown))
        input.emit(.rightStickDown, .up)
        XCTAssertFalse(runtime.snapshot.pressed.contains(.rightStickDown))
        input.emit(.rightStickUp, .down)
        input.emit(.rightStickUp, .pulse)
        input.stop()
        XCTAssertTrue(runtime.snapshot.pressed.isEmpty)
        runtime.stop()
    }
    func testDeviceDisconnectClearsHeldVisualsAndGeneratedFn() async {
        await MainActor.run {
            let input = FakeHID(), runtime = BridgeRuntime(source: input)
            var injected: [Bool] = []; runtime.dictation.send = { injected.append($0) }
            runtime.captureOnly = true; runtime.start(demo: true)
            input.emit(.dial, .down); input.emit(.voice, .down)
            runtime.dictation.setHeld(true)
            input.stop()
            XCTAssertTrue(runtime.snapshot.pressed.isEmpty)
            XCTAssertEqual(injected, [true, false])
            runtime.stop()
        }
    }
}

extension DeviceInputTests {
    private func isolatedTemplates() -> DeviceTemplateStore {
        let name = "VibeWand.RuntimeTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        addTeardownBlock { preferences.removePersistentDomain(forName: name) }
        return DeviceTemplateStore(defaults: preferences)
    }

    func testTemplateReplacementReleasesKeysAndDetachesOldSource() async throws {
        let templates = isolatedTemplates()
        try await MainActor.run {
            let input = FakeHID(), runtime = BridgeRuntime(source: input, templates: templates,
                sourceFactory: { _, template in UnconfiguredHIDSource(template: template.template) })
            var fn: [Bool] = [], keys: [(UInt16, Bool)] = []
            runtime.dictation.send = { fn.append($0) }
            runtime.applicationSwitcher.send = { code, down, _ in keys.append((code, down)) }
            runtime.start(demo: true)
            input.emit(.dial, .down); input.emit(.dial, .up) // Pending single click.
            runtime.dictation.setHeld(true)
            runtime.applicationSwitcher.begin()
            try runtime.selectTemplate(.dualSense)
            XCTAssertEqual(fn, [true, false])
            XCTAssertFalse(runtime.applicationSwitcher.active)
            XCTAssertEqual(keys.last?.0, 55)
            XCTAssertEqual(keys.last?.1, false)
            XCTAssertNil(input.onEvent)
            XCTAssertNil(input.onConnection)
            XCTAssertEqual(input.connection, .stopped)
            XCTAssertFalse(runtime.snapshot.connected)
            XCTAssertTrue(runtime.snapshot.status.contains("HID"))
            XCTAssertEqual(runtime.snapshot.deviceTemplate, .dualSense)
            let action = runtime.snapshot.action
            input.emit(.voice, .down)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 2)
            XCTAssertEqual(runtime.snapshot.action, action)
            XCTAssertTrue(runtime.snapshot.pressed.isEmpty)
            runtime.stop()
        }
    }

    func testCaptureModeBlocksSimulatedAndInternalActionsAndReleasesKeys() async throws {
        let templates = isolatedTemplates()
        try await MainActor.run {
            let runtime = BridgeRuntime(source: FakeHID(), templates: templates)
            var localActions: [GestureAction] = [], fn: [Bool] = []
            runtime.onInternalAction = { localActions.append($0) }
            runtime.dictation.send = { fn.append($0) }
            var config = runtime.configuration
            config.set(.global, .ok, .single, .openSettings)
            try runtime.updateConfiguration(config)
            runtime.playDemo()
            runtime.dictation.setHeld(true)
            runtime.captureOnly = true
            let action = runtime.snapshot.action
            runtime.handle(.ok, phase: .pulse)
            runtime.handle(.voice, phase: .down)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 2)
            XCTAssertTrue(localActions.isEmpty)
            XCTAssertEqual(fn, [true, false])
            XCTAssertEqual(runtime.snapshot.action, action)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("采集物理事件", "Capture physical input"))
            runtime.stop()
        }
    }

    func testInternalActionsWorkWithoutApplicationObservationAndPersist() async throws {
        let templates = isolatedTemplates()
        try await MainActor.run {
            let runtime = BridgeRuntime(source: FakeHID(), templates: templates)
            var actions: [GestureAction] = []
            runtime.onInternalAction = { actions.append($0) }
            var config = runtime.configuration
            config.set(.global, .ok, .single, .toggleOverlay)
            try runtime.updateConfiguration(config)
            runtime.handle(.ok, phase: .pulse)
            XCTAssertEqual(actions, [.toggleOverlay])
            XCTAssertEqual(templates.configuration().action(.reading, .ok, .single), .toggleOverlay)
            XCTAssertEqual(GestureAction.toggleOverlay.category, .vibeWand)
            XCTAssertEqual(GestureAction.dictation.category, .system)
            XCTAssertEqual(GestureAction.enter.category, .application)
            runtime.stop()
        }
    }
}

extension DeviceInputTests {
    func testControllerSelectsNativeBackendWithoutProfileAndKeepsExplicitHIDOverride() async throws {
        try await MainActor.run {
            XCTAssertTrue(try BridgeRuntime.makeSource(profile: nil, template: .dualSense) is GameControllerInputSource)
            XCTAssertTrue(try BridgeRuntime.makeSource(profile: nil, template: .vibeKey) is AU05HIDClient)
            XCTAssertTrue(try BridgeRuntime.makeSource(profile: nil, template: .xiaomiRemote) is UnconfiguredHIDSource)
            let data = Data(#"{"name":"Override","match":{"vendorID":4660,"productID":1,"usagePage":1,"usage":5},"exclusiveAccess":true,"bindings":[{"usagePage":9,"usage":1,"kind":"button","control":"voice"}]}"#.utf8)
            let profile = try JSONDecoder().decode(HIDDeviceProfile.self, from: data)
            XCTAssertTrue(try BridgeRuntime.makeSource(profile: profile, template: .dualSense) is GenericHIDClient)
        }
    }

    func testSwitchingTemplateImmediatelyUpdatesHUDEvenBeforeDeviceConnects() async throws {
        let templates = isolatedTemplates()
        try await MainActor.run {
            let runtime = BridgeRuntime(source: FakeHID(), templates: templates,
                sourceFactory: { _, template in UnconfiguredHIDSource(template: template.template) })
            runtime.start(demo: true)
            var frames: [DeviceTemplateID] = []
            runtime.onSnapshot = { frames.append($0.deviceTemplate) }
            try runtime.selectTemplate(.dualSense)
            XCTAssertEqual(runtime.snapshot.deviceTemplate, .dualSense)
            XCTAssertEqual(frames.last, .dualSense)
            XCTAssertFalse(runtime.snapshot.connected)
            XCTAssertEqual(runtime.snapshot.controlActions[.rightStickUp], GestureAction.scrollDown.label)
            try runtime.selectTemplate(.xiaomiRemote)
            XCTAssertEqual(frames.last, .xiaomiRemote)
            XCTAssertEqual(runtime.snapshot.controlActions[.dial], GestureAction.contextConfirm.label)
            XCTAssertNil(runtime.snapshot.controlActions[.rightStickUp])
            var configuration = runtime.configuration
            configuration.set(.global, .dial, .hold, .dictation)
            try runtime.updateConfiguration(configuration)
            runtime.demo = true
            XCTAssertEqual(runtime.snapshot.controlActions[.dial], GestureAction.dictation.label)
            runtime.stop()
        }
    }
}
