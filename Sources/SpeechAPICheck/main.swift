import Foundation
import SpeechInput

/// An explicit audio-file check. Keys are read from Keychain, never CLI arguments.
@main
struct SpeechAPICheck {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var streamAudio = false, polishText = false, keyFromStdin = false, listen = false
        var vocabulary = SpeechVocabulary()
        while let flag = arguments.first, flag.hasPrefix("--") {
            if flag == "--stream" { streamAudio = true } else if flag == "--polish" { polishText = true }
            else if flag == "--key-stdin" { keyFromStdin = true }
            // As for a command that goes to the model that listens: only the recogniser's reading is waited for.
            else if flag == "--listen" { streamAudio = true; listen = true }
            else if flag == "--no-vocabulary" { vocabulary.computing = false }
            else if flag == "--terms", arguments.count > 1 { arguments.removeFirst(); vocabulary.terms = SpeechVocabulary.terms(from: arguments[0]) }
            else { break }
            arguments.removeFirst()
        }
        if arguments.first == SpeechProvider.senseVoice.rawValue, arguments.count == 5 { return await senseVoice(Array(arguments.dropFirst())) }
        guard arguments.count == 4, let provider = SpeechProvider(rawValue: arguments[0]), !provider.isLocal else {
            print("Usage: SpeechAPICheck [--stream | --listen] [--polish] [--no-vocabulary] [--terms a,b] qwenRealtime|transcriptionAPI <endpoint> <model> <audio-file>")
            print("       SpeechAPICheck senseVoice <node> <SenseVoice plug-in folder> <model folder> <audio-file>")
            exit(2)
        }
        do {
            var configuration = SpeechConfiguration()
            configuration.mode = .builtIn; configuration.provider = provider
            configuration.endpoint = arguments[1]; configuration.model = arguments[2]
            configuration.vocabulary = vocabulary
            let audio = try SpeechAudio.read(from: URL(fileURLWithPath: arguments[3]))
            let key = keyFromStdin ? readLine() : try await KeychainSpeechCredentials().readAsync(account: configuration.credentialAccount)
            let start = Date()
            var text: String
            if streamAudio, provider == .qwenRealtime {
                guard let key else { throw SpeechInputError.missingAPIKey }
                let stream = QwenRealtimeStream()
                stream.listening = listen
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
                let release = Date()
                text = try await stream.finish()
                print("Text \(String(format: "%.2f", Date().timeIntervalSince(release)))s after release")
                print("Live previews before release: \(earlyPreviews)")
                guard earlyPreviews > 0 else { throw SpeechInputError.protocolRejected }
            } else { text = try await SpeechAPIClient().transcribe(audio, configuration: configuration, apiKey: key) }
            if polishText {
                guard let settings = configuration.effectivePolishing else { throw SpeechInputError.polishingUnavailable }
                print("Original:", text)
                text = try await SpeechTextProcessor().polish(text, configuration: settings, vocabulary: vocabulary, apiKey: key)
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

    /// The recogniser on this Mac, on an audio file: the Node to run it, the folder of the harness's SenseVoice
    /// plug-in, and the folder its models are kept in. Nothing is downloaded here.
    @MainActor static func senseVoice(_ arguments: [String]) async {
        let plugin = URL(fileURLWithPath: arguments[1])
        let service = SenseVoice(runtime: SenseVoice.Runtime(node: URL(fileURLWithPath: arguments[0]), worker: plugin.appendingPathComponent("lib/worker.js"),
            assets: plugin.appendingPathComponent("runtime/assets.json"), stores: [URL(fileURLWithPath: arguments[2])]))
        defer { service.shutdown() }
        do {
            let audio = try SpeechAudio.read(from: URL(fileURLWithPath: arguments[3]))
            var start = Date()
            try await service.prepare()
            let text = try await service.transcribe(audio, configuration: SpeechConfiguration(), apiKey: nil)
            print("Recognized \(String(format: "%.1f", audio.duration))s audio in \(String(format: "%.2f", Date().timeIntervalSince(start)))s, the recogniser's start included")
            start = Date()
            _ = try await service.transcribe(audio, configuration: SpeechConfiguration(), apiKey: nil)
            print("Again, with the recogniser loaded: \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            print(text)
        } catch {
            print("Speech check failed: \(DictationSession.safeError(error).localizedDescription)")
            exit(1)
        }
    }
}
