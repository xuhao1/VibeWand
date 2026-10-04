import Foundation
import SpeechInput

/// An explicit audio-file check. Keys are read from Keychain, never CLI arguments.
@main
struct SpeechAPICheck {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var streamAudio = false, polishText = false, keyFromStdin = false
        while let flag = arguments.first, flag.hasPrefix("--") {
            if flag == "--stream" { streamAudio = true } else if flag == "--polish" { polishText = true }
            else if flag == "--key-stdin" { keyFromStdin = true } else { break }
            arguments.removeFirst()
        }
        guard arguments.count == 4, let provider = SpeechProvider(rawValue: arguments[0]), provider != .system else {
            print("Usage: SpeechAPICheck [--stream] [--polish] qwenRealtime|transcriptionAPI <endpoint> <model> <audio-file>")
            exit(2)
        }
        do {
            var configuration = SpeechConfiguration()
            configuration.mode = .builtIn; configuration.provider = provider
            configuration.endpoint = arguments[1]; configuration.model = arguments[2]
            let audio = try SpeechAudio.read(from: URL(fileURLWithPath: arguments[3]))
            let key = keyFromStdin ? readLine() : try await KeychainSpeechCredentials().readAsync(account: configuration.credentialAccount)
            let start = Date()
            var text: String
            if streamAudio, provider == .qwenRealtime {
                guard let key else { throw SpeechInputError.missingAPIKey }
                let stream = QwenRealtimeStream()
                var released = false, earlyPreviews = 0
                stream.onPartial = { partial in
                    if !released { earlyPreviews += 1 }
                    print("Preview \(String(format: "%.1f", Date().timeIntervalSince(start)))s (\(released ? "after" : "before") release): \(partial)")
                }
                try await stream.start(configuration: configuration, apiKey: key)
                for offset in stride(from: 0, to: audio.pcm.count, by: 6400) {
                    try await stream.append(audio.pcm.subdata(in: offset..<min(offset + 6400, audio.pcm.count)))
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                released = true
                text = try await stream.finish()
                print("Live previews before release: \(earlyPreviews)")
                guard earlyPreviews > 0 else { throw SpeechInputError.protocolRejected }
            } else { text = try await SpeechAPIClient().transcribe(audio, configuration: configuration, apiKey: key) }
            if polishText {
                guard let settings = configuration.effectivePolishing else { throw SpeechInputError.polishingUnavailable }
                print("Original:", text)
                text = try await SpeechTextProcessor().polish(text, configuration: settings, apiKey: key)
                print("Polished:", text)
            }
            print("Recognized \(String(format: "%.1f", audio.duration))s audio in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            print(text)
        } catch {
            // Network/provider errors are normalized so credentials never reach output.
            let safe = DictationSession.safeError(error)
            print("Speech check failed: \(safe.localizedDescription)")
            exit(1)
        }
    }
}
