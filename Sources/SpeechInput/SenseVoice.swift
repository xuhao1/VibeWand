import Foundation
import CryptoKit

/// SenseVoice on this Mac, through the recogniser of DeepSeek Harness's SenseVoice plug-in: the plug-in's own
/// worker script, started the way the plug-in starts it, on the model files the plug-in names, kept where a
/// harness keeps them so that neither downloads what the other already has. A recording goes to that process
/// over the loopback interface and nowhere else.
@MainActor
public final class SenseVoice: SpeechTranscribing {
    /// What the plug-in consists of on disk. This type knows nothing of where a harness puts it.
    public struct Runtime: Equatable, Sendable {
        /// The Node the worker runs on, the plug-in's worker script, and its list of model files.
        public var node: URL, worker: URL, assets: URL
        /// The folders a harness keeps the plug-in's data in. The first that holds the models is used,
        /// and a download goes into the first of all.
        public var stores: [URL]
        public init(node: URL, worker: URL, assets: URL, stores: [URL]) {
            self.node = node; self.worker = worker; self.assets = assets; self.stores = stores
        }
    }
    public enum State: Equatable {
        /// This build carries no recogniser to run.
        case unavailable
        /// The models have to be downloaded first.
        case missing
        /// A download is under way; the fraction that has arrived.
        case downloading(Double)
        case ready
        /// The last download did not finish. What arrived is kept for the next try.
        case failed
    }

    /// One file the recogniser loads, as the plug-in pins it: where it comes from, how long it is, and its digest.
    struct Asset: Decodable, Equatable, Sendable {
        var name: String, url: URL, bytes: Int64, sha256: String
    }
    private struct Manifest: Decodable {
        var models: [String: Asset], tokens: Asset, vad: Asset
    }
    /// The quantised weights: a quarter of the full ones in size, and what the plug-in itself defaults to.
    nonisolated static let precision = "int8"
    /// Where the files are fetched from, as the plug-in has it: the hub, and a mirror for networks that cannot reach it.
    nonisolated static let origins = ["https://huggingface.co", "https://hf-mirror.com"]
    /// After this long without a recording the recogniser is let go; its memory is worth more than its start-up.
    nonisolated static let idleSeconds: UInt64 = 300

    public private(set) var state: State = .unavailable { didSet { if state != oldValue { onChange?() } } }
    public var onChange: (() -> Void)?
    private let runtime: Runtime?
    private let files: [(asset: Asset, folder: String)]
    private let session: URLSession
    private var download: Task<Void, Never>?
    private var worker: (process: Process, input: Pipe, port: Int, token: String)?
    private var starting: Task<Void, Error>?
    private var rest: Task<Void, Never>?

    /// `runtime` is nil when the app carries no recogniser, which leaves SenseVoice unavailable.
    public init(runtime: Runtime?) {
        let manifest = runtime.flatMap { try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: $0.assets)) }
        let weights = manifest?.models[Self.precision]
        self.runtime = manifest == nil || weights == nil ? nil : runtime
        files = manifest.flatMap { manifest in
            weights.map { [($0, "models/sensevoice-onnx"), (manifest.tokens, "models/sensevoice-onnx"), (manifest.vad, "models/silero")] }
        } ?? []
        // The recording stays on this Mac: a proxy set for the system must not be handed a loopback request.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
        refresh()
    }

    /// Bytes still to fetch before the models are complete.
    public var downloadSize: Int64 { files.reduce(0) { $0 + $1.asset.bytes } }
    /// The folder the models are in, or the one a download would put them in.
    public var store: URL? { located ?? destination }
    /// The store that holds every file at its full length.
    private var located: URL? {
        runtime?.stores.first { store in files.allSatisfy { Self.length(Self.place($0, in: store)) == $0.asset.bytes } }
    }
    /// Where a download goes: the first store, unless a file there has the same name and another length. That is
    /// another release of the model, kept by a harness of another version, and it stays that harness's. The last
    /// store is VibeWand's own and takes what no other can.
    private var destination: URL? {
        runtime?.stores.first { store in
            files.allSatisfy { file in Self.length(Self.place(file, in: store)).map { $0 == file.asset.bytes } ?? true }
        } ?? runtime?.stores.last
    }
    private nonisolated static func place(_ file: (asset: Asset, folder: String), in store: URL) -> URL {
        store.appendingPathComponent(file.folder).appendingPathComponent(file.asset.name)
    }
    private nonisolated static func length(_ file: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
    }

    /// Looks again at what is on disk; a harness may have fetched the models in the meantime.
    public func refresh() {
        guard runtime != nil else { state = .unavailable; return }
        if case .downloading = state { return }
        state = located != nil ? .ready : state == .failed ? .failed : .missing
    }

    // MARK: Fetching the models

    public func startDownload() {
        guard download == nil, located == nil, let store = destination else { return }
        state = .downloading(0)
        download = Task { [weak self, files, session = URLSession(configuration: .ephemeral)] in
            defer { session.invalidateAndCancel() }
            do {
                let total = Double(files.reduce(0) { $0 + $1.asset.bytes })
                // Asked with the smallest file: a hub this network cannot reach is not waited for three times over.
                let origins = await Self.ordered(for: files[1].asset.url, session: session)
                var done: Int64 = 0
                for file in files {
                    let folder = store.appendingPathComponent(file.folder)
                    let base = done
                    try await Self.fetch(file.asset, into: folder, session: session, origins: origins) { [weak self] received in
                        Task { @MainActor in
                            guard let self, case .downloading = self.state else { return }
                            self.state = .downloading(Double(base + received) / total)
                        }
                    }
                    done += file.asset.bytes
                }
                self?.download = nil; self?.state = .ready
            } catch {
                self?.download = nil
                self?.state = error is CancellationError ? .missing : .failed
            }
        }
    }
    public func cancelDownload() { download?.cancel() }

    /// The same file at another origin: hubs and their mirrors serve one path.
    nonisolated static func relocate(_ url: URL, to origin: String) -> URL? {
        guard var source = URLComponents(url: url, resolvingAgainstBaseURL: false), let target = URLComponents(string: origin) else { return nil }
        source.scheme = target.scheme; source.host = target.host; source.port = target.port
        return source.url
    }
    /// The origins that answer for a file, quickest first, and then the others.
    nonisolated static func ordered(for sample: URL, session: URLSession, among origins: [String] = SenseVoice.origins) async -> [String] {
        let answering = await withTaskGroup(of: String?.self) { group -> [String] in
            for origin in origins {
                group.addTask {
                    guard let url = relocate(sample, to: origin) else { return nil }
                    var request = URLRequest(url: url, timeoutInterval: 3)
                    request.httpMethod = "HEAD"
                    let status = ((try? await session.data(for: request))?.1 as? HTTPURLResponse)?.statusCode ?? 0
                    return (200..<300).contains(status) ? origin : nil
                }
            }
            var found: [String] = []
            for await origin in group { if let origin { found.append(origin) } }
            return found
        }
        return answering + origins.filter { !answering.contains($0) }
    }

    /// Brings one file to `folder` under its own name, complete and matching its digest. A file already there at
    /// full length is left as it is. An interrupted transfer is taken up where it stopped, from whichever origin answers.
    nonisolated static func fetch(_ asset: Asset, into folder: URL, session: URLSession, origins: [String] = SenseVoice.origins,
                                  progress: @escaping @Sendable (Int64) -> Void) async throws {
        let target = folder.appendingPathComponent(asset.name), partial = folder.appendingPathComponent(asset.name + ".part")
        guard length(target) != asset.bytes else { progress(asset.bytes); return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var failure: Error = SpeechInputError.unavailable
        for attempt in 0..<8 where (length(partial) ?? 0) < asset.bytes {
            try Task.checkCancellation()
            guard let source = relocate(asset.url, to: origins[attempt % origins.count]) else { throw SpeechInputError.invalidConfiguration }
            let have = length(partial) ?? 0
            var request = URLRequest(url: source, timeoutInterval: 20)
            if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
            do {
                let (bytes, response) = try await session.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // A server that ignores the range sends the whole file again.
                guard status == 206 || status == 200 else { throw SpeechInputError.http(status) }
                if status == 200 { try? FileManager.default.removeItem(at: partial) }
                if !FileManager.default.fileExists(atPath: partial.path) { FileManager.default.createFile(atPath: partial.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: partial)
                var received = try handle.seekToEnd(), buffer = Data()
                buffer.reserveCapacity(1 << 17)
                // What has arrived is kept however the transfer ends: the next attempt asks only for the rest.
                defer { try? handle.write(contentsOf: buffer); try? handle.close() }
                for try await byte in bytes {
                    buffer.append(byte)
                    guard buffer.count == 1 << 17 else { continue }
                    try handle.write(contentsOf: buffer)
                    received += UInt64(buffer.count); buffer.removeAll(keepingCapacity: true)
                    progress(Int64(received))
                }
            } catch let error where !(error is CancellationError) {
                failure = error
            }
        }
        guard length(partial) == asset.bytes else { throw failure }
        guard try digest(partial) == asset.sha256 else {
            // Not the file the plug-in pins: nothing of it is kept.
            try? FileManager.default.removeItem(at: partial)
            throw SpeechInputError.protocolRejected
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
        progress(asset.bytes)
    }
    nonisolated static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The recogniser

    /// Called when a recording starts: the models have to be there, and the recogniser is woken so that it is
    /// loaded by the time the speaker stops.
    public func prepare() async throws {
        guard runtime != nil else { throw SpeechInputError.invalidConfiguration }
        guard located != nil else { refresh(); throw SpeechInputError.modelMissing }
        rest?.cancel()
        wake()
    }
    private func wake() {
        guard worker?.process.isRunning != true, starting == nil else { return }
        worker = nil
        starting = Task {
            defer { self.starting = nil }
            try await self.start()
        }
    }

    public func transcribe(_ audio: SpeechAudio, configuration: SpeechConfiguration, apiKey: String?) async throws -> String {
        try audio.validate()
        rest?.cancel()
        wake()
        if let starting { try await starting.value }
        guard let worker else { throw SpeechInputError.unavailable }
        defer { settle() }
        // No language is pinned: speech that mixes Chinese and English is the ordinary case here.
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(worker.port)/transcribe?language=auto")!, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(worker.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.upload(for: request, from: audio.wav)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpeechInputError.http(status) }
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = reply["text"] as? String else {
            throw SpeechInputError.protocolRejected
        }
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { throw SpeechInputError.noSpeech }
        return said
    }

    /// The arguments and environment the plug-in's own host gives its worker, for these files.
    static func launch(_ runtime: Runtime, store: URL, files: [String], token: String) throws -> (arguments: [String], environment: [String: String]) {
        let configuration: [String: String] = ["dataRoot": store.path, "model": files[0], "tokens": files[1], "vad": files[2]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys]), as: UTF8.self)
        // The worker listens until it is stopped. It is also to stop when VibeWand is gone without having stopped it,
        // which it learns from its input closing.
        let leash = "data:text/javascript,process.stdin.resume();process.stdin.on('end',()=>process.exit(0))"
        return (["--import", leash, runtime.worker.path, json],
                ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "DSH_SPEECH_TOKEN": token])
    }

    private func start() async throws {
        guard let runtime, let store = located else { throw SpeechInputError.modelMissing }
        let paths = files.map { Self.place($0, in: store).path }
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        let launch = try Self.launch(runtime, store: store, files: paths, token: token)
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = runtime.node
        process.arguments = launch.arguments; process.environment = launch.environment
        process.currentDirectoryURL = store
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        // The worker prints one line once the models are loaded: the port it listens on.
        let port: Int? = await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                var lines = output.fileHandleForReading.bytes.lines.makeAsyncIterator()
                guard let line = try? await lines.next() else { return nil }
                return (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["port"] as? Int
            }
            group.addTask { try? await Task.sleep(nanoseconds: 60_000_000_000); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let port, process.isRunning else {
            process.terminate()
            throw SpeechInputError.unavailable
        }
        worker = (process, input, port, token)
    }

    private func settle() {
        rest?.cancel()
        rest = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.shutdown()
        }
    }

    /// Lets the recogniser go. The next recording starts it again.
    public func shutdown() {
        rest?.cancel(); rest = nil
        starting?.cancel(); starting = nil
        worker?.process.terminate(); worker = nil
    }
}
