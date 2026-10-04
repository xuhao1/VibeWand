import AppKit
import ApplicationServices
import XCTest
import SpeechInput
import AU05Device
@testable import VibeKeyBridge

/// Opt-in live acceptance; ordinary unit tests never manipulate WorkBuddy.
final class WorkBuddyLiveTests: XCTestCase {
    private func clipboardSnapshot() -> [[String: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type.rawValue, $0) } })
        }
    }
    private func controls(in root: AXUIElement, className: String) -> [AXUIElement] {
        var stack = [root], seen = Set<CFHashCode>(), found: [AXUIElement] = []
        while let node = stack.popLast(), seen.count < 2000 {
            guard seen.insert(CFHash(node)).inserted else { continue }
            let classes = attribute(node, "AXDOMClassList") as? [String] ?? []
            if classes.contains(className) { found.append(node); continue }
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            if !["AXTextArea", "AXTextField", "AXStaticText"].contains(role),
               let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { stack += children.reversed() }
        }
        return found
    }
    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }

    private func modelSignature(pid: pid_t) throws -> String {
        let profile = ApplicationProfile.workBuddy
        let control = try XCTUnwrap(LabelledControlFinder.find(pid: pid, roles: profile.modelTriggerRoles) { profile.isModelTrigger(role: $0, hint: $1) })
        return try XCTUnwrap([kAXValueAttribute, kAXTitleAttribute].compactMap { attribute(control, $0) as? String }.first { !$0.isEmpty && $0 != "Select model" })
    }

    private func selectedSearchResult(in window: AXUIElement) -> AXUIElement? {
        controls(in: window, className: "wb-gs-item").first {
            attribute($0, kAXSelectedAttribute) as? Bool == true ||
                (attribute($0, "AXDOMClassList") as? [String] ?? []).contains("wb-gs-item--selected")
        }
    }

    @MainActor
    private func postNewTask(pid: pid_t) async throws {
        let profile = ApplicationProfile.workBuddy
        let control = try XCTUnwrap(LabelledControlFinder.find(pid: pid, roles: profile.modelTriggerRoles) { profile.isModelTrigger(role: $0, hint: $1) })
        _ = AXUIElementSetAttributeValue(control, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await Task.sleep(nanoseconds: 100_000_000)
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: down))
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
            event.postToPid(pid)
        }
    }

    @MainActor
    private func focusComposer(_ adapter: AccessibilityAdapter, pid: pid_t) async throws -> TargetObservation {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                throw NSError(domain: "VibeWand.WorkBuddyAcceptance", code: 4)
            }
            if let composer = LabelledControlFinder.find(pid: pid, budget: 0.3, roles: ["AXTextArea"], matches: { _, _ in true }) {
                _ = AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                try await Task.sleep(nanoseconds: 100_000_000)
                let observation = await sample(adapter)
                if observation.context.editorFocused { return observation }
                if let position = attribute(composer, kAXPositionAttribute), let size = attribute(composer, kAXSizeAttribute),
                   CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var point = CGPoint.zero, dimensions = CGSize.zero
                    if AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) {
                        SystemPointer.click(at: CGPoint(x: point.x + dimensions.width / 2, y: point.y + dimensions.height / 2))
                    }
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw NSError(domain: "VibeWand.WorkBuddyAcceptance", code: 5,
            userInfo: [NSLocalizedDescriptionKey: "WorkBuddy composer did not settle after navigation"])
    }

    @MainActor
    private func sample(_ adapter: AccessibilityAdapter) async -> TargetObservation {
        await withCheckedContinuation { continuation in
            adapter.requestRefresh { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func waitFor(_ adapter: AccessibilityAdapter,
                         stage: String = "main",
                         _ matches: (TargetObservation) -> Bool) async throws -> TargetObservation {
        let deadline = Date().addingTimeInterval(8)
        var last = TargetObservation()
        repeat {
            let observation = await sample(adapter)
            last = observation
            if matches(observation) { return observation }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw NSError(domain: "VibeWand.WorkBuddyAcceptance", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(stage): target=\(last.context.targetAvailable) editor=\(last.context.editorFocused) modal=\(last.context.modalOpen) picker=\(String(describing: last.context.picker)) candidates=\(last.candidates.count) status=\(last.status) foreground=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")"])
    }

    @MainActor
    func testLiveTaskSearchModelNavigationAndPasteDelivery() async throws {
        guard ProcessInfo.processInfo.environment["VIBEWAND_WORKBUDDY_LIVE"] == "1" else {
            throw XCTSkip("Requires explicitly enabled live WorkBuddy acceptance")
        }
        guard AXIsProcessTrusted() else {
            throw NSError(domain: "VibeWand.WorkBuddyAcceptance", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Native test process lacks Accessibility access"])
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.workbuddy.mac").first)
        let previousApp = NSWorkspace.shared.frontmostApplication
        defer { previousApp?.activate(options: []) }
        XCTAssertTrue(app.activate(options: []))
        let suite = "VibeWand.WorkBuddyLive.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let adapter = AccessibilityAdapter(preferences: preferences)
        adapter.onStatus = { print("WorkBuddy adapter:", $0) }
        defer { adapter.reset() }
        let originalMethod = UserDefaults.standard.object(forKey: TextInserter.methodKey)
        TextInserter.method = .automatic
        defer {
            if let originalMethod { UserDefaults.standard.set(originalMethod, forKey: TextInserter.methodKey) }
            else { UserDefaults.standard.removeObject(forKey: TextInserter.methodKey) }
        }
        let originalClipboard = clipboardSnapshot()
        var observation = try await waitFor(adapter) { $0.context.targetAvailable && !$0.context.modalOpen }
        XCTAssertEqual(observation.context.applicationProfile, .workBuddy)
        observation = try await focusComposer(adapter, pid: app.processIdentifier)
        let initialEditor = try XCTUnwrap(observation.editor)
        let initialValue = try XCTUnwrap(AccessibilityDictationField(element: initialEditor, pid: app.processIdentifier).read()?.value)
        guard !ApplicationProfile.workBuddy.hasDraft(value: initialValue, labels: []) else {
            throw NSError(domain: "VibeWand.WorkBuddyAcceptance", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Live acceptance refuses to replace an existing user draft"])
        }
        if controls(in: try XCTUnwrap(observation.window), className: "wb-home-route").isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            try await postNewTask(pid: app.processIdentifier)
        }
        observation = try await waitFor(adapter, stage: "initial home ready") { value in
            value.context.targetAvailable && value.window.map { !self.controls(in: $0, className: "wb-home-route").isEmpty } == true
        }
        observation = try await focusComposer(adapter, pid: app.processIdentifier)

        adapter.perform(.openSessions, observation: observation)
        observation = try await waitFor(adapter, stage: "task search opened") { $0.context.picker == .sessions }
        UnicodeTextDelivery.post("a", pid: app.processIdentifier)
        observation = try await waitFor(adapter, stage: "search query entered") { value in
            value.focused.map { self.attribute($0, kAXValueAttribute) as? String == "a" } == true
        }
        let tasksTab = try XCTUnwrap(LabelledControlFinder.find(pid: app.processIdentifier, roles: ["AXRadioButton"]) { _, hint in ["tasks", "任务"].contains(hint.lowercased()) })
        XCTAssertEqual(AXUIElementPerformAction(tasksTab, kAXPressAction as CFString), .success)
        observation = try await waitFor(adapter, stage: "search results loaded") { value in
            value.window.map { !self.controls(in: $0, className: "wb-gs-item").isEmpty } == true
        }
        let globalResults = controls(in: try XCTUnwrap(observation.window), className: "wb-gs-item")
        print("WorkBuddy global results:", globalResults.count)
        XCTAssertGreaterThan(globalResults.count, 1)
        XCTAssertTrue(globalResults.allSatisfy { (attribute($0, "AXDOMClassList") as? [String] ?? []).contains("wb-gs-item--task") })
        let previousSelection = selectedSearchResult(in: try XCTUnwrap(observation.window)).map(CFHash)
        observation = await sample(adapter)
        adapter.perform(.moveCandidate(1), observation: observation)
        observation = try await waitFor(adapter, stage: "task result selection moved") { value in
            value.context.picker == .sessions && value.window.flatMap { self.selectedSearchResult(in: $0) }.map(CFHash) != previousSelection
        }
        adapter.perform(.confirmCandidate, observation: observation)
        observation = try await waitFor(adapter, stage: "task opened") { value in
            value.context.targetAvailable && value.context.picker == nil && value.window.map { self.controls(in: $0, className: "wb-home-route").isEmpty } == true &&
                LabelledControlFinder.find(pid: app.processIdentifier, budget: 0.2, roles: ApplicationProfile.workBuddy.modelTriggerRoles) { ApplicationProfile.workBuddy.isModelTrigger(role: $0, hint: $1) } != nil
        }
        // Allow WorkBuddy's task-route keyboard listener and initial autofocus
        // to settle before using its own New Task shortcut for fixture cleanup.
        try await Task.sleep(nanoseconds: 500_000_000)
        try await postNewTask(pid: app.processIdentifier)
        observation = try await waitFor(adapter, stage: "home restored") { value in
            value.context.targetAvailable && value.context.picker == nil && value.window.map { !self.controls(in: $0, className: "wb-home-route").isEmpty } == true
        }
        observation = try await focusComposer(adapter, pid: app.processIdentifier)
        try await Task.sleep(nanoseconds: 200_000_000)
        observation = await sample(adapter)
        adapter.perform(.openSessions, observation: observation)
        observation = try await waitFor(adapter, stage: "search reopened") { $0.context.picker == .sessions }
        adapter.perform(.cancelPicker, observation: observation)
        observation = try await waitFor(adapter, stage: "task search closed") { $0.context.targetAvailable && $0.context.picker == nil && !$0.context.modalOpen }

        adapter.perform(.openModels, observation: observation)
        observation = try await waitFor(adapter, stage: "model menu opened") { $0.context.picker == .models && !$0.candidates.isEmpty }
        print("WorkBuddy model candidates:", observation.candidates.count)
        print("WorkBuddy selected models:", observation.candidates.filter(\.selected).count)
        let originalModelSignature = try modelSignature(pid: app.processIdentifier)
        let originalModelIndex = try XCTUnwrap(observation.candidates.firstIndex(where: \.selected))
        let originalModelTitle = observation.candidates[originalModelIndex].title
        XCTAssertGreaterThan(observation.candidates.count, 1)
        // The control lookup above can outlive the adapter's 700 ms sample;
        // refresh before dispatch, just as the runtime does for device input.
        observation = try await waitFor(adapter, stage: "fresh model navigation") { $0.context.picker == .models && !$0.candidates.isEmpty }
        adapter.perform(.moveCandidate(originalModelIndex > 0 ? -1 : 1), observation: observation)
        observation = try await waitFor(adapter) { $0.context.picker == .models }
        XCTAssertFalse(adapter.selectionTitle.isEmpty)
        adapter.perform(.confirmCandidate, observation: observation)
        observation = try await waitFor(adapter) { $0.context.targetAvailable && $0.context.picker == nil && !$0.context.modalOpen }
        XCTAssertTrue(try modelSignature(pid: app.processIdentifier) != originalModelSignature)
        adapter.perform(.openModels, observation: observation)
        observation = try await waitFor(adapter, stage: "model menu reopened") { $0.context.picker == .models && !$0.candidates.isEmpty }
        let restoreIndex = try XCTUnwrap(observation.candidates.firstIndex { $0.title == originalModelTitle })
        let selectedIndex = try XCTUnwrap(observation.candidates.firstIndex(where: \.selected))
        for _ in 0..<abs(restoreIndex - selectedIndex) {
            adapter.perform(.moveCandidate(restoreIndex > selectedIndex ? 1 : -1), observation: observation)
            observation = try await waitFor(adapter) { $0.context.picker == .models }
        }
        adapter.perform(.confirmCandidate, observation: observation)
        observation = try await waitFor(adapter, stage: "model restored") { $0.context.targetAvailable && $0.context.picker == nil && !$0.context.modalOpen }
        XCTAssertTrue(try modelSignature(pid: app.processIdentifier) == originalModelSignature)
        observation = try await focusComposer(adapter, pid: app.processIdentifier)

        // Only an empty composer is eligible for disposable test text.
        // Existing user drafts are never replaced or printed by this test.
        let editor = try XCTUnwrap(observation.editor)
        let field = AccessibilityDictationField(element: editor, pid: app.processIdentifier)
        let original = try XCTUnwrap(field.read())
        XCTAssertFalse(observation.context.hasDraftText ?? true)
        guard !ApplicationProfile.workBuddy.hasDraft(value: original.value, labels: []) else {
            throw NSError(domain: "VibeWand.WorkBuddyAcceptance", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Test requires an empty focused WorkBuddy composer"])
        }
        let inserter = TextInserter()
        let text = "VibeWand WorkBuddy acceptance 2026-10-05"
        let outcome: TextInsertionOutcome = await withCheckedContinuation { continuation in
            inserter.insert(text, pid: app.processIdentifier, bundleID: "com.tencent.workbuddy.mac", editor: editor) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertEqual(outcome, .inserted(via: "paste", verified: true))
        XCTAssertTrue(clipboardSnapshot() == originalClipboard)
        XCTAssertTrue(field.read()?.value == text)
        observation = try await waitFor(adapter) { $0.context.canEditDraft }
        let caret = try XCTUnwrap(field.read()?.selection.location)
        adapter.perform(.moveCursor(-1), observation: observation)
        observation = try await waitFor(adapter, stage: "caret moved left") { _ in field.read()?.selection.location == caret - 1 }
        adapter.perform(.moveCursor(1), observation: observation)
        observation = try await waitFor(adapter, stage: "caret moved right") { _ in field.read()?.selection.location == caret }
        adapter.perform(.deleteBackward, observation: observation)
        let expected = String(text.dropLast())
        _ = try await waitFor(adapter) { _ in field.read()?.value == expected }
        // Remove only test-owned text through the production deletion path.
        for _ in expected {
            observation = try await waitFor(adapter) { $0.context.canEditDraft }
            adapter.perform(.deleteBackward, observation: observation)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        _ = try await waitFor(adapter) { $0.context.hasDraftText == false }
        XCTAssertFalse(ApplicationProfile.workBuddy.hasDraft(value: try XCTUnwrap(field.read()?.value), labels: []))

        // Exercise Runtime → DictationSession → TextInserter with deterministic
        // transcripts. Audio recognition itself is outside this app-adapter test.
        let prefix = "Existing test draft: "
        UnicodeTextDelivery.post(prefix, pid: app.processIdentifier)
        _ = try await waitFor(adapter, stage: "test draft seeded") { _ in field.read()?.value == prefix }
        let replayText = "VibeWand WorkBuddy voice replay"
        let speechPreferences = SpeechPreferences(defaults: preferences)
        var speechConfiguration = speechPreferences.load()
        speechConfiguration.mode = .builtIn
        speechConfiguration.provider = .system
        speechConfiguration.textStyle = .verbatim
        try speechPreferences.save(speechConfiguration)
        let voice = VoiceInputController(preferences: speechPreferences, engineFactory: { _ in
            TranscriptReplayEngine(previews: ["VibeWand", replayText])
        })
        let runtime = BridgeRuntime(source: UnconfiguredHIDSource(template: DeviceTemplateID.vibeKey.template),
            templates: DeviceTemplateStore(defaults: preferences), voiceInput: voice)
        defer { runtime.stop() }
        runtime.replaySpeech(duration: 0.25)
        try await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertTrue(field.read()?.value == prefix, "Partial recognition must not paste into WorkBuddy")
        let replayDraft = prefix + replayText
        _ = try await waitFor(adapter, stage: "runtime dictation delivered and clipboard restored") { _ in
            field.read()?.value == replayDraft && self.clipboardSnapshot() == originalClipboard
        }
        XCTAssertTrue(clipboardSnapshot() == originalClipboard)
        for _ in replayDraft {
            observation = try await waitFor(adapter) { $0.context.canEditDraft }
            adapter.perform(.deleteBackward, observation: observation)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        _ = try await waitFor(adapter, stage: "test draft cleaned") { $0.context.hasDraftText == false }
        XCTAssertFalse(ApplicationProfile.workBuddy.hasDraft(value: try XCTUnwrap(field.read()?.value), labels: []))
    }
}
