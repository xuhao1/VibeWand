import XCTest
@testable import VibeWandBridge

final class CustomApplicationProfileTests: XCTestCase {
    private func withPreferences(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "VibeWand.customApps.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        try body(preferences)
    }

    func testTemplatesHaveDifferentPrimaryActionsAndStableNavigation() {
        let chat = CustomApplicationProfile(template: .chat)
        let browser = CustomApplicationProfile(template: .browser)
        let custom = CustomApplicationProfile(template: .custom)
        XCTAssertEqual(chat.shortcut(for: .openSessions), .init(key: .k, command: true))
        XCTAssertEqual(browser.shortcut(for: .openSessions), .init(key: .tab, control: true))
        XCTAssertEqual(browser.shortcut(for: .openModels), .init(key: .l, command: true))
        XCTAssertNil(custom.shortcut(for: .openSessions))
        XCTAssertNil(custom.shortcut(for: .openModels))
        for profile in [chat, browser, custom] {
            XCTAssertEqual(profile.shortcut(for: .sendReturn)?.key, .returnKey)
            XCTAssertEqual(profile.shortcut(for: .cancelPicker)?.key, .escape)
            XCTAssertEqual(profile.shortcut(for: .moveCandidate(-1))?.key, .up)
            XCTAssertEqual(profile.shortcut(for: .moveCandidate(1))?.key, .down)
            XCTAssertEqual(profile.shortcut(for: .moveCursor(-1))?.key, .left)
            XCTAssertEqual(profile.shortcut(for: .deleteBackward)?.key, .backspace)
            XCTAssertNil(profile.shortcut(for: .scroll(-1))) // Native scrolling.
        }
    }

    @MainActor
    func testExactCustomIdentityPersistsWithoutAllowingHelpersOrUnknownApps() throws {
        try withPreferences { preferences in
            let adapter = AccessibilityAdapter(preferences: preferences)
            var profile = CustomApplicationProfile(name: " Team chat ", bundleID: " org.example.Chat ", template: .chat)
            profile.shortcuts[.primary] = .init(key: .f, command: true, shift: true)
            try adapter.saveCustomProfile(profile)
            let restored = AccessibilityAdapter(preferences: preferences)
            XCTAssertEqual(restored.customProfiles.count, 1)
            XCTAssertEqual(restored.customProfiles[0].name, "Team chat")
            XCTAssertEqual(restored.customProfiles[0].shortcuts, profile.shortcuts)
            XCTAssertEqual(restored.resolvedProfile(bundleID: "org.example.Chat"), .customChat)
            XCTAssertTrue(restored.isApplicationEnabled(bundleID: "org.example.Chat"))
            for bundle in [nil, "org.example.Chat.helper", "org.example.chat", "org.example.Other"] {
                XCTAssertFalse(restored.isApplicationEnabled(bundleID: bundle))
                XCTAssertEqual(restored.resolvedProfile(bundleID: bundle), .generic)
            }
        }
    }

    @MainActor
    func testDisabledCustomEntryShadowsBuiltInAndRemovalRestoresBuiltIn() throws {
        try withPreferences { preferences in
            let adapter = AccessibilityAdapter(preferences: preferences)
            let profile = CustomApplicationProfile(name: "Safari", bundleID: "com.apple.Safari", template: .browser)
            try adapter.saveCustomProfile(profile)
            adapter.setCustomProfileEnabled(false, id: profile.id)
            let restored = AccessibilityAdapter(preferences: preferences)
            XCTAssertFalse(restored.isApplicationEnabled(bundleID: profile.bundleID))
            XCTAssertTrue(restored.isEnabled(.browser)) // Other browsers stay enabled.
            restored.setCustomProfileEnabled(true, id: profile.id)
            XCTAssertTrue(restored.isApplicationEnabled(bundleID: profile.bundleID))
            restored.removeCustomProfile(id: profile.id)
            XCTAssertEqual(restored.resolvedProfile(bundleID: profile.bundleID), .browser)
            XCTAssertTrue(restored.isApplicationEnabled(bundleID: profile.bundleID))
            XCTAssertTrue(restored.customProfiles.isEmpty)
        }
    }

    func testInvalidAndDuplicateIdentitiesDoNotChangeSavedRules() throws {
        try withPreferences { preferences in
            let store = CustomApplicationProfileStore(preferences: preferences)
            let profile = CustomApplicationProfile(name: "Browser", bundleID: "com.example.browser", template: .browser)
            try store.save(profile)
            for bundle in ["", "Safari", "com.example.*", "com.example.browser;open", "com.example..browser"] {
                XCTAssertThrowsError(try store.save(.init(name: "Bad", bundleID: bundle)))
            }
            XCTAssertThrowsError(try store.save(.init(name: "Duplicate", bundleID: profile.bundleID)))
            XCTAssertThrowsError(try store.save(.init(name: " ", bundleID: "org.example.valid")))
            XCTAssertEqual(store.profiles, [profile])
            var updated = profile
            updated.name = "Updated"
            updated.applyTemplate(.custom)
            try store.save(updated)
            XCTAssertEqual(store.profiles, [updated])
        }
    }

    func testCustomShortcutsReachEventRoutingAndUnassignedDoesNotFallBack() {
        var profile = CustomApplicationProfile(name: "Custom", bundleID: "org.example.app", template: .custom)
        profile.shortcuts[.confirm] = .init(key: .returnKey, command: true)
        profile.shortcuts[.previous] = .init(key: .tab, control: true, shift: true)
        profile.shortcuts[.scrollDown] = .init(key: .pageDown)
        var observation = TargetObservation()
        observation.customProfile = profile
        XCTAssertEqual(observation.shortcut(for: .sendReturn)?.code, 36)
        XCTAssertEqual(observation.shortcut(for: .sendReturn)?.flags, .maskCommand)
        XCTAssertEqual(observation.shortcut(for: .confirmCandidate)?.flags, .maskCommand)
        XCTAssertEqual(observation.shortcut(for: .moveCandidate(-1))?.code, 48)
        XCTAssertEqual(observation.shortcut(for: .moveCandidate(-1))?.flags, [.maskControl, .maskShift])
        XCTAssertEqual(observation.shortcut(for: .scroll(1))?.code, 121)
        XCTAssertNil(observation.shortcut(for: .openSessions, fallback: KeyStroke(code: 40, flags: .maskCommand)))
        XCTAssertNil(observation.shortcut(for: .none))
    }

    func testIMEAndUnknownDialogKeepNativeReturnEscapeDespiteCustomSendChord() {
        var profile = CustomApplicationProfile(template: .chat)
        profile.shortcuts[.confirm] = .init(key: .returnKey, command: true)
        profile.shortcuts[.cancel] = .init(key: .w, command: true)
        var observation = TargetObservation()
        observation.customProfile = profile
        observation.context.compositionActive = true
        XCTAssertEqual(observation.shortcut(for: .sendReturn)?.code, 36)
        XCTAssertEqual(observation.shortcut(for: .sendReturn)?.flags, [])
        XCTAssertEqual(observation.shortcut(for: .sendEscape)?.code, 53)
        observation.context.compositionActive = false
        observation.context.modalOpen = true
        XCTAssertEqual(observation.shortcut(for: .sendReturn)?.flags, [])
        XCTAssertEqual(observation.shortcut(for: .sendEscape)?.code, 53)
        observation.context.picker = .sessions
        XCTAssertEqual(observation.shortcut(for: .confirmCandidate)?.flags, .maskCommand)
        XCTAssertEqual(observation.shortcut(for: .cancelPicker)?.code, 13)
    }

    func testCustomBrowserScrollsEvenWithEditorFocusAndChatRecognizesSearch() {
        var state = InteractionState(mode: .editing)
        let context = InteractionContext(targetAvailable: true, editorFocused: true,
            modalOpen: false, compositionActive: false, picker: nil, hasDraftText: true, applicationProfile: .customBrowser)
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .scroll(1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .sendEscape)
        XCTAssertEqual(ApplicationProfile.customChat.pickerKind("Search", focusedSearch: true), .sessions)
        XCTAssertNil(ApplicationProfile.custom.pickerKind("Search", focusedSearch: true))
        XCTAssertNil(ApplicationProfile.customBrowser.pickerKind("Search", focusedSearch: true))
        XCTAssertFalse(ApplicationProfile.custom.expectsSessionPicker)
        XCTAssertFalse(ApplicationProfile.customBrowser.expectsSessionPicker)
        XCTAssertTrue(ApplicationProfile.customChat.expectsSessionPicker)
    }
}
