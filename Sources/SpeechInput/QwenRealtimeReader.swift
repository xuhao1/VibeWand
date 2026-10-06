import Foundation

/// The voice service's speech synthesis: a line goes in and comes out as speech,
/// said exactly as written. It is for what VibeWand itself has to say, a
/// question or a result, which the Omni model might answer instead of reading;
/// given the voice the Omni model speaks in, both sound like one speaker.
@MainActor
public enum QwenRealtimeReader {
    public nonisolated static let model = "qwen3-tts-flash-realtime"
    /// A voice both this model and the Omni model have. Asked for by name, since their own defaults differ.
    public nonisolated static let voice = "Serena"

    /// Reads `line` aloud and hands on the speech as it arrives: mono 16-bit PCM at `QwenRealtimeConversation.sampleRate`.
    /// `configuration` is the voice service's; the synthesis model is reached at the same address with the same key.
    public static func read(_ line: String, voice: String = voice, configuration: SpeechConfiguration, apiKey: String,
                            sound: (Data) -> Void) async throws {
        var service = configuration
        service.model = model
        var request = URLRequest(url: try service.apiURL()); request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral, delegate: SpeechRedirectPolicy(), delegateQueue: nil)
        let socket = session.webSocketTask(with: request); socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        try await withTaskCancellationHandler(operation: {
            try await SpeechAPIClient.waitFor("session.created", socket: socket)
            try await SpeechAPIClient.send(["type": "session.update", "session": ["voice": voice, "response_format": "pcm", "mode": "commit"]], socket: socket)
            try await SpeechAPIClient.waitFor("session.updated", socket: socket)
            try await SpeechAPIClient.send(["type": "input_text_buffer.append", "text": line], socket: socket)
            try await SpeechAPIClient.send(["type": "input_text_buffer.commit"], socket: socket)
            while true {
                let message = try await SpeechAPIClient.receive(socket)
                switch message["type"] as? String {
                case "response.audio.delta":
                    if let speech = (message["delta"] as? String).flatMap({ Data(base64Encoded: $0) }) { sound(speech) }
                case "response.done": return
                default: break
                }
            }
        }, onCancel: { socket.cancel(with: .goingAway, reason: nil) })
    }
}
