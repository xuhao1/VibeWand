// Records a region of one display to a ProRes 4444 movie, keeping transparency, with either every window in it
// or only the windows of the named applications (so an overlay can be filmed by itself, whatever lies behind it).
//
//   wincap <out.mov> <seconds> <x> <y> <w> <h> [owner-name ...]
//
// The rectangle is in global points with the origin at the top left of the main display. Frame times are the
// moments the frames were shown; <out.mov>.start holds the wall-clock time of the first one. It stops early
// when <out.mov>.stop appears.
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let startFile: URL
    var first: CMTime?
    var frames = 0

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        startFile = url.appendingPathExtension("start")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, let image = buffer.imageBuffer else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        guard let raw = attachments?.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = buffer.presentationTimeStamp
        if first == nil {
            first = time
            writer.startWriting(); writer.startSession(atSourceTime: .zero)
            let age = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) - CMTimeGetSeconds(time)
            try? String(format: "%.4f\n", Date().timeIntervalSince1970 - age).write(to: startFile, atomically: true, encoding: .utf8)
        }
        guard input.isReadyForMoreMediaData, let first else { return }
        if adaptor.append(image, withPresentationTime: CMTimeSubtract(time, first)) { frames += 1 }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { FileHandle.standardError.write("stream stopped: \(error)\n".data(using: .utf8)!) }
    func finish() async { input.markAsFinished(); await writer.finishWriting() }
}

let arguments = CommandLine.arguments
guard arguments.count >= 7, let seconds = Double(arguments[2]), let x = Double(arguments[3]), let y = Double(arguments[4]),
      let w = Double(arguments[5]), let h = Double(arguments[6]) else {
    print("usage: wincap <out.mov> <seconds> <x> <y> <w> <h> [owner-name ...]"); exit(2)
}
let url = URL(fileURLWithPath: arguments[1]), owners = Array(arguments.dropFirst(7))
let region = CGRect(x: x, y: y, width: w, height: h)
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
guard let display = content.displays.first(where: { $0.frame.intersects(region) }) else { print("no display holds that rectangle"); exit(1) }
let filter: SCContentFilter
if owners.isEmpty {
    filter = SCContentFilter(display: display, excludingWindows: [])
} else {
    let windows = content.windows.filter { window in owners.contains { window.owningApplication?.applicationName.localizedCaseInsensitiveContains($0) ?? false } }
    guard !windows.isEmpty else { print("no window of \(owners) is on screen"); exit(1) }
    filter = SCContentFilter(display: display, including: windows)
}
let scale = Double(filter.pointPixelScale)
let configuration = SCStreamConfiguration()
configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
configuration.width = Int(w * scale); configuration.height = Int(h * scale)
configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
configuration.pixelFormat = kCVPixelFormatType_32BGRA
configuration.showsCursor = ProcessInfo.processInfo.environment["WINCAP_CURSOR"] == "1"
configuration.backgroundColor = .clear
configuration.queueDepth = 8
let recorder = try Recorder(url: url, width: configuration.width, height: configuration.height)
let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "wincap"))
try await stream.startCapture()
let stop = url.appendingPathExtension("stop"), deadline = Date().addingTimeInterval(seconds)
try? FileManager.default.removeItem(at: stop)
while Date() < deadline, !FileManager.default.fileExists(atPath: stop.path) { try await Task.sleep(nanoseconds: 50_000_000) }
try? await stream.stopCapture()
await recorder.finish()
try? FileManager.default.removeItem(at: stop)
print("frames \(recorder.frames) size \(configuration.width)x\(configuration.height)")
