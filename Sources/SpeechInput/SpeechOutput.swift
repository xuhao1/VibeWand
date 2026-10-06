import AVFoundation
import NaturalLanguage

/// What is said aloud to the user: a line in the system's own voice, or the
/// speech a model streams as it answers. Nothing is kept or written to disk.
@MainActor
public final class SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    /// Stretches of speech handed to the player and not yet played to their end.
    private var queued = 0
    public init() { engine.attach(player) }

    /// Reads a line in the system voice of the language it is written in.
    public func say(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        let language = NLLanguageRecognizer.dominantLanguage(for: text)
        // The recogniser names scripts where the voices are named by region.
        let region: [NLLanguage: String] = [.simplifiedChinese: "zh-CN", .traditionalChinese: "zh-TW"]
        if let language {
            // The best voice of that language the user has installed; the compact one every Mac has sounds mechanical.
            let wanted = region[language] ?? language.rawValue
            let installed = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == wanted || $0.language.hasPrefix(wanted + "-") }
            utterance.voice = installed.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: wanted)
        }
        synthesizer.speak(utterance)
    }

    /// Plays the next stretch of streamed speech: mono 16-bit PCM at `sampleRate`.
    public func play(_ pcm: Data, sampleRate: Double) {
        if format?.sampleRate != sampleRate {
            guard let wanted = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return }
            player.stop(); engine.stop()
            engine.connect(player, to: engine.mainMixerNode, format: wanted)
            format = wanted
        }
        let frames = pcm.count / 2
        guard let format, frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0] else { return }
        pcm.withUnsafeBytes { bytes in
            for index in 0..<frames { samples[index] = Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768 }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        if !engine.isRunning { guard (try? engine.start()) != nil else { return } }
        queued += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.played() }
        }
        if !player.isPlaying { player.play() }
    }
    /// The output is let go once the last stretch has been heard, so that nothing is kept running between answers.
    private func played() {
        queued = max(0, queued - 1)
        if queued == 0 { engine.stop() }
    }

    /// Falls silent at once.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if format != nil { player.stop(); engine.stop() }
    }
}
