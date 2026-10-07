import Foundation

/// The voice service's speech synthesis: a line goes in and comes back as speech, said as written in one of
/// the model's own voices. It is the voice of command mode when the model that acts has none: a model that
/// reads text does the work, and this one says the result.
public enum QwenSpeechSynthesis {
    public static let model = "qwen-audio-3.1-tts-flash"
    public static let sampleRate = 24_000.0
    /// The voice it reads in until the user picks another.
    public static let voice = "longanwen_v3.1"

    /// Where the model is asked: the voice service's own host, which `configuration` names for its Realtime model.
    static func address(_ configuration: SpeechConfiguration) throws -> URL {
        guard var parts = URLComponents(url: try configuration.apiURL(), resolvingAgainstBaseURL: false) else { throw SpeechInputError.invalidEndpoint }
        parts.scheme = parts.scheme == "ws" ? "http" : "https"
        parts.path = "/api/v1/services/audio/tts/SpeechSynthesizer"; parts.query = nil
        guard let url = parts.url else { throw SpeechInputError.invalidEndpoint }
        return url
    }

    /// The speech for `line` in `voice`: mono 16-bit PCM at `sampleRate`. The service answers with where the
    /// audio is, and it is fetched from there.
    public static func read(_ line: String, voice: String, configuration: SpeechConfiguration, apiKey: String) async throws -> Data {
        var request = URLRequest(url: try address(configuration)); request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "input": ["text": line, "voice": voice, "format": "pcm", "sample_rate": Int(sampleRate)]
        ])
        let session = URLSession(configuration: .ephemeral, delegate: SpeechRedirectPolicy(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (answer, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw SpeechInputError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let audio = ((try JSONSerialization.jsonObject(with: answer) as? [String: Any])?["output"] as? [String: Any])?["audio"] as? [String: Any]
        // The audio lies with the service's storage, which is given nothing but the address it handed out.
        guard var place = (audio?["url"] as? String).flatMap(URLComponents.init(string:)) else { throw SpeechInputError.protocolRejected }
        place.scheme = "https"
        guard let url = place.url else { throw SpeechInputError.protocolRejected }
        let (speech, fetched) = try await URLSession.shared.data(from: url)
        guard (fetched as? HTTPURLResponse)?.statusCode == 200 else { throw SpeechInputError.protocolRejected }
        return speech
    }
}
