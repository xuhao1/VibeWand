import XCTest
@testable import VibeKeyBridge

final class OverlayGuidanceTests: XCTestCase {
    func testGuideUsesEffectiveCustomGesturesAndCurrentApplication() {
        var configuration = DeviceTemplateID.dualSense.template.defaultConfiguration
        configuration.set(.editing, .dial, .single, .openSettings)
        var snapshot = HUDSnapshot()
        snapshot.deviceTemplate = .dualSense; snapshot.connected = true; snapshot.scope = .editing
        snapshot.controlHints = HUDGuidance.hints(template: DeviceTemplateID.dualSense.template, configuration: configuration, scope: .editing, profile: .browser)
        XCTAssertEqual(HUDGuidance.primary(.dial, snapshot: snapshot)?.action, .openSettings)
        XCTAssertEqual(snapshot.controlHints[.ok]?.first(where: { $0.kind == .long })?.caption, L10n.tr("下一标签页", "Next tab"))
        XCTAssertTrue(HUDGuidance.nextStep(snapshot).contains(L10n.tr("下一标签页", "Next tab")))
        XCTAssertEqual(HUDGuidance.primary(.voice, snapshot: snapshot)?.title, L10n.tr("按住 · 听写", "Hold · Dictate"))
    }

    func testGuideChangesForPickersAndDoesNotInviteActionsWhileCapturing() {
        var snapshot = HUDSnapshot()
        snapshot.deviceTemplate = .dualSense; snapshot.connected = true; snapshot.scope = .sessions
        snapshot.controlHints = HUDGuidance.hints(template: DeviceTemplateID.dualSense.template, configuration: DeviceTemplateID.dualSense.template.defaultConfiguration, scope: .sessions, profile: .codex)
        XCTAssertEqual(HUDGuidance.primary(.ok, snapshot: snapshot)?.caption, L10n.tr("确认会话", "Open chat"))
        XCTAssertEqual(HUDGuidance.primary(.escape, snapshot: snapshot)?.caption, L10n.tr("返回", "Back"))
        XCTAssertEqual(HUDGuidance.primary(.left, snapshot: snapshot)?.caption, L10n.tr("上一个", "Previous"))
        XCTAssertTrue(snapshot.controlHints[.ok]?.allSatisfy { $0.kind == .single } == true)
        snapshot.captureOnly = true
        XCTAssertEqual(HUDGuidance.nextStep(snapshot), L10n.tr("仅采集输入", "Input capture only"))
        snapshot.captureOnly = false; snapshot.connected = false
        XCTAssertEqual(HUDGuidance.nextStep(snapshot), L10n.tr("连接设备开始", "Connect to begin"))
    }
}
