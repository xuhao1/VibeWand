import XCTest
@testable import VibeWandBridge

final class ApplicationProfileTests: XCTestCase {
    func testOnlyExactInstalledAppIdentitiesAreSupported() {
        XCTAssertEqual(ApplicationProfile.resolve(bundleID: "com.deepseek.dsh"), .deepSeekHarness)
        XCTAssertEqual(ApplicationProfile.resolve(bundleID: "com.tencent.workbuddy.mac"), .workBuddy)
        XCTAssertEqual(ApplicationProfile.resolve(bundleID: "com.tencent.xinWeChat"), .weChat)
        XCTAssertEqual(ApplicationProfile.resolve(bundleID: "com.electron.lark"), .feishu)
        for bundle in ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac"] {
            XCTAssertEqual(ApplicationProfile.resolve(bundleID: bundle), .browser)
        }
        for bundle in [nil, "com.deepseek.dsh.helper", "com.tencent.workbuddy.mac.helper", "com.workbuddy.workbuddy", "com.example.codex", "com.google.Chrome.fake", "com.apple.TextEdit"] {
            XCTAssertEqual(ApplicationProfile.resolve(bundleID: bundle), .generic)
        }
    }

    func testTerminalAgentsTakeTypedCommandsAndFollowTheirPrompt() {
        XCTAssertEqual(ApplicationProfile.resolve(bundleID: "com.googlecode.iterm2"), .terminal)
        XCTAssertEqual(ApplicationProfile.terminal.typedCommand(for: .openSessions), "/resume")
        XCTAssertEqual(ApplicationProfile.terminal.typedCommand(for: .openModels), "/model")
        XCTAssertNil(ApplicationProfile.terminal.typedCommand(for: .sendReturn))
        XCTAssertNil(ApplicationProfile.codex.typedCommand(for: .openSessions))

        // An empty prompt, or no prompt at all: turning scrolls and ESC stays Escape.
        var state = InteractionState()
        for recognised in [true, false] {
            let context = InteractionContext(targetAvailable: true, editorFocused: recognised, modalOpen: false,
                compositionActive: false, picker: nil, hasDraftText: false, applicationProfile: .terminal)
            XCTAssertFalse(context.canEditDraft)
            XCTAssertEqual(reduce(state: &state, control: .right, context: context), .scroll(-1))
            XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .sendEscape)
            XCTAssertEqual(reduce(state: &state, control: .dial, context: context), .openSessions)
        }
        // A draft at the prompt is edited like any other composer.
        var context = InteractionContext(targetAvailable: true, editorFocused: true, modalOpen: false,
            compositionActive: false, picker: nil, hasDraftText: true, applicationProfile: .terminal)
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .moveCursor(-1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .deleteBackward)
        XCTAssertEqual(state.mode, .editing)
        // A list the typed command opened is navigated with the same controls as any picker.
        context = InteractionContext(targetAvailable: true, editorFocused: false, modalOpen: false,
            compositionActive: false, picker: .sessions, hasDraftText: false, applicationProfile: .terminal)
        XCTAssertEqual(reduce(state: &state, control: .right, context: context), .moveCandidate(1))
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context), .confirmCandidate)
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .cancelPicker)
    }

    func testBrowserInputFocusNeverChangesWheelIntoCursorOrDeletion() {
        var state = InteractionState(mode: .editing)
        let context = InteractionContext(targetAvailable: true, editorFocused: true,
            modalOpen: false, compositionActive: false, picker: nil, hasDraftText: true, applicationProfile: .browser)
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .scroll(1))
        XCTAssertEqual(reduce(state: &state, control: .right, context: context), .scroll(-1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .sendEscape)
        XCTAssertEqual(reduce(state: &state, control: .dial, context: context), .openSessions)
        XCTAssertEqual(state.mode, .browse)
        XCTAssertEqual(ApplicationProfile.browser.primaryShortcut?.code, 48)
        XCTAssertEqual(ApplicationProfile.browser.primaryShortcut?.flags, .maskControl)
        XCTAssertEqual(ApplicationProfile.browser.secondaryShortcut?.code, 37)
        XCTAssertEqual(ApplicationProfile.browser.secondaryShortcut?.flags, .maskCommand)
    }

    func testAppSwitchDiscardsStalePickerAndStillHonorsComposition() {
        var state = InteractionState(mode: .models)
        var browser = InteractionContext(targetAvailable: true, editorFocused: true,
            modalOpen: false, compositionActive: false, picker: nil, applicationProfile: .browser)
        XCTAssertEqual(reduce(state: &state, control: .dial, context: browser), .openSessions)
        browser.compositionActive = true
        XCTAssertEqual(reduce(state: &state, control: .right, context: browser), .none)
        XCTAssertEqual(reduce(state: &state, control: .dial, context: browser), .sendReturn)
        browser.compositionActive = false
        browser.modalOpen = true
        XCTAssertEqual(reduce(state: &state, control: .right, context: browser), .none)
    }

    func testPickerMetadataIsScopedToApplication() {
        XCTAssertNil(ApplicationProfile.browser.pickerKind("Search chats", focusedSearch: true))
        XCTAssertNil(ApplicationProfile.weChat.pickerKind("ModelSelectorPopover"))
        XCTAssertEqual(ApplicationProfile.weChat.pickerKind("搜索", focusedSearch: true), .sessions)
        XCTAssertNil(ApplicationProfile.weChat.pickerKind("搜索", focusedSearch: false))
        XCTAssertEqual(ApplicationProfile.feishu.pickerKind("ModalWebViewWidget - search:search-command-bar:default"), .sessions)
        XCTAssertNil(ApplicationProfile.feishu.pickerKind("Rename conversation"))
        XCTAssertEqual(ApplicationProfile.deepSeekHarness.pickerKind("搜索会话名称", focusedSearch: true), .sessions)
        XCTAssertEqual(ApplicationProfile.deepSeekHarness.pickerKind("Search session names", focusedSearch: true), .sessions)
        XCTAssertEqual(ApplicationProfile.deepSeekHarness.pickerKind("模型与推理等级"), .models)
        XCTAssertEqual(ApplicationProfile.deepSeekHarness.pickerKind("Model and reasoning effort"), .models)
    }

    func testHarnessModelActionRequiresKnownControlAndDoesNotInventShortcut() {
        XCTAssertNil(ApplicationProfile.deepSeekHarness.secondaryShortcut)
        XCTAssertTrue(ApplicationProfile.isHarnessModelTrigger(role: "AXPopUpButton", hint: "选择模型，当前 Qwen"))
        XCTAssertTrue(ApplicationProfile.isHarnessModelTrigger(role: "AXButton", hint: "Select model, current DeepSeek, reasoning effort high"))
        XCTAssertTrue(ApplicationProfile.isHarnessModelTrigger(role: "AXPopUpButton", hint: "请选择模型"))
        XCTAssertFalse(ApplicationProfile.isHarnessModelTrigger(role: "AXStaticText", hint: "Select model, current DeepSeek"))
        XCTAssertFalse(ApplicationProfile.isHarnessModelTrigger(role: "AXButton", hint: "Delete model"))
    }

    @MainActor
    func testDisabledIntegrationsPersistAndUnknownAppsCannotBeEnabled() {
        let suite = "VibeWand.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let adapter = AccessibilityAdapter(preferences: preferences)
        XCTAssertTrue(adapter.isEnabled(.browser))
        adapter.setEnabled(false, for: .browser)
        adapter.setEnabled(true, for: .generic)
        let restored = AccessibilityAdapter(preferences: preferences)
        XCTAssertFalse(restored.isEnabled(.browser))
        XCTAssertTrue(restored.isEnabled(.codex))
        XCTAssertFalse(restored.isEnabled(.generic))
        restored.setEnabled(true, for: .browser)
        XCTAssertTrue(restored.isEnabled(.browser))
    }
}
