import AppKit
import XCTest
@testable import VibeWandBridge

final class ControlsCardTests: XCTestCase {
    private func snapshot(_ template: DeviceTemplateID, _ scene: GestureScope, pressed: Set<DeviceControl> = [], command: Bool = true) -> HUDSnapshot {
        var configuration = template.template.defaultConfiguration
        if command { configuration.commandLayer = template.template.commandBindings }
        var snapshot = HUDSnapshot()
        snapshot.deviceTemplate = template; snapshot.connected = true; snapshot.pressed = pressed
        snapshot.card = ControlsCardSnapshot(scene: scene, hints: HUDGuidance.hints(template: template.template,
            configuration: configuration, scope: scene, profile: .codex))
        return snapshot
    }

    func testControllerCardNamesEveryAssignedControlOnce() {
        let template = DeviceTemplateID.dualSense.template
        let slots = ControlsCardSlot.slots(for: template)
        XCTAssertEqual(Set(slots.map(\.id)).count, slots.count)
        // Every control of the layout has a label to appear on.
        XCTAssertEqual(Set(slots.flatMap(\.controls)), Set(template.controls.map(\.control)))
        let hints = snapshot(.dualSense, .editing).card!.hints
        func lines(_ id: String) -> [String] { slots.first { $0.id == id }!.lines(hints) }
        XCTAssertEqual(lines("r1"), [L10n.tr("按住 · 命令", "Hold · Command")])
        XCTAssertEqual(lines("r2"), [L10n.tr("按住 · 听写", "Hold · Dictate")])
        XCTAssertEqual(lines("l1"), [L10n.tr("选会话", "Chats"), L10n.tr("长按 · 模型 / 强度", "Long · Model / effort")])
        XCTAssertEqual(lines("l2"), [L10n.tr("按住 · 切应用", "Hold · Switch apps")])
        XCTAssertEqual(lines("dpad"), ["↑↓ " + L10n.tr("滚屏", "Scroll"), "←→ " + L10n.tr("移动光标", "Move caret")])
        XCTAssertEqual(lines("rightStick"), lines("dpad"))
        XCTAssertEqual(lines("options"), [L10n.tr("按键一览", "Controls")])
        XCTAssertTrue(lines("create").isEmpty)
        // Without a caret to move, sideways says nothing; in a list all four step through it.
        XCTAssertEqual(slots.first { $0.id == "dpad" }!.lines(snapshot(.dualSense, .reading).card!.hints), ["↑↓ " + L10n.tr("滚屏", "Scroll")])
        XCTAssertEqual(slots.first { $0.id == "dpad" }!.lines(snapshot(.dualSense, .sessions).card!.hints),
                       ["↑↓←→ " + L10n.tr("上一个 / 下一个", "Previous / next")])
        // Before command mode is set up R1 has nothing to say.
        XCTAssertTrue(slots.first { $0.id == "r1" }!.lines(snapshot(.dualSense, .reading, command: false).card!.hints).isEmpty)
    }

    @MainActor
    func testTheOpenCardTakesEveryPressTurnsItsPagesAndClosesOnBack() async throws {
        let name = "VibeWand.ControlsCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DeviceTemplateStore(defaults: defaults)
        try store.select(.dualSense)
        let runtime = BridgeRuntime(templates: store)
        runtime.demo = true
        defer { runtime.stop() }
        func tap(_ control: DeviceControl) { runtime.handle(control, phase: .down); runtime.handle(control, phase: .up) }
        let idle = runtime.snapshot.action
        XCTAssertNil(runtime.snapshot.card)
        tap(.options)
        XCTAssertEqual(runtime.snapshot.card?.scene, .editing, "It opens on the scene the app in front is in")
        // Presses that would delete and dictate light up and do nothing else.
        tap(.dial)
        XCTAssertEqual(runtime.snapshot.card?.tried, "□ · " + L10n.tr("单击 · 退格", "Press · Backspace"))
        runtime.handle(.voice, phase: .down)
        XCTAssertEqual(runtime.snapshot.card?.tried, "△ · " + L10n.tr("按住 · 听写", "Hold · Dictate"))
        runtime.handle(.voice, phase: .up)
        XCTAssertEqual(runtime.snapshot.action, idle)
        // Directions and L1 turn the pages, as they move through a list; the ends hold.
        tap(.dpadRight)
        XCTAssertEqual(runtime.snapshot.card?.scene, .sessions)
        XCTAssertEqual(runtime.snapshot.card?.hints[.l1]?.first?.action, .nextCandidate)
        tap(.l1); tap(.l1)
        XCTAssertEqual(runtime.snapshot.card?.scene, .applications)
        runtime.handle(.leftStickUp, phase: .down); runtime.handle(.leftStickUp, phase: .pulse); runtime.handle(.leftStickUp, phase: .up)
        XCTAssertEqual(runtime.snapshot.card?.scene, .sessions)
        // × closes it and gives the device back to the app.
        tap(.ok)
        XCTAssertNil(runtime.snapshot.card)
        XCTAssertEqual(runtime.snapshot.action, idle)
        tap(.dial)
        XCTAssertEqual(runtime.snapshot.action, BridgeEffect.deleteBackward.title)
        // From the menu it opens the same way; a page picked with the pointer shows, and ☰ closes it again.
        runtime.toggleCard()
        XCTAssertEqual(runtime.snapshot.card?.scene, .editing)
        runtime.showCard(.reading)
        XCTAssertEqual(runtime.snapshot.card?.scene, .reading)
        XCTAssertNil(runtime.snapshot.card?.hints[.dpadLeft]?.first)
        tap(.options)
        XCTAssertNil(runtime.snapshot.card)
    }

    @MainActor
    func testThePanelIsBuiltOnTheSystemsGlassTakesNoFocusAndShowsNothingUntilAsked() async throws {
        _ = NSApplication.shared
        var chosen: [GestureScope?] = []
        let controller = ControlsCardController { chosen.append($0) }
        // A snapshot with no card shows nothing and builds nothing on screen.
        controller.update(HUDSnapshot())
        let panel = controller.makePanel()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        let content = try XCTUnwrap(panel.contentView)
        XCTAssertEqual(content.frame.width / content.frame.height, ControlsCard.size.width / ControlsCard.size.height, accuracy: 0.01)
        XCTAssertLessThanOrEqual(content.frame.width, ControlsCard.size.width)
        XCTAssertTrue(content.acceptsFirstMouse(for: nil), "Its tabs must answer a click while another app is in front")
        content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
        func glass(_ view: NSView) -> Bool { view is CompanionBackdrop || view.subviews.contains(where: glass) }
        XCTAssertTrue(glass(content), "The live card sits on the system's glass, not on a painted imitation")
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(chosen.isEmpty)
    }

    func testEveryLayoutHasACardThatRendersWithoutAWindow() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            // VIBEWAND_CONTROLS_REVIEW=<folder> writes every card there in both languages, to be looked over.
            let review = ProcessInfo.processInfo.environment["VIBEWAND_CONTROLS_REVIEW"].map { URL(fileURLWithPath: $0) }
            let previousLanguage = L10n.shared.language, previousPreference = UserDefaults.standard.string(forKey: L10n.storageKey)
            defer { L10n.shared.language = previousLanguage; UserDefaults.standard.set(previousPreference, forKey: L10n.storageKey) }
            for language in review == nil ? [previousLanguage] : AppLanguage.allCases {
                L10n.shared.language = language
                var cards = DeviceTemplateID.allCases.flatMap { template in
                    ControlsCardSnapshot.scenes.map { (name: "\(template.rawValue)-\($0.rawValue)", snapshot: snapshot(template, $0)) }
                }
                // One more as it looks while a button is being tried.
                var tried = snapshot(.dualSense, .editing, pressed: [.l1])
                tried.card?.tried = "L1 · " + L10n.tr("长按 · 模型 / 强度", "Long · Model / effort")
                cards.append((name: "dualSense-tried", snapshot: tried))
                for card in cards {
                    let image = try XCTUnwrap(ControlsCardController.image(card.snapshot))
                    XCTAssertEqual(image.size, ControlsCard.size)
                    guard let review else { continue }
                    try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
                    let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: review.appendingPathComponent("\(card.name)-\(language.rawValue).png"))
                }
            }
        }
    }
}
