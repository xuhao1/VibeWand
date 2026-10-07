import XCTest
@testable import VibeWandBridge

final class OverlayGuidanceTests: XCTestCase {
    func testGuideUsesEffectiveCustomGesturesAndCurrentApplication() {
        var configuration = DeviceTemplateID.dualSense.template.defaultConfiguration
        configuration.set(.editing, .dial, .single, .openSettings)
        var snapshot = HUDSnapshot()
        snapshot.deviceTemplate = .dualSense; snapshot.connected = true; snapshot.scope = .editing
        snapshot.controlHints = HUDGuidance.hints(template: DeviceTemplateID.dualSense.template, configuration: configuration, scope: .editing, profile: .browser)
        XCTAssertEqual(HUDGuidance.primary(.dial, snapshot: snapshot)?.action, .openSettings)
        // In a browser L1 steps through the tabs, and the footer says so by the button's own name.
        XCTAssertEqual(HUDGuidance.primary(.l1, snapshot: snapshot)?.caption, L10n.tr("下一标签页", "Next tab"))
        XCTAssertEqual(HUDGuidance.nextStep(snapshot), "L1 · " + L10n.tr("单击 · 下一标签页", "Press · Next tab"))
        XCTAssertEqual(snapshot.controlHints[.l1]?.first(where: { $0.kind == .long })?.caption, L10n.tr("地址栏", "Address bar"))
        XCTAssertEqual(HUDGuidance.primary(.l2, snapshot: snapshot)?.title, L10n.tr("按住 · 切应用", "Hold · Switch apps"))
        XCTAssertEqual(HUDGuidance.primary(.r2, snapshot: snapshot)?.title, L10n.tr("按住 · 听写", "Hold · Dictate"))
        // The face buttons carry one thing each.
        XCTAssertEqual(snapshot.controlHints[.ok]?.map(\.kind), [.single])
        XCTAssertEqual(snapshot.controlHints[.escape]?.map(\.kind), [.single])
        XCTAssertEqual(HUDGuidance.primary(.voice, snapshot: snapshot)?.title, L10n.tr("按住 · 听写", "Hold · Dictate"))
    }

    func testGuideChangesForPickersAndDoesNotInviteActionsWhileCapturing() {
        var snapshot = HUDSnapshot()
        snapshot.deviceTemplate = .dualSense; snapshot.connected = true; snapshot.scope = .sessions
        snapshot.controlHints = HUDGuidance.hints(template: DeviceTemplateID.dualSense.template, configuration: DeviceTemplateID.dualSense.template.defaultConfiguration, scope: .sessions, profile: .codex)
        // ○ confirms and × goes back in a list as everywhere else; L1 and the directions step through it.
        XCTAssertEqual(HUDGuidance.primary(.escape, snapshot: snapshot)?.caption, L10n.tr("确认会话", "Open chat"))
        XCTAssertEqual(HUDGuidance.primary(.ok, snapshot: snapshot)?.caption, L10n.tr("返回", "Back"))
        XCTAssertEqual(HUDGuidance.primary(.l1, snapshot: snapshot)?.caption, L10n.tr("下一个", "Next"))
        XCTAssertEqual(HUDGuidance.primary(.dpadUp, snapshot: snapshot)?.caption, L10n.tr("上一个", "Previous"))
        XCTAssertTrue(snapshot.controlHints[.ok]?.allSatisfy { $0.kind == .single } == true)
        XCTAssertEqual(HUDGuidance.nextStep(snapshot), "○ · " + L10n.tr("单击 · 确认会话", "Press · Open chat"))
        snapshot.captureOnly = true
        XCTAssertEqual(HUDGuidance.nextStep(snapshot), L10n.tr("仅采集输入", "Input capture only"))
        snapshot.captureOnly = false; snapshot.connected = false
        XCTAssertEqual(HUDGuidance.nextStep(snapshot), L10n.tr("连接设备开始", "Connect to begin"))
    }
}
