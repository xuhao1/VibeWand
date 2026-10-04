import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

@MainActor public enum SpeechAudioInput { public static var deviceUID: String? }

/// Conversion and bounded audio storage stay inside the audio layer. Buffers
/// never cross the UI boundary and recordings are never written to disk.
private final class PCMCollector {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var data = Data()
    private var failure = false
    init(inputFormat: AVAudioFormat) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: format) else { throw SpeechInputError.recordingFailed }
        outputFormat = format; self.converter = converter
    }
    func append(_ input: AVAudioPCMBuffer) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !failure else { return nil }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { failure = true; return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        guard status != .error, error == nil else { failure = true; return nil }
        if let bytes = output.int16ChannelData?[0] {
            let size = Int(output.frameLength) * 2
            guard data.count + size <= 120 * 32000 else { failure = true; return nil }
            let chunk = Data(bytes: bytes, count: size)
            data.append(chunk)
            return chunk
        }
        return nil
    }
    func audio() throws -> SpeechAudio {
        lock.lock(); defer { lock.unlock() }
        guard !failure else { throw SpeechInputError.recordingFailed }
        return SpeechAudio(pcm: data)
    }
}

@MainActor
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var collector: PCMCollector?
    private var tapped = false
    static func authorize() async throws {
        try Task.checkCancellation()
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: allowed = false
        }
        try Task.checkCancellation()
        guard allowed else { throw SpeechInputError.microphoneDenied }
    }
    func start(onBuffer: ((AVAudioPCMBuffer) -> Void)? = nil, onPCM: ((Data) -> Void)? = nil) async throws {
        try await Self.authorize()
        let input = engine.inputNode
        if let uid = SpeechAudioInput.deviceUID {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var identity = uid as CFString, device: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let found = withUnsafePointer(to: &identity) { pointer in
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                    UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
            }
            guard found == noErr, device != 0, let unit = input.audioUnit,
                  AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                      kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
            else { throw SpeechInputError.recordingFailed }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechInputError.recordingFailed }
        let collector = try PCMCollector(inputFormat: format)
        self.collector = collector
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            if let chunk = collector.append(buffer) { onPCM?(chunk) }
            onBuffer?(buffer)
        }
        tapped = true
        engine.prepare()
        do { try engine.start() }
        catch { cancel(); throw SpeechInputError.recordingFailed }
    }
    func stop() throws -> SpeechAudio {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        guard let collector else { throw SpeechInputError.emptyAudio }
        self.collector = nil
        let audio = try collector.audio(); try audio.validate(); return audio
    }
    func cancel() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        collector = nil
    }
    func snapshot() throws -> SpeechAudio {
        guard let collector else { throw SpeechInputError.emptyAudio }
        return try collector.audio()
    }
}

public extension SpeechAudio {
    /// Used for explicit, reproducible API checks with an existing audio file.
    static func read(from url: URL) throws -> SpeechAudio {
        let file = try AVAudioFile(forReading: url)
        guard Double(file.length) / file.processingFormat.sampleRate <= 120 else { throw SpeechInputError.tooLong }
        let collector = try PCMCollector(inputFormat: file.processingFormat)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { throw SpeechInputError.recordingFailed }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            _ = collector.append(buffer)
        }
        let audio = try collector.audio(); try audio.validate(); return audio
    }
}
