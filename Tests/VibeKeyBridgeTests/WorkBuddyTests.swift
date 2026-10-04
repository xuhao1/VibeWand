import XCTest
import AppKit
import SwiftUI
@testable import VibeKeyBridge

/// Fixtures from WorkBuddy 5.6.2's installed renderer, not a live UI test.
final class WorkBuddyTests: XCTestCase {
    let profile = ApplicationProfile.workBuddy

    func testTaskAndGlobalSearchAreScopedToWorkBuddy() {
        for hint in ["搜索任务", "Search Tasks", "全局搜索", "Global search",
                     "搜索任务、空间、产物、项目", "Search tasks, spaces, artifacts, projects",
                     "搜索任务 搜索任务 conversation-search-modal__input"] {
            XCTAssertEqual(profile.pickerKind(hint, focusedSearch: true), .sessions, hint)
            XCTAssertNil(ApplicationProfile.browser.pickerKind(hint, focusedSearch: true), hint)
            XCTAssertNil(ApplicationProfile.claude.pickerKind(hint, focusedSearch: true), hint)
        }
        for hint in ["Search", "搜索", "搜索对话内容", "Search in conversation", "Rename task", "Delete task confirmation"] {
            XCTAssertNil(profile.pickerKind(hint, focusedSearch: true), hint)
        }
    }

    func testSessionActionUsesSidebarButtonWithKnownShortcutFallback() {
        XCTAssertTrue(profile.opensSessionsWithButton)
        XCTAssertFalse(profile.picksSessionsFromSidebar)
        XCTAssertTrue(profile.sessionTriggerAncestorClasses.contains("conversation-list-topbar-actions"))
        XCTAssertEqual(profile.primaryShortcut?.code, 40)
        XCTAssertEqual(profile.primaryShortcut?.flags, .maskCommand)
        for hint in ["搜索", "Search"] {
            XCTAssertTrue(profile.isSessionTrigger(role: "AXButton", hint: hint))
            XCTAssertFalse(profile.isSessionTrigger(role: "AXStaticText", hint: hint))
        }
        XCTAssertFalse(profile.isSessionTrigger(role: "AXButton", hint: "Search files"))
        XCTAssertFalse(ApplicationProfile.claude.isSessionTrigger(role: "AXButton", hint: "Search"))
    }

    func testModelActionRequiresTheComposerControlAndInventsNoShortcut() {
        XCTAssertTrue(profile.opensModelsWithButton)
        XCTAssertNil(profile.secondaryShortcut)
        for role in ["AXButton", "AXPopUpButton", "AXMenuButton"] {
            XCTAssertTrue(profile.isModelTrigger(role: role, hint: "Select model"))
            XCTAssertTrue(profile.isModelTrigger(role: role, hint: "选择模型"))
            XCTAssertFalse(profile.isModelTrigger(role: role, hint: "Delete model"))
            XCTAssertFalse(profile.isModelTrigger(role: role, hint: "Models settings"))
        }
        XCTAssertFalse(profile.isModelTrigger(role: "AXStaticText", hint: "Select model"))
        XCTAssertEqual(profile.pickerKind("cr-model-selector__menu Thinking effort"), .models)
        XCTAssertEqual(profile.pickerKind("cr-model-selector__group-sub-menu"), .models)
        XCTAssertFalse(profile.isEffortTrigger(role: "AXButton", hint: "Thinking mode"))
    }

    func testWebModelOptionsExcludeDecorativeTextDisabledModelsAndFooterActions() {
        let classes = ["cr-model-selector__item", "cr-model-selector__item--selected"]
        XCTAssertTrue(profile.isWebModelOption(role: "AXStaticText", classes: classes))
        XCTAssertTrue(profile.isWebModelOption(role: "AXMenuItem", classes: classes))
        for role in ["AXStaticText", "AXGroup", "AXRow", "AXMenuItem"] {
            XCTAssertFalse(profile.isWebModelOption(role: role, classes: ["cr-model-selector__item-name"]))
            XCTAssertFalse(profile.isWebModelOption(role: role, classes: ["cr-model-selector__item", "cr-model-selector__item--disabled"]))
        }
        XCTAssertFalse(profile.isWebModelOption(role: "AXButton", classes: ["cr-model-selector__group-sub-menu-action"]))
        XCTAssertFalse(ApplicationProfile.claude.isWebModelOption(role: "AXStaticText", classes: classes))
    }

    func testEmptyComposerScrollsDraftEditsAndSearchOwnsNavigation() {
        let composer = AccessibilityFocusMetadata(role: "AXTextArea", editable: true,
            selection: CFRange(location: 0, length: 0))
        let placeholder = "今天帮你做些什么？@ 添加上下文，/调用技能与指令"
        var context = InteractionContext(targetAvailable: true,
            editorFocused: AccessibilityHints.editorFocused(in: [composer]), modalOpen: false,
            compositionActive: false, picker: nil,
            hasDraftText: AccessibilityHints.hasDraft(value: placeholder, labels: [placeholder]), applicationProfile: profile)
        var state = InteractionState()
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .scroll(1))
        context.hasDraftText = true
        XCTAssertEqual(reduce(state: &state, control: .right, context: context), .moveCursor(1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .deleteBackward)
        context.picker = .sessions
        context.modalOpen = true
        XCTAssertEqual(reduce(state: &state, control: .right, context: context), .moveCandidate(1))
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context), .confirmCandidate)
        context.picker = nil
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .none)
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .sendEscape)
    }

    @MainActor
    func testWorkBuddyDictationPastesAndCustomRuleCanOverrideTheAdapter() async throws {
        let originalMethod = UserDefaults.standard.object(forKey: TextInserter.methodKey)
        defer {
            if let originalMethod { UserDefaults.standard.set(originalMethod, forKey: TextInserter.methodKey) }
            else { UserDefaults.standard.removeObject(forKey: TextInserter.methodKey) }
        }
        TextInserter.method = .automatic
        XCTAssertFalse(TextInserter.supportsDirectWrites("com.tencent.workbuddy.mac"))
        XCTAssertTrue(TextInserter.supportsDirectWrites("org.example.NativeEditor"))

        let suite = "VibeWand.workBuddy.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let adapter = AccessibilityAdapter(preferences: preferences)
        XCTAssertTrue(adapter.isApplicationEnabled(bundleID: "com.tencent.workbuddy.mac"))
        adapter.setEnabled(false, for: profile)
        let restored = AccessibilityAdapter(preferences: preferences)
        XCTAssertFalse(restored.isApplicationEnabled(bundleID: "com.tencent.workbuddy.mac"))
        restored.setEnabled(true, for: profile)
        let custom = CustomApplicationProfile(name: "WorkBuddy", bundleID: "com.tencent.workbuddy.mac", template: .chat)
        try restored.saveCustomProfile(custom)
        XCTAssertEqual(restored.resolvedProfile(bundleID: custom.bundleID), .customChat)
        restored.setCustomProfileEnabled(false, id: custom.id)
        XCTAssertFalse(restored.isApplicationEnabled(bundleID: custom.bundleID))
        restored.removeCustomProfile(id: custom.id)
        XCTAssertEqual(restored.resolvedProfile(bundleID: custom.bundleID), profile)
        XCTAssertTrue(restored.isApplicationEnabled(bundleID: custom.bundleID))

        // Optional visual evidence uses our own hidden view and never controls
        // WorkBuddy or starts a physical input source.
        if let path = ProcessInfo.processInfo.environment["VIBEWAND_APPLICATIONS_REVIEW"] {
            _ = NSApplication.shared
            let runtime = BridgeRuntime(templates: DeviceTemplateStore(defaults: preferences))
            let overlay = OverlayController { _, _ in XCTFail("Rendering must not dispatch input") }
            let model = SettingsModel(runtime: runtime, overlay: overlay)
            let host = NSHostingView(rootView: ApplicationSettings(model: model).background(Color(nsColor: .windowBackgroundColor)).id("initial"))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 820),
                styleMask: [], backing: .buffered, defer: false)
            window.contentView = host
            let oldLanguage = L10n.shared.language
            let oldPreference = UserDefaults.standard.object(forKey: L10n.storageKey)
            defer {
                L10n.shared.language = oldLanguage
                if let oldPreference { UserDefaults.standard.set(oldPreference, forKey: L10n.storageKey) }
                else { UserDefaults.standard.removeObject(forKey: L10n.storageKey) }
                runtime.stop()
            }
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, language) in [("zh", AppLanguage.zhHans), ("en", .english)] {
                L10n.shared.language = language
                window.appearance = NSAppearance(named: .aqua)
                host.rootView = ApplicationSettings(model: model).background(Color(nsColor: .windowBackgroundColor)).id(language.rawValue)
                model.refresh()
                try await Task.sleep(nanoseconds: 450_000_000)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("applications-\(name).png"))
                XCTAssertFalse(window.isVisible)
            }
        }
    }
}
