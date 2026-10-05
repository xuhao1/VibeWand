import XCTest
@testable import SpeechInput

final class SpeechInputTests: XCTestCase {
    func testChangingProvidersRetainsTheirEndpointsAndModels() throws {
        var config = SpeechConfiguration(); config.provider = .qwenRealtime
        config.endpoint = "wss://workspace.example/api-ws/v1/realtime"
        config.selectProvider(.system); config.selectProvider(.transcriptionAPI)
        config.endpoint = "http://localhost:8080/v1"; config.model = "local-sensevoice"
        config.selectProvider(.qwenRealtime)
        XCTAssertEqual(config.endpoint, "wss://workspace.example/api-ws/v1/realtime")
        config.selectProvider(.transcriptionAPI)
        XCTAssertEqual(config.endpoint, "http://localhost:8080/v1")
        XCTAssertEqual(config.model, "local-sensevoice")
        try config.validate()
    }
    func testWorkspaceBasesResolveToQwenRealtimeAndCredentialsBindToDestination() throws {
        var config = SpeechConfiguration(); config.provider = .qwenRealtime
        config.endpoint = "https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
        XCTAssertEqual(try config.apiURL().absoluteString, "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.8-omni-flash-realtime")
        let account = config.credentialAccount
        config.endpoint = "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime"
        XCTAssertEqual(account, config.credentialAccount)
        config.endpoint = "HTTPS://WORKSPACE.cn-beijing.maas.aliyuncs.com/api/v1/"
        XCTAssertEqual(account, config.credentialAccount)
        config.endpoint = "wss://another.example/api-ws/v1/realtime"
        XCTAssertNotEqual(account, config.credentialAccount)
    }
    func testCredentialsCannotHideInsideSharedEndpoint() {
        for endpoint in ["https://user:secret@example.com/v1", "https://example.com/v1?api_key=secret", "https://example.com/v1#secret", "http://example.com/v1"] {
            var config = SpeechConfiguration(); config.endpoint = endpoint
            XCTAssertThrowsError(try config.validate())
        }
    }
    func testShareRoundTripContainsPreferencesOnly() throws {
        let suite = "speech-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpeechPreferences(defaults: defaults)
        var config = SpeechConfiguration(); config.mode = .builtIn; config.provider = .qwenRealtime
        try preferences.save(config)
        XCTAssertEqual(preferences.load(), config)
        let data = try preferences.export(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "mode", "provider", "locale", "endpoint", "model"])
        XCTAssertEqual(try preferences.decodeImport(data), config)
    }
    func testMultipartContainsPlayableWavAndLanguage() throws {
        var config = SpeechConfiguration(); config.provider = .transcriptionAPI; config.endpoint = "http://localhost:8080/v1"; config.model = "whisper-1"
        XCTAssertEqual(try config.apiURL().absoluteString, "http://localhost:8080/v1/audio/transcriptions")
        let audio = SpeechAudio(pcm: Data(repeating: 0, count: 32000))
        XCTAssertEqual(audio.duration, 1)
        XCTAssertEqual(audio.wav.count, 32044)
        XCTAssertEqual(String(decoding: audio.wav.prefix(4), as: UTF8.self), "RIFF")
        let body = SpeechAPIClient.multipartBody(audio, model: config.model, locale: "zh-CN", boundary: "test")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("filename=\"dictation.wav\""))
        XCTAssertTrue(text.contains("\r\n\r\nzh\r\n"))
        XCTAssertTrue(body.range(of: audio.wav) != nil)
    }
    func testQwenRecognisesOnTheASRModelWithVocabularyContext() throws {
        var config = SpeechConfiguration(); config.provider = .qwenRealtime
        XCTAssertEqual(try config.recognitionURL().query, "model=qwen3-asr-flash-realtime")
        XCTAssertEqual(try config.apiURL().query, "model=qwen3.8-omni-flash-realtime")
        XCTAssertEqual(try config.recognitionURL().host, try config.apiURL().host)
        config.model = "qwen3-asr-flash-realtime-2026-02-10"
        XCTAssertEqual(try config.recognitionURL(), try config.apiURL())

        let session = try XCTUnwrap(SpeechAPIClient.sessionUpdate(context: "VibeWand")["session"] as? [String: Any])
        XCTAssertTrue(session["turn_detection"] is NSNull)
        XCTAssertEqual(session["modalities"] as? [String], ["text"])
        XCTAssertEqual(session["input_audio_format"] as? String, "pcm")
        XCTAssertEqual(session["sample_rate"] as? Int, 16000)
        let transcription = try XCTUnwrap(session["input_audio_transcription"] as? [String: Any])
        XCTAssertEqual((transcription["corpus"] as? [String: String])?["text"], "VibeWand")
        XCTAssertNil(transcription["language"])
        let plain = try XCTUnwrap(SpeechAPIClient.sessionUpdate()["session"] as? [String: Any])
        XCTAssertEqual((plain["input_audio_transcription"] as? [String: Any])?.isEmpty, true)
    }
    func testVocabularyOrdersContextAndParsesTypedTerms() throws {
        var vocabulary = SpeechVocabulary()
        XCTAssertTrue(try XCTUnwrap(vocabulary.context).contains("Claude Code"))
        vocabulary.domain = "新能源汽车"
        vocabulary.terms = SpeechVocabulary.terms(from: "刀片电池， 比亚迪\n\n热管理、BMS; ")
        XCTAssertEqual(vocabulary.terms, ["刀片电池", "比亚迪", "热管理", "BMS"])
        XCTAssertEqual(vocabulary.allTerms.prefix(2), ["刀片电池", "比亚迪"])
        let lines = try XCTUnwrap(vocabulary.context).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1], "新能源汽车")
        XCTAssertEqual(lines[2], "刀片电池, 比亚迪, 热管理, BMS")
        vocabulary.computing = false
        XCTAssertEqual(vocabulary.context, "新能源汽车\n刀片电池, 比亚迪, 热管理, BMS")
        XCTAssertNil({ var empty = SpeechVocabulary(); empty.computing = false; return empty.context }())
    }
    func testVocabularyAndMicrophoneAreSharedAndOversizedListsRejected() throws {
        var config = SpeechConfiguration()
        XCTAssertEqual(config.effectiveMicrophone, .device)
        XCTAssertEqual(config.effectiveVocabulary, SpeechVocabulary())
        config.microphone = .system
        var vocabulary = SpeechVocabulary(); vocabulary.domain = "机器人"; vocabulary.terms = ["灵巧手"]
        config.vocabulary = vocabulary
        let data = try SpeechPreferences().export(config)
        XCTAssertEqual(try SpeechPreferences().decodeImport(data), config)
        config.vocabulary?.terms = Array(repeating: "一个很长的专用词汇条目", count: 400)
        XCTAssertThrowsError(try config.validate())
    }
    func testCompatibleAPIReceivesVocabularyAsPrompt() {
        let audio = SpeechAudio(pcm: Data(repeating: 0, count: 32000))
        let body = SpeechAPIClient.multipartBody(audio, model: "whisper-1", locale: "zh-CN", prompt: "刀片电池", boundary: "test")
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("name=\"prompt\"\r\n\r\n刀片电池\r\n"))
        let plain = SpeechAPIClient.multipartBody(audio, model: "whisper-1", locale: "zh-CN", boundary: "test")
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("name=\"prompt\""))
    }
    func testSafeErrorsDoNotExposeServiceResponseOrKeys() async {
        await MainActor.run {
            let error = NSError(domain: "sk-test-private", code: 401, userInfo: [NSLocalizedDescriptionKey: "sk-test-private"])
            XCTAssertEqual(DictationSession.safeError(error), .protocolRejected)
            XCTAssertFalse(DictationSession.safeError(error).localizedDescription.contains("sk-test-private"))
        }
    }
    func testCompatibleAPIActuallyUploadsAudioAndReadsTranscript() async throws {
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [StubSpeechProtocol.self]
        let session = URLSession(configuration: urlConfiguration)
        defer { session.invalidateAndCancel() }
        StubSpeechProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-credential")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            return (200, Data("{\"text\":\" 测试文字 \"}".utf8))
        }
        var config = SpeechConfiguration(); config.provider = .transcriptionAPI
        config.endpoint = "https://speech.example/v1"; config.model = "whisper-1"
        let text = try await SpeechAPIClient(session: session).transcribe(SpeechAudio(pcm: Data(repeating: 0, count: 32000)), configuration: config, apiKey: "test-credential")
        XCTAssertEqual(text, "测试文字")
    }
    func testProviderHTTPErrorBodyIsNeverSurfaced() async throws {
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [StubSpeechProtocol.self]
        let session = URLSession(configuration: urlConfiguration)
        defer { session.invalidateAndCancel() }
        StubSpeechProtocol.handler = { _ in (401, Data("private-key-echo-in-error".utf8)) }
        var config = SpeechConfiguration(); config.provider = .transcriptionAPI; config.endpoint = "https://speech.example/v1"
        do {
            _ = try await SpeechAPIClient(session: session).transcribe(SpeechAudio(pcm: Data(repeating: 0, count: 32000)), configuration: config, apiKey: "test-credential")
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? SpeechInputError, .http(401))
            XCTAssertFalse(error.localizedDescription.contains("private-key-echo-in-error"))
        }
    }
    func testReleaseDuringPermissionWaitNeverRecordsLater() async {
        let (session, engine) = await MainActor.run { () -> (DictationSession, FakeEngine) in
            let engine = FakeEngine(); engine.waitOnStart = true
            let session = DictationSession { _ in engine }
            session.begin(SpeechConfiguration()); return (session, engine)
        }
        await Task.yield()
        await MainActor.run { session.end(); engine.resumeStart() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await MainActor.run { XCTAssertEqual(session.state, .idle); XCTAssertFalse(engine.running) }
    }
    func testCanceledDelayedTranscriptNeverReachesConsumer() async {
        let (session, engine) = await MainActor.run { () -> (DictationSession, FakeEngine) in
            let engine = FakeEngine(); engine.waitOnFinish = true
            let session = DictationSession { _ in engine }
            session.onTranscript = { _ in XCTFail("Canceled result was delivered") }
            session.begin(SpeechConfiguration()); return (session, engine)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await MainActor.run { XCTAssertEqual(session.state, .recording); session.end() }
        await Task.yield()
        await MainActor.run { session.cancel(); engine.resumeFinish() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await MainActor.run { XCTAssertEqual(session.state, .idle) }
    }
}

private final class StubSpeechProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (code, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class FakeEngine: DictationEngine {
    var waitOnStart = false, waitOnFinish = false, running = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    func start() async throws {
        if waitOnStart { await withCheckedContinuation { startContinuation = $0 } }
        try Task.checkCancellation(); running = true
    }
    func finish() async throws -> String {
        if waitOnFinish { await withCheckedContinuation { finishContinuation = $0 } }
        return "test transcript"
    }
    func cancel() { running = false }
    func resumeStart() { startContinuation?.resume(); startContinuation = nil }
    func resumeFinish() { finishContinuation?.resume(); finishContinuation = nil }
}
