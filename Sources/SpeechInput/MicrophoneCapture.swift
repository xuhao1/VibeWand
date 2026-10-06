import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

@MainActor public enum SpeechAudioInput {
    /// The input to record from; nil is the macOS default input.
    public static var deviceUID: String?

    /// A USB device's own microphone. Core Audio names its model "Product:VVVV:PPPP".
    public static func deviceUID(vendorID: Int, productID: Int) -> String? {
        let model = String(format: ":%04X:%04X", vendorID, productID)
        return devices().first { string(kAudioDevicePropertyModelUID, of: $0)?.uppercased().hasSuffix(model) == true }
            .flatMap { string(kAudioDevicePropertyDeviceUID, of: $0) }
    }
    /// A microphone the Mac can record from now.
    public struct Input: Equatable, Identifiable, Sendable {
        public var uid: String, name: String
        /// Part of the Mac itself, as opposed to one that was plugged in or paired.
        public var builtIn: Bool
        public var id: String { uid }
    }
    public static func inputs() -> [Input] {
        devices().compactMap { device in
            guard let uid = string(kAudioDevicePropertyDeviceUID, of: device) else { return nil }
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
            return Input(uid: uid, name: string(kAudioObjectPropertyName, of: device) ?? uid, builtIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }
    }
    /// The input a choice stands for now: the chosen one while it is connected, otherwise the Mac's own.
    /// nil, the macOS default input, is left for a Mac that has none of its own.
    public static func resolve(_ chosen: String?) -> String? {
        let inputs = inputs()
        return (inputs.first { $0.uid == chosen } ?? inputs.first(where: \.builtIn))?.uid
    }
    /// Every audio device that has an input stream.
    private static func devices() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr && size > 0
        }
    }
    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    // MARK: Listening from the moment a button goes down

    private static var armed: MicrophoneTap?
    private static var patience: Task<Void, Never>?
    /// Opens `device` (nil is the macOS default input) ahead of a recording that may follow, when a button that
    /// can start one goes down. What it hears stays in memory and goes nowhere: a recording that starts within
    /// a few seconds takes it up and so begins at the press, and otherwise it is dropped.
    public static func arm(_ device: String?) {
        if let armed, armed.device == device { return }
        disarm()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, let tap = try? MicrophoneTap(device: device) else { return }
        armed = tap
        patience = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { disarm() }
        }
    }
    /// The press turned out not to start a recording: what was heard is dropped and the microphone closed.
    public static func disarm() {
        patience?.cancel(); patience = nil
        armed?.stop(); armed = nil
    }
    /// The microphone opened for the recording now starting, if it is the one that recording wants.
    fileprivate static func takeArmed() -> MicrophoneTap? {
        patience?.cancel(); patience = nil
        defer { armed = nil }
        guard let tap = armed, tap.device == deviceUID else { armed?.stop(); return nil }
        return tap
    }
    fileprivate nonisolated static func device(_ uid: String?) -> AudioDeviceID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard let uid else {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr && device != 0 ? device : nil
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var identity = uid as CFString
        let found = withUnsafePointer(to: &identity) { pointer in
            AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return found == noErr && device != 0 ? device : nil
    }
}

/// Conversion and bounded audio storage stay inside the audio layer. Buffers
/// never cross the UI boundary and recordings are never written to disk.
private final class PCMCollector {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private var data = Data()
    private var failure = false
    init() throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else { throw SpeechInputError.recordingFailed }
        outputFormat = format
    }
    func append(_ input: AVAudioPCMBuffer) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !failure else { return nil }
        // The buffers say what the microphone delivers; what an engine reports beforehand can be out of date.
        if converter?.inputFormat != input.format {
            guard let made = AVAudioConverter(from: input.format, to: outputFormat) else { failure = true; return nil }
            // A stereo handset may carry its microphone on either channel.
            made.downmix = true
            converter = made
        }
        guard let converter else { return nil }
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

/// One microphone, read through an audio unit of its own. An audio engine reads the system's default input
/// and output as one device, and when it is pointed at another microphone it reconfigures itself a moment
/// later: a recording that had started by then was stopped under it, and one that had not received nothing.
/// A unit that is given its device before it starts has no such moment.
private final class MicrophoneTap: @unchecked Sendable {
    let device: String?
    private let unit: AudioUnit
    private let format: AVAudioFormat
    private let lock = NSLock()
    /// What was heard before anybody asked for it.
    private var held: [AVAudioPCMBuffer] = []
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var stopped = false

    init(device uid: String?) throws {
        device = uid
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        var made: AudioUnit?
        guard var id = SpeechAudioInput.device(uid), let component = AudioComponentFindNext(nil, &description),
              AudioComponentInstanceNew(component, &made) == noErr, let unit = made else { throw SpeechInputError.recordingFailed }
        self.unit = unit
        // Input only, from this device, in the device's own rate and channels as plain floats.
        var on: UInt32 = 1, off: UInt32 = 0, hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let word = UInt32(MemoryLayout<UInt32>.size)
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, word) == noErr,
              AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, word) == noErr,
              AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, word) == noErr,
              AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size) == noErr,
              hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: hardware.mSampleRate, channels: hardware.mChannelsPerFrame),
              AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, format.streamDescription, size) == noErr
        else { AudioComponentInstanceDispose(unit); throw SpeechInputError.recordingFailed }
        self.format = format
        var heard = AURenderCallbackStruct(inputProc: { context, flags, time, _, frames, _ in
            Unmanaged<MicrophoneTap>.fromOpaque(context).takeUnretainedValue().render(flags, time, frames)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &heard,
                                   UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr,
              AudioUnitInitialize(unit) == noErr, AudioOutputUnitStart(unit) == noErr
        else { AudioComponentInstanceDispose(unit); throw SpeechInputError.recordingFailed }
    }
    private func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ time: UnsafePointer<AudioTimeStamp>, _ frames: UInt32) -> OSStatus {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return noErr }
        buffer.frameLength = frames
        let status = AudioUnitRender(unit, flags, time, 1, frames, buffer.mutableAudioBufferList)
        guard status == noErr else { return status }
        lock.lock(); defer { lock.unlock() }
        if let sink { sink(buffer) } else { held.append(buffer) }
        return noErr
    }
    /// Hands over what was heard so far, in order, and everything from now on.
    func deliver(to sink: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock(); defer { lock.unlock() }
        held.forEach(sink); held = []
        self.sink = sink
    }
    func stop() {
        lock.lock(); let done = stopped; stopped = true; sink = nil; held = []; lock.unlock()
        guard !done else { return }
        AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit)
    }
    deinit { stop() }
}

@MainActor
final class MicrophoneCapture {
    private var tap: MicrophoneTap?
    private var collector: PCMCollector?
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
        cancel()
        let collector = try PCMCollector()
        // A microphone opened when the button went down has been listening since: the recording begins there.
        let tap = try SpeechAudioInput.takeArmed() ?? MicrophoneTap(device: SpeechAudioInput.deviceUID)
        self.collector = collector; self.tap = tap
        tap.deliver { buffer in
            if let chunk = collector.append(buffer) { onPCM?(chunk) }
            onBuffer?(buffer)
        }
    }
    func stop() throws -> SpeechAudio {
        tap?.stop(); tap = nil
        guard let collector else { throw SpeechInputError.emptyAudio }
        self.collector = nil
        let audio = try collector.audio(); try audio.validate(); return audio
    }
    func cancel() {
        tap?.stop(); tap = nil
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
        let collector = try PCMCollector()
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { throw SpeechInputError.recordingFailed }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            _ = collector.append(buffer)
        }
        let audio = try collector.audio(); try audio.validate(); return audio
    }
}
