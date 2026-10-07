import XCTest
import AU05Device
@testable import VibeWandBridge

final class LocalizationTests: XCTestCase {
    func testLanguageDefaultsToSystemAndExplicitSelectionSurvivesRelaunch() {
        let suite = "VibeWand.LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let chinese = L10n(defaults: defaults, preferredLanguages: ["zh-Hant-HK", "en-US"])
        XCTAssertEqual(chinese.language, .zhHans)
        XCTAssertEqual(chinese.translate("设置", "Settings"), "设置")
        chinese.language = .english
        XCTAssertEqual(defaults.string(forKey: L10n.storageKey), AppLanguage.english.rawValue)
        XCTAssertEqual(L10n(defaults: defaults, preferredLanguages: ["zh-CN"]).language, .english)

        defaults.set("obsolete-value", forKey: L10n.storageKey)
        XCTAssertEqual(L10n(defaults: defaults, preferredLanguages: ["fr-FR", "zh-CN"]).language, .english)
        XCTAssertEqual(L10n(defaults: defaults, preferredLanguages: []).language, .english)
    }

    func testLanguageChangeNotificationFollowsPersistenceAndIgnoresNoOp() {
        let suite = "VibeWand.LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = L10n(defaults: defaults, preferredLanguages: ["en-US"])
        var persistedValues: [String?] = []
        let observer = NotificationCenter.default.addObserver(forName: L10n.languageDidChange,
            object: localization, queue: nil) { _ in
                persistedValues.append(defaults.string(forKey: L10n.storageKey))
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        localization.language = .zhHans
        localization.language = .zhHans
        XCTAssertEqual(persistedValues, [AppLanguage.zhHans.rawValue])
    }

    func testLanguageSwitchUpdatesCatalogAndHUDWithoutChangingBindingsOrAXMatching() async throws {
        try await MainActor.run {
            let previousLanguage = L10n.shared.language
            let previousPreference = UserDefaults.standard.string(forKey: L10n.storageKey)
            defer {
                L10n.shared.language = previousLanguage
                UserDefaults.standard.set(previousPreference, forKey: L10n.storageKey)
            }
            let suite = "VibeWand.LocalizationTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let runtime = BridgeRuntime(templates: DeviceTemplateStore(defaults: defaults))
            runtime.demo = true
            defer { runtime.stop() }
            var configuration = runtime.configuration
            configuration.set(.global, .rightStickPress, .single, .openSettings)
            try runtime.updateConfiguration(configuration)
            let bindings = runtime.configuration.overrides

            L10n.shared.language = .zhHans
            XCTAssertEqual(DeviceTemplateID.dualSense.template.title, "手柄")
            XCTAssertEqual(runtime.snapshot.mode, "编辑文字")
            XCTAssertEqual(GestureScope.editing.label, "编辑文字")
            L10n.shared.language = .english
            XCTAssertEqual(DeviceTemplateID.dualSense.template.title, "Controller")
            XCTAssertEqual(DeviceTemplateID.xiaomiRemote.template.title, "Remote")
            XCTAssertEqual(runtime.snapshot.mode, "Editing text")
            XCTAssertEqual(runtime.snapshot.target, "VibeWand interaction design")
            XCTAssertEqual(runtime.configuration.overrides, bindings)
            XCTAssertEqual(GestureScope.editing.label, "Editing text")
            XCTAssertEqual(ApplicationProfile.deepSeekHarness.pickerKind("模型与推理等级"), .models)
            XCTAssertEqual(ApplicationProfile.weChat.pickerKind("搜索", focusedSearch: true), .sessions)

            let labels = GestureAction.allCases.map(\.label)
                + GestureScope.allCases.map(\.label) + GestureKind.allCases.map(\.label)
                + ActionCategory.allCases.map(\.label) + DeviceControl.allCases.map(\.label)
                + ApplicationProfile.allCases.flatMap { [$0.title, $0.summary, $0.verification] }
                + DeviceTemplate.catalog.flatMap {
                    [$0.title, $0.subtitle, $0.connectionNote, $0.audioNote]
                    + $0.controls.flatMap { [$0.title, $0.detail] }
                }
                + [runtime.snapshot.mode, runtime.snapshot.action, runtime.snapshot.status,
                   HIDDeviceProfile.ProfileError.invalid.localizedDescription,
                   AU05Connection.waiting.title]
            XCTAssertFalse(labels.contains { text in
                text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
            }, "English presentation must not retain Chinese labels")
        }
    }
}
