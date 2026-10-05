import XCTest
@testable import SpeechInput

final class StreamingAndPolishingTests: XCTestCase {
    func testTentativeWordsAreRevisedAndCompletedTextWins() {
        var buffer = SpeechTranscriptBuffer()
        buffer.accept(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "text": "今天", "stash": "天气糟"])
        XCTAssertEqual(buffer.text, "今天天气糟")
        buffer.accept(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "text": "今天", "stash": "天气不错"])
        XCTAssertEqual(buffer.text, "今天天气不错")
        buffer.accept(["type": "conversation.item.input_audio_transcription.completed", "item_id": "a", "transcript": "今天天气不错。"])
        buffer.accept(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "text": "迟到的旧文字"])
        buffer.accept(["type": "conversation.item.input_audio_transcription.delta", "item_id": "b", "text": "", "stash": "Hello 😊"])
        XCTAssertEqual(buffer.text, "今天天气不错。Hello 😊")
        XCTAssertFalse(buffer.accept(["type": "response.text.delta", "delta": "助手回复不能当听写"]))
    }
    func testDedicatedASRPreviewEventsUseTheSameBuffer() {
        var buffer = SpeechTranscriptBuffer()
        XCTAssertTrue(buffer.accept(["type": "conversation.item.input_audio_transcription.text", "item_id": "a", "text": "打开", "stash": " Claude"]))
        XCTAssertEqual(buffer.text, "打开 Claude")
        buffer.accept(["type": "conversation.item.input_audio_transcription.completed", "item_id": "a", "transcript": "打开 Claude Code。"])
        XCTAssertEqual(buffer.text, "打开 Claude Code。")
    }
    func testPolishingInstructionsCarryTheSpeakersVocabulary() {
        var vocabulary = SpeechVocabulary(); vocabulary.computing = false
        XCTAssertEqual(SpeechTextProcessor.instructions(vocabulary: vocabulary), SpeechTextProcessor.instructions)
        vocabulary.domain = "照顾婴儿"; vocabulary.terms = ["安抚奶嘴", "Pampers"]
        var text = SpeechTextProcessor.instructions(vocabulary: vocabulary)
        XCTAssertTrue(text.hasPrefix(SpeechTextProcessor.instructions))
        XCTAssertTrue(text.contains("说话者经常谈论：照顾婴儿。"))
        XCTAssertTrue(text.contains("说话者的专用词汇：安抚奶嘴、Pampers。"))
        vocabulary.computing = true
        text = SpeechTextProcessor.instructions(vocabulary: vocabulary)
        XCTAssertTrue(text.contains("软件开发；照顾婴儿"))
        XCTAssertTrue(text.contains("安抚奶嘴、Pampers、Claude、"))
        XCTAssertTrue(text.contains("VibeWand"))
    }
    func testPolishingSettingsRoundTripNeverContainsCredentials() throws {
        var config = SpeechConfiguration(); config.textStyle = .polished
        config.polishing = SpeechPolishingConfiguration(provider: .chatCompletions, endpoint: "https://text.example/v1", model: "text-model")
        let data = try SpeechPreferences().export(config)
        XCTAssertEqual(try SpeechPreferences().decodeImport(data), config)
        XCTAssertEqual(try config.polishing?.apiURL().path, "/v1/chat/completions")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
        var bad = config.polishing!; bad.endpoint += "?api_key=secret"
        XCTAssertThrowsError(try bad.validate())
    }
    func testQwenPolishingReusesOnlyTheSameDestinationKey() {
        var config = SpeechConfiguration(); config.provider = .qwenRealtime
        config.endpoint = "https://workspace.example/compatible-mode/v1"
        XCTAssertEqual(config.effectivePolishing?.credentialAccount, config.credentialAccount)
        config.polishing = SpeechPolishingConfiguration(provider: .chatCompletions, endpoint: "https://another.example/v1", model: "text")
        XCTAssertNotEqual(config.effectivePolishing?.credentialAccount, config.credentialAccount)
    }
    func testPartialCallbacksAndStyleSwitchDuringRecording() async {
        let engine = await MainActor.run { PreviewEngine() }
        let processor = MemoryPolisher()
        let session = await MainActor.run {
            let session = DictationSession(processor: processor, credentials: EmptyCredentials()) { _ in engine }
            session.begin(SpeechConfiguration()); return session
        }
        await waitFor(session, .recording)
        await MainActor.run {
            engine.onPartialTranscript?("嗯，测试")
            XCTAssertEqual(session.preview, "嗯，测试")
            session.textStyle = .polished; session.end()
        }
        await waitFor(session, .completed)
        await MainActor.run { XCTAssertEqual(session.preview, "整理后的文字") }
        XCTAssertEqual(processor.input, "原始测试文字")
        XCTAssertEqual(processor.vocabulary, SpeechVocabulary())
    }
    func testPolishingFailureKeepsTheOriginalTranscript() async {
        let engine = await MainActor.run { PreviewEngine() }
        let processor = MemoryPolisher(); processor.fail = true
        let session = await MainActor.run {
            let session = DictationSession(processor: processor, credentials: EmptyCredentials()) { _ in engine }
            var config = SpeechConfiguration(); config.textStyle = .polished
            session.begin(config); return session
        }
        await waitFor(session, .recording)
        await MainActor.run { session.end() }
        await waitFor(session, .completed)
        await MainActor.run { XCTAssertEqual(session.preview, "原始测试文字") }
    }
    func testCanceledRecognizerCannotSendLatePreview() async {
        let engine = await MainActor.run { PreviewEngine() }
        let session = await MainActor.run {
            let session = DictationSession { _ in engine }; session.begin(SpeechConfiguration()); return session
        }
        await waitFor(session, .recording)
        await MainActor.run {
            session.cancel(); engine.onPartialTranscript?("迟到文字")
            XCTAssertEqual(session.preview, ""); XCTAssertEqual(session.state, .idle)
        }
    }
    private func waitFor(_ session: DictationSession, _ state: DictationState) async {
        for _ in 0..<200 {
            if await MainActor.run(body: { session.state == state }) { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        await MainActor.run { XCTFail("Unexpected state: \(session.state)") }
    }
}

@MainActor
private final class PreviewEngine: DictationEngine {
    var onPartialTranscript: ((String) -> Void)?
    var onFailure: ((SpeechInputError) -> Void)?
    func start() async throws {}
    func finish() async throws -> String { "原始测试文字" }
    func cancel() {}
}
private struct EmptyCredentials: SpeechCredentialStore {
    func read(account: String) throws -> String? { nil }
    func save(_ key: String, account: String) throws {}
    func remove(account: String) throws {}
}
private final class MemoryPolisher: SpeechTextProcessing {
    var input = "", fail = false, vocabulary: SpeechVocabulary?
    func polish(_ text: String, configuration: SpeechPolishingConfiguration, vocabulary: SpeechVocabulary, apiKey: String?) async throws -> String {
        input = text; self.vocabulary = vocabulary
        if fail { throw SpeechInputError.protocolRejected }
        return "整理后的文字"
    }
}
