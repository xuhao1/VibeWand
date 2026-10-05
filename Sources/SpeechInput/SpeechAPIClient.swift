import Foundation

public struct SpeechAudio: Equatable {
    /// Mono, 16 kHz, signed 16-bit little endian PCM, without a header.
    public let pcm: Data
    public init(pcm: Data) { self.pcm = pcm }
    public var duration: Double { Double(pcm.count) / 32000 }
    public func validate() throws {
        guard pcm.count >= 3200, pcm.count % 2 == 0 else { throw SpeechInputError.emptyAudio }
        guard duration <= 120 else { throw SpeechInputError.tooLong }
    }
    public var wav: Data {
        var data = Data()
        func string(_ s: String) { data.append(Data(s.utf8)) }
        func u16(_ value: UInt16) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        string("RIFF"); u32(UInt32(pcm.count + 36)); string("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        string("data"); u32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}

public protocol SpeechTranscribing {
    func transcribe(_ audio: SpeechAudio, configuration: SpeechConfiguration, apiKey: String?) async throws -> String
}

/// Qwen's Realtime event protocol and multipart /audio/transcriptions are
/// independent adapters. No UI, keyboard events, preferences or secret storage.
public final class SpeechAPIClient: SpeechTranscribing {
    private let session: URLSession
    private let ownsSession: Bool
    public init(session: URLSession? = nil) {
        ownsSession = session == nil
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: SpeechRedirectPolicy(), delegateQueue: nil)
    }
    deinit { if ownsSession { session.invalidateAndCancel() } }
    public func transcribe(_ audio: SpeechAudio, configuration: SpeechConfiguration, apiKey: String?) async throws -> String {
        guard configuration.provider != .system else { throw SpeechInputError.invalidConfiguration }
        try audio.validate(); try configuration.validate(); try Task.checkCancellation()
        if configuration.provider == .qwenRealtime {
            guard let apiKey, !apiKey.isEmpty else { throw SpeechInputError.missingAPIKey }
            let stream = await QwenRealtimeStream()
            try await stream.start(configuration: configuration, apiKey: apiKey)
            for offset in stride(from: 0, to: audio.pcm.count, by: 6400) {
                try await stream.append(audio.pcm.subdata(in: offset..<min(offset + 6400, audio.pcm.count)))
            }
            return try await stream.finish()
        }
        return try await multipart(audio, configuration: configuration, apiKey: apiKey)
    }

    /// An Omni session that only listens. Its recogniser streams previews,
    /// biased by `context`, with no language pinned so mixed speech is
    /// detected; the model writes the transcript under `instructions`.
    public static func sessionUpdate(instructions: String, context: String? = nil) -> [String: Any] {
        var recogniser: [String: Any] = ["model": "qwen3-asr-flash-realtime"]
        if let context { recogniser["corpus"] = ["text": context] }
        return ["type": "session.update", "session": [
            "modalities": ["text"], "turn_detection": NSNull(), "instructions": instructions,
            "input_audio_transcription": recogniser,
            "audio": ["input": ["format": ["type": "pcm", "sample_rate": 16000,
                "sample_format": "s16le", "channels": 1, "packing": "interleaved", "channel_layout": "mono"]]]
        ]]
    }

    static func send(_ event: [String: Any], socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    static func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: throw SpeechInputError.protocolRejected }
        guard data.count < 1_048_576, let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpeechInputError.protocolRejected }
        // Never surface raw provider error text: it may contain credentials or audio.
        if event["type"] as? String == "error" { throw SpeechInputError.protocolRejected }
        return event
    }
    static func waitFor(_ type: String, socket: URLSessionWebSocketTask) async throws {
        while try await receive(socket)["type"] as? String != type { try Task.checkCancellation() }
    }

    public static func multipartBody(_ audio: SpeechAudio, model: String, locale: String, prompt: String? = nil, boundary: String) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in [("model", model), ("language", locale.split(separator: "-").first.map(String.init) ?? locale), ("response_format", "json")]
            + (prompt.map { [("prompt", $0)] } ?? []) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audio.wav); append("\r\n--\(boundary)--\r\n")
        return body
    }
    private func multipart(_ audio: SpeechAudio, configuration: SpeechConfiguration, apiKey: String?) async throws -> String {
        var request = URLRequest(url: try configuration.apiURL()); request.httpMethod = "POST"; request.timeoutInterval = 45
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let boundary = "VibeWand-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(audio, model: configuration.model, locale: configuration.locale,
            prompt: configuration.effectiveVocabulary.context, boundary: boundary)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpeechInputError.protocolRejected }
        guard (200..<300).contains(http.statusCode) else { throw SpeechInputError.http(http.statusCode) }
        guard data.count < 1_048_576, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = value["text"] as? String else { throw SpeechInputError.protocolRejected }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpeechInputError.noSpeech }
        return trimmed
    }
}

/// An imported endpoint cannot redirect a credential-bearing upload elsewhere.
final class SpeechRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
