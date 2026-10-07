import XCTest
import GameController
import AppKit
import AU05Device
@testable import VibeWandBridge

final class ControllerPointerTests: XCTestCase {
    func testTouchpadIsRelativeAndLiftNeverMovesThePointer() throws {
        var decoder = ControllerTouchpadDecoder()
        XCTAssertNil(decoder.consume(.init(x: -0.4, y: 0.2), now: 0))
        let motion = try XCTUnwrap(decoder.consume(.init(x: -0.2, y: 0.4), now: 0.02))
        XCTAssertEqual(motion.dx, 140, accuracy: 0.001)
        XCTAssertEqual(motion.dy, -70, accuracy: 0.001)
        XCTAssertNil(decoder.consume(.init(x: -0.2, y: 0.4), now: 0.04))
        XCTAssertNil(decoder.consume(nil, now: 0.06))
        XCTAssertNil(decoder.consume(.init(x: 0.8, y: -0.5), now: 0.08))
        XCTAssertNotNil(decoder.consume(.init(x: 0.7, y: -0.4), now: 0.10))
    }

    func testInvalidStaleAndDiscontinuousContactsReanchor() {
        var decoder = ControllerTouchpadDecoder()
        decoder.prime(.init(x: 0.2, y: 0.2), now: 0)
        XCTAssertNil(decoder.consume(.init(x: 0.3, y: 0.3), now: 1))
        XCTAssertNil(decoder.consume(.init(x: -0.9, y: 0.3), now: 1.02))
        XCTAssertNotNil(decoder.consume(.init(x: -0.8, y: 0.3), now: 1.04))
        XCTAssertNil(decoder.consume(.init(x: .nan, y: 0.3), now: 1.06))
        XCTAssertNil(decoder.consume(.init(x: 0.5, y: 0.3), now: 1.08))
        XCTAssertNil(decoder.consume(.init(x: 2, y: 0.3), now: 1.10))
        decoder.reset()
        XCTAssertNil(decoder.consume(.init(x: 0.6, y: 0.3), now: 1.12))
    }

    func testRelativePointerSupportsNegativeDisplayOriginsAndClampsGaps() {
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                        CGRect(x: -1200, y: 100, width: 1000, height: 800)]
        XCTAssertEqual(SystemPointer.relativeTarget(from: .init(x: 10, y: 300), motion: .init(dx: -310, dy: 30), displays: displays), .init(x: -300, y: 330))
        XCTAssertEqual(SystemPointer.relativeTarget(from: .init(x: 10, y: 300), motion: .init(dx: -60, dy: 0), displays: displays), .init(x: 0, y: 300))
        XCTAssertEqual(SystemPointer.relativeTarget(from: .init(x: 900, y: 700), motion: .init(dx: 300, dy: 300), displays: displays), .init(x: 999, y: 799))
    }

    @MainActor
    func testNativeSourceStopsTouchTrackingAcrossSleepAndDisconnect() async {
        let controller = GCController.withExtendedGamepad()
        var controllers = [controller]
        var contact: ControllerTouchpadDecoder.Contact? = nil
        let workspace = NotificationCenter()
        let source = GameControllerInputSource(controllers: { controllers }, notifications: NotificationCenter(),
            workspaceNotifications: workspace, readTouchpad: { _ in contact })
        var motions: [ControllerPointerMotion] = []
        source.onPointerMotion = { motions.append($0) }
        source.start(); defer { source.stop() }
        let time = ProcessInfo.processInfo.systemUptime
        contact = .init(x: 0.1, y: 0.1); source.pollInput(now: time)
        contact = .init(x: 0.2, y: 0.1); source.pollInput(now: time + 0.02)
        XCTAssertEqual(motions.count, 1)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        contact = .init(x: 0.5, y: 0.1); source.pollInput(now: time + 0.04)
        XCTAssertEqual(motions.count, 1)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        source.pollInput(now: time + 0.06)
        XCTAssertEqual(motions.count, 1)
        controllers = []; source.refreshControllers()
        contact = .init(x: 0.6, y: 0.1); source.pollInput(now: time + 0.08)
        XCTAssertEqual(motions.count, 1)
        XCTAssertEqual(source.diagnostics.pointerMovements, 1)
    }

    @MainActor
    func testRuntimeCaptureDemoAndStoppedInputNeverInjectPointerEvents() async throws {
        let name = "VibeWand.PointerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let templates = DeviceTemplateStore(defaults: defaults)
        try templates.select(.dualSense)
        let controller = GCController.withExtendedGamepad()
        let source = GameControllerInputSource(controllers: { [controller] }, notifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        let runtime = BridgeRuntime(source: source, templates: templates)
        var motions = 0, clicks = 0
        runtime.sendPointerMotion = { _ in motions += 1 }; runtime.sendPointerClick = { clicks += 1 }
        runtime.start(demo: true)
        source.onPointerMotion?(.init(dx: 10, dy: -10))
        runtime.handle(.touchpad, phase: .pulse)
        XCTAssertEqual(motions, 0); XCTAssertEqual(clicks, 0)
        runtime.captureOnly = true
        source.onPointerMotion?(.init(dx: 10, dy: -10))
        runtime.handle(.touchpad, phase: .pulse)
        XCTAssertEqual(motions, 0); XCTAssertEqual(clicks, 0)
        runtime.stop()
        runtime.captureOnly = false; runtime.demo = false
        source.onPointerMotion?(.init(dx: 10, dy: -10))
        XCTAssertEqual(motions, 0)
    }
}
