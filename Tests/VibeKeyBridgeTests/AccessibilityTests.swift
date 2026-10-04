import XCTest
@testable import VibeKeyBridge

final class AccessibilityTests: XCTestCase {
    func testStrongPickerMetadataAndIdentifiersAreRecognized() {
        XCTAssertEqual(AccessibilityHints.pickerKind("Search chats"), .sessions)
        XCTAssertEqual(AccessibilityHints.pickerKind("command-menu"), .sessions)
        XCTAssertEqual(AccessibilityHints.pickerKind("模型选择"), .models)
        XCTAssertEqual(AccessibilityHints.pickerKind("model_select"), .models)
        XCTAssertEqual(AccessibilityHints.pickerKind("reasoning-effort"), .efforts)
        XCTAssertNil(AccessibilityHints.pickerKind("Ask a question about a model"))
        XCTAssertNil(AccessibilityHints.pickerKind("Delete chat confirmation dialog"))
        XCTAssertNil(AccessibilityHints.pickerKind("Search"))
    }

    func testCompatibilityRequiresFreshSearchAndChangedFocus() {
        func accepted(age: TimeInterval = 0.3, origin: UInt? = 1, current: UInt? = 2,
                      text: Bool = true, hint: String = "Search", enabled: Bool = true,
                      mode: InteractionMode = .sessions) -> Bool {
            AccessibilityHints.acceptCompatibilitySearch(mode: mode, age: age, originFocus: origin,
                currentFocus: current, isText: text, hint: hint, enabled: enabled)
        }
        XCTAssertTrue(accepted())
        XCTAssertFalse(accepted(age: 1.21), "An old shortcut cannot label a later search field")
        XCTAssertFalse(accepted(age: -0.1))
        XCTAssertFalse(accepted(origin: 2), "The original input must never be treated as an opened picker")
        XCTAssertFalse(accepted(origin: nil))
        XCTAssertFalse(accepted(current: nil))
        XCTAssertFalse(accepted(text: false))
        XCTAssertFalse(accepted(hint: "Message composer"))
        XCTAssertFalse(accepted(enabled: false))
        XCTAssertFalse(accepted(mode: .models), "Generic search is not proof of model selection")
    }

    func testUnrelatedModalNeverAdoptsPendingRequest() {
        XCTAssertFalse(AccessibilityHints.acceptCompatibilitySearch(mode: .sessions, age: 0.2,
            originFocus: 1, currentFocus: 2, isText: false, hint: "Dialog Confirm deletion", enabled: true))
        XCTAssertFalse(AccessibilityHints.acceptCompatibilitySearch(mode: .sessions, age: 0.2,
            originFocus: 1, currentFocus: 2, isText: true, hint: "Rename chat", enabled: true))
    }

    func testIdentityChangesWhenApplicationWindowOrEditorChanges() {
        let original = TargetIdentity(pid: 42, windowHash: 100, windowTitle: "Session A",
                                      focusedHash: 200, focusedIdentifier: "composer")
        XCTAssertEqual(original, original)
        var changed = original; changed.pid = 43
        XCTAssertNotEqual(original, changed)
        changed = original; changed.windowHash = 101
        XCTAssertNotEqual(original, changed)
        changed = original; changed.windowTitle = "Session B"
        XCTAssertNotEqual(original, changed)
        changed = original; changed.focusedHash = 201
        XCTAssertNotEqual(original, changed)
        changed = original; changed.focusedIdentifier = "file-editor"
        XCTAssertNotEqual(original, changed)
    }

    func testAnonymousWritableComposerKeepsHorizontalNavigationAtEveryCaretPosition() {
        for caret in [0, 3, 18] {
            let owner = AccessibilityFocusMetadata(role: "AXTextArea", enabled: true,
                valueSettable: true, selection: CFRange(location: caret, length: 0))
            let context = InteractionContext(targetAvailable: true,
                editorFocused: AccessibilityHints.editorFocused(in: [owner]),
                modalOpen: false, compositionActive: false, picker: nil)
            var state = InteractionState()
            XCTAssertEqual(reduce(state: &state, control: .left, context: context), .moveCursor(-1))
            XCTAssertEqual(reduce(state: &state, control: .right, context: context), .moveCursor(1))
            XCTAssertEqual(state.mode, .editing, "A boundary cannot turn the dial into scrolling")
        }
    }

    func testExplicitlyEditableEmptyComposerDoesNotNeedPlaceholderOrText() {
        let empty = AccessibilityFocusMetadata(role: "AXTextArea", editable: true,
            selection: CFRange(location: 0, length: 0))
        XCTAssertTrue(AccessibilityHints.editorFocused(in: [empty]))
    }

    func testFocusInsideTextAreaUsesEnclosingComposerButButtonsDoNot() {
        let owner = AccessibilityFocusMetadata(role: "AXTextArea", valueSettable: true,
            selection: CFRange(location: 5, length: 0))
        let wrapper = AccessibilityFocusMetadata(role: "AXGroup")
        let textChild = AccessibilityFocusMetadata(role: "AXStaticText")
        XCTAssertTrue(AccessibilityHints.editorFocused(in: [textChild, wrapper, owner]))
        XCTAssertEqual(AccessibilityHints.textOwnerIndex(in: [textChild, wrapper, owner]), 2)
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [AccessibilityFocusMetadata(role: "AXButton"), owner]))
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [textChild, AccessibilityFocusMetadata(role: "AXWindow"), owner]))
    }

    func testSelectionAloneCannotTreatReadOnlyConversationTextAsInput() {
        let selection = CFRange(location: 0, length: 3)
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [AccessibilityFocusMetadata(role: "AXTextArea", selection: selection)]))
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [AccessibilityFocusMetadata(role: "AXTextArea", valueSettable: true)]))
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [AccessibilityFocusMetadata(role: "AXTextArea", valueSettable: true,
            selection: CFRange(location: -1, length: 0))]))
        for readOnly in [
            AccessibilityFocusMetadata(role: "AXTextArea", hint: "Message composer", enabled: false),
            AccessibilityFocusMetadata(role: "AXTextArea", hint: "Message composer", editable: false)
        ] {
            XCTAssertFalse(AccessibilityHints.editorFocused(in: [readOnly], forceEditing: true))
        }
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [AccessibilityFocusMetadata(role: "AXTextField", editable: true,
            valueSettable: true, selection: selection)]), "An anonymous rename/settings field is ambiguous")
    }

    func testSearchAndTerminalContextOverrideEditingFallback() {
        let writable = AccessibilityFocusMetadata(role: "AXTextArea", valueSettable: true,
            selection: CFRange(location: 4, length: 0))
        for excludedHint in ["Search chats", "搜索", "filter", "terminal", "terminal-prompt", "code editor", "monaco", "file-editor", "xterm"] {
            let parent = AccessibilityFocusMetadata(role: "AXGroup", hint: excludedHint)
            XCTAssertFalse(AccessibilityHints.editorFocused(in: [writable, parent], forceEditing: true), excludedHint)
        }
        let search = AccessibilityFocusMetadata(role: "AXTextField", subrole: "AXSearchField", hint: "Message composer")
        XCTAssertFalse(AccessibilityHints.editorFocused(in: [search], forceEditing: true))
        let window = AccessibilityFocusMetadata(role: "AXWindow", hint: "Discuss terminal search functionality")
        XCTAssertTrue(AccessibilityHints.editorFocused(in: [writable, window]), "A conversation title is not input-control metadata")
    }

    func testModalAndCompositionStillOwnAnonymousEditorNavigation() {
        let owner = AccessibilityFocusMetadata(role: "AXTextArea", valueSettable: true,
            selection: CFRange(location: 5, length: 0))
        for (modal, composition) in [(true, false), (false, true)] {
            let context = InteractionContext(targetAvailable: true,
                editorFocused: AccessibilityHints.editorFocused(in: [owner]),
                modalOpen: modal, compositionActive: composition, picker: nil)
            var state = InteractionState()
            XCTAssertEqual(reduce(state: &state, control: .left, context: context), .none)
            XCTAssertEqual(reduce(state: &state, control: .right, context: context), .none)
            XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .sendEscape)
        }
    }
}

extension AccessibilityTests {
    func testModelSelectorIdentifiersAndReasoningLabelsAreRecognized() {
        XCTAssertEqual(AccessibilityHints.pickerKind("ModelSelectorPopover"), .models)
        XCTAssertEqual(AccessibilityHints.pickerKind("model-dropdown"), .models)
        XCTAssertEqual(AccessibilityHints.pickerKind("Model"), .models)
        XCTAssertEqual(AccessibilityHints.pickerKind("ReasoningEffortSelector"), .efforts)
        XCTAssertEqual(AccessibilityHints.pickerKind("Reasoning"), .efforts)
        XCTAssertNil(AccessibilityHints.pickerKind("Ask a question about the model"))
    }
    func testModelRequestBindsOnlyNewMenuInSameWindow() {
        func accepted(mode: InteractionMode = .models, age: Double = 0.2, role: String = "AXMenu",
                      previous: Set<UInt> = [], window: UInt = 1) -> Bool {
            AccessibilityHints.acceptRequestedMenu(mode: mode, age: age, role: role,
                menuHash: 30, previousMenus: previous, originWindow: 1, currentWindow: window)
        }
        XCTAssertTrue(accepted())
        XCTAssertFalse(accepted(role: "AXDialog"))
        XCTAssertFalse(accepted(role: "AXTextArea"))
        XCTAssertFalse(accepted(previous: [30]))
        XCTAssertFalse(accepted(window: 2))
        XCTAssertFalse(accepted(age: 1.3))
        XCTAssertFalse(accepted(mode: .sessions))
    }
}

extension AccessibilityTests {
    func testRequestedSelectorRequiresActualOptionsOrSliderNotJustDialog() {
        func accepted(options: Int = 0, slider: Bool = false, previous: Set<UInt> = []) -> Bool {
            AccessibilityHints.acceptRequestedSelector(mode: .models, age: 0.2, role: "AXDialog",
                menuHash: 30, previousMenus: previous, originWindow: 1, currentWindow: 1, options: options, slider: slider)
        }
        XCTAssertFalse(accepted())
        XCTAssertTrue(accepted(options: 3))
        XCTAssertTrue(accepted(slider: true))
        XCTAssertFalse(accepted(options: 3, previous: [30]))
    }
}
