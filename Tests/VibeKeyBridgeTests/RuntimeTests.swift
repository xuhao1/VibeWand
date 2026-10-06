import XCTest
import SpeechInput
@testable import VibeKeyBridge

final class RuntimeTests: XCTestCase {
    func testUnknownIMEStillAllowsCursorMovementAndDeletionInComposer() {
        var state = InteractionState()
        let context = InteractionContext(targetAvailable: true, editorFocused: true,
            modalOpen: false, compositionActive: false, picker: nil)
        XCTAssertTrue(context.canEditDraft)
        XCTAssertEqual(reduce(state: &state, control: .left, context: context), .moveCursor(-1))
        XCTAssertEqual(reduce(state: &state, control: .right, context: context), .moveCursor(1))
        XCTAssertEqual(reduce(state: &state, control: .escape, context: context), .deleteBackward)
        XCTAssertEqual(reduce(state: &state, control: .forceEscape, context: context), .sendEscape)
    }
    func testUnknownIMEStillPreservesCancelForVisibleCandidatesAndModals() {
        for (modal, composing, picker) in [(true, false, nil), (false, true, nil),
                                         (true, false, InteractionMode.sessions)] {
            var state = InteractionState()
            let context = InteractionContext(targetAvailable: true, editorFocused: true,
                modalOpen: modal, compositionActive: composing, picker: picker)
            XCTAssertFalse(context.canEditDraft)
            XCTAssertEqual(reduce(state: &state, control: .escape, context: context), picker == nil ? .sendEscape : .cancelPicker)
        }
    }
    func testCancelNeverTurnsHeldDialIntoClick() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.dial, phase: .down)
            runtime.handle(.dial, phase: .cancel)
            runtime.handle(.dial, phase: .up)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("编辑文字", "Editing text"))
            XCTAssertFalse(runtime.snapshot.pressed.contains(.dial))
            runtime.stop()
        }
    }
    func testPressRotateReleaseDoesNotOpenSessionPicker() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.dial, phase: .down)
            runtime.handle(.left, phase: .pulse)
            runtime.handle(.dial, phase: .up)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("编辑文字", "Editing text"))
            XCTAssertEqual(runtime.snapshot.rotation, -1)
            runtime.stop()
        }
    }
    func testHeldEscapeKeepsDeletingUntilRelease() async throws {
        try await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            let deletions: @MainActor () throws -> Int = { (try runtime.diagnostics()["recentActions"] as? [String])?.count ?? 0 }
            let start = ProcessInfo.processInfo.systemUptime
            runtime.handle(.escape, phase: .down)
            for step in 0..<4 { runtime.advanceGestures(now: start + 0.6 + Double(step) * 0.1) }
            let held = try deletions()
            XCTAssertGreaterThanOrEqual(held, 4)
            runtime.handle(.escape, phase: .up)
            for step in 4..<8 { runtime.advanceGestures(now: start + 0.6 + Double(step) * 0.1) }
            XCTAssertEqual(try deletions(), held)
            runtime.stop()
        }
    }
    func testHardwareDownUpSelectsSessionOnSecondPress() async {
        await MainActor.run {
            let runtime = BridgeRuntime(); runtime.demo = true
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 0.3)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("选择会话", "Choose a chat"))
            runtime.handle(.right, phase: .pulse)
            runtime.handle(.dial, phase: .down); runtime.handle(.dial, phase: .up)
            runtime.advanceGestures(now: ProcessInfo.processInfo.systemUptime + 0.3)
            XCTAssertEqual(runtime.snapshot.mode, L10n.tr("阅读会话", "Reading"))
            XCTAssertEqual(runtime.snapshot.target, L10n.tr("修复登录问题", "Fix sign-in issue"))
            runtime.stop()
        }
    }
    func testEachDictationChoosesItsMicrophoneAndSystemInputOverridesTheDevice() async throws {
        let name = "vibewand-microphone-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        try await MainActor.run {
            let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults),
                engineFactory: { _ in TranscriptReplayEngine(previews: ["测试"]) })
            var route: String? = "handset-microphone"
            voice.microphone = { route }
            voice.beginTest()
            XCTAssertEqual(SpeechAudioInput.deviceUID, "handset-microphone")
            route = nil
            voice.begin()
            XCTAssertNil(SpeechAudioInput.deviceUID)

            let runtime = BridgeRuntime(source: UnconfiguredHIDSource(template: DeviceTemplateID.vibeKey.template),
                templates: DeviceTemplateStore(defaults: defaults), voiceInput: voice)
            var configuration = voice.configuration
            XCTAssertEqual(configuration.effectiveMicrophone, .device)
            configuration.microphone = .system
            try runtime.updateSpeechConfiguration(configuration)
            XCTAssertNil(runtime.deviceMicrophone)

            // A keyboard has no microphone: it records from the one chosen for it, and from this Mac's own
            // while that one is away.
            let keyboard = BridgeRuntime(source: KeyboardInputSource(), templates: DeviceTemplateStore(defaults: defaults), voiceInput: voice)
            configuration.microphone = .device; configuration.keyboardMicrophone = "a-microphone-that-is-away"
            try keyboard.updateSpeechConfiguration(configuration)
            XCTAssertEqual(keyboard.deviceMicrophone, SpeechAudioInput.inputs().first(where: \.builtIn)?.uid)
        }
    }
    /// A dictation that fails is given up once, when it fails. The next one begins as its own: whoever follows
    /// it is told nothing while the failure before still stands, or the text field it was to write into
    /// would be given up with it.
    @MainActor
    func testAFailedDictationIsGivenUpOnceAndTheNextOneBeginsAsItsOwn() async throws {
        let name = "vibewand-failed-dictation-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults), engineFactory: { _ in UnheardEngine() })
        var givenUp = 0, toldAsFailed = false
        voice.onCancel = { givenUp += 1 }
        voice.begin()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(voice.state, .recording)
        voice.end()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(voice.state, .failed(.noSpeech))
        XCTAssertEqual(givenUp, 1)

        voice.onChange = { if case .failed = voice.state { toldAsFailed = true } }
        voice.begin()
        XCTAssertEqual(voice.state, .preparing)
        XCTAssertFalse(toldAsFailed)
        XCTAssertEqual(givenUp, 1)
        voice.cancel()
    }
}

/// A recogniser that hears nothing in what was recorded.
@MainActor
private final class UnheardEngine: DictationEngine {
    func start() async throws {}
    func finish() async throws -> String { throw SpeechInputError.noSpeech }
    func cancel() {}
}
