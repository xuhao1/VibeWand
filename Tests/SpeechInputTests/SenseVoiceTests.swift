import XCTest
import CryptoKit
@testable import SpeechInput

/// SenseVoice through the harness plug-in's recogniser: where its models are looked for, how they are fetched,
/// and what the recogniser is started with. No recogniser is run and nothing leaves this Mac: downloads are
/// answered by a stub.
final class SenseVoiceTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vw-sensevoice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        Hub.files = [:]; Hub.requests = []; Hub.cutAfter = nil
    }

    /// A plug-in folder with a file list in the shape the plug-in ships, naming files of these lengths.
    private func runtime(weights: Int = 5, tokens: Int = 3, vad: Int = 2, stores: [String]) throws -> SenseVoice.Runtime {
        func asset(_ name: String, _ bytes: Int) -> [String: Any] {
            ["name": name, "url": "https://hub.test/org/repo/resolve/abc/\(name)", "bytes": bytes, "sha256": String(repeating: "0", count: 64)]
        }
        let manifest: [String: Any] = ["models": ["int8": asset("model.int8.onnx", weights), "fp32": asset("model.onnx", 9)],
                                       "tokens": asset("tokens.txt", tokens), "vad": asset("silero_vad.onnx", vad)]
        let assets = folder.appendingPathComponent("assets.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: assets)
        return SenseVoice.Runtime(node: URL(fileURLWithPath: "/usr/bin/false"), worker: folder.appendingPathComponent("worker.js"), assets: assets,
                                  stores: stores.map(folder.appendingPathComponent))
    }
    private func put(_ bytes: Int, _ path: String) throws {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: file)
    }

    @MainActor
    func testTheModelsAreUsedWhereAHarnessAlreadyKeepsThemAndOtherwiseOwed() async throws {
        XCTAssertEqual(SenseVoice(runtime: nil).state, .unavailable)
        let runtime = try runtime(stores: ["harness", "own"])
        let service = SenseVoice(runtime: runtime)
        XCTAssertEqual(service.state, .missing)
        XCTAssertEqual(service.downloadSize, 10)
        // Nothing is there yet: a download would go to the first store, the harness's.
        XCTAssertEqual(service.store, runtime.stores[0])
        do { try await service.prepare(); XCTFail("a recording must be refused while the models are missing") }
        catch { XCTAssertEqual(error as? SpeechInputError, .modelMissing) }

        // Complete in VibeWand's own store: that one is used, although the harness's comes first.
        try put(5, "own/models/sensevoice-onnx/model.int8.onnx"); try put(3, "own/models/sensevoice-onnx/tokens.txt")
        service.refresh()
        XCTAssertEqual(service.state, .missing, "the voice detector is still missing")
        try put(2, "own/models/silero/silero_vad.onnx")
        service.refresh()
        XCTAssertEqual(service.state, .ready)
        XCTAssertEqual(service.store, runtime.stores[1])
        // A file cut short is not a model.
        try put(4, "harness/models/sensevoice-onnx/model.int8.onnx"); try put(3, "harness/models/sensevoice-onnx/tokens.txt"); try put(2, "harness/models/silero/silero_vad.onnx")
        service.refresh()
        XCTAssertEqual(service.store, runtime.stores[1])
        // Once the harness has its own complete set, that is the one shared.
        try put(5, "harness/models/sensevoice-onnx/model.int8.onnx")
        service.refresh()
        XCTAssertEqual(service.store, runtime.stores[0])

        // A harness of another version keeps another release under the same name. It is not written over:
        // what VibeWand needs then goes to its own store.
        let other = try self.runtime(weights: 6, stores: ["harness", "elsewhere"])
        let later = SenseVoice(runtime: other)
        XCTAssertEqual(later.state, .missing)
        XCTAssertEqual(later.store, other.stores[1])
    }

    @MainActor
    func testTheRecogniserIsStartedAsThePluginStartsItAndStopsWhenVibeWandIsGone() throws {
        let runtime = try runtime(stores: ["own"])
        let launch = try SenseVoice.launch(runtime, store: runtime.stores[0], files: ["/m/model.int8.onnx", "/m/tokens.txt", "/m/silero_vad.onnx"],
                                           token: String(repeating: "ab", count: 32))
        XCTAssertEqual(launch.arguments.count, 4)
        XCTAssertEqual(launch.arguments[0], "--import")
        XCTAssertTrue(launch.arguments[1].hasPrefix("data:text/javascript,") && launch.arguments[1].contains("process.stdin.on('end'"))
        XCTAssertEqual(launch.arguments[2], runtime.worker.path)
        let configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(launch.arguments[3].utf8)) as? [String: String])
        XCTAssertEqual(configuration, ["dataRoot": runtime.stores[0].path, "model": "/m/model.int8.onnx", "tokens": "/m/tokens.txt", "vad": "/m/silero_vad.onnx"])
        // The token reaches the worker in its environment, as its host hands it over, and nothing of VibeWand's own does.
        XCTAssertEqual(launch.environment["DSH_SPEECH_TOKEN"], String(repeating: "ab", count: 32))
        XCTAssertEqual(Set(launch.environment.keys), ["PATH", "HOME", "TMPDIR", "DSH_SPEECH_TOKEN"])
    }

    func testAFileIsFetchedFromWhicheverOriginAnswersTakenUpWhereItStoppedAndKeptOnlyWhenItMatches() async throws {
        let content = Data((0..<300_000).map { UInt8($0 % 251) })
        let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let asset = SenseVoice.Asset(name: "model.int8.onnx", url: URL(string: "https://hub.test/org/repo/resolve/abc/model.int8.onnx")!,
                                     bytes: Int64(content.count), sha256: digest)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Hub.self]
        let session = URLSession(configuration: configuration)
        let store = folder.appendingPathComponent("models"), target = store.appendingPathComponent(asset.name)
        let origins = ["https://hub.test", "https://mirror.test"]

        // The hub breaks off part way; the mirror is asked for the rest and no more.
        Hub.files = ["hub.test": content, "mirror.test": content]; Hub.cutAfter = ("hub.test", 140_000)
        XCTAssertEqual(SenseVoice.relocate(asset.url, to: origins[1])?.absoluteString, "https://mirror.test/org/repo/resolve/abc/model.int8.onnx")
        let seen = Progress()
        try await SenseVoice.fetch(asset, into: store, session: session, origins: origins) { seen.note($0) }
        XCTAssertEqual(try Data(contentsOf: target), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path + ".part"))
        XCTAssertEqual(Hub.requests.map(\.host), ["hub.test", "mirror.test"])
        XCTAssertNil(Hub.requests[0].range)
        XCTAssertEqual(Hub.requests[1].range, "bytes=140000-")
        XCTAssertEqual(seen.last, asset.bytes)

        // Already complete: nothing is asked of anyone.
        Hub.requests = []
        try await SenseVoice.fetch(asset, into: store, session: session, origins: origins) { _ in }
        XCTAssertTrue(Hub.requests.isEmpty)

        // The right length but not the file the plug-in pins: refused, and nothing of it stays.
        try FileManager.default.removeItem(at: target)
        Hub.cutAfter = nil; Hub.files = ["hub.test": Data(repeating: 1, count: content.count)]
        do { try await SenseVoice.fetch(asset, into: store, session: session, origins: ["https://hub.test"]) { _ in }; XCTFail("a file with another digest was kept") }
        catch { XCTAssertEqual(error as? SpeechInputError, .protocolRejected) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path) || FileManager.default.fileExists(atPath: target.path + ".part"))

        // No origin has it: the failure is the service's answer.
        Hub.files = [:]
        do { try await SenseVoice.fetch(asset, into: store, session: session, origins: origins) { _ in }; XCTFail("a missing file was reported as fetched") }
        catch { XCTAssertEqual(error as? SpeechInputError, .http(404)) }

        // The origins that answer come first, so a hub out of reach is not waited for at every file.
        Hub.files = ["mirror.test": content]
        let ordered = await SenseVoice.ordered(for: asset.url, session: session, among: origins)
        XCTAssertEqual(ordered, ["https://mirror.test", "https://hub.test"])
    }

    /// Opt-in, on the network: the two small model files as the plug-in pins them, fetched from the hub or its
    /// mirror with the app's own code, and one of them taken up again from half way. The weights, 239 MB, are left alone.
    func testLiveModelFilesAreFetchedFromTheHubAndAnInterruptedOneIsTakenUpAgain() async throws {
        guard let plugin = ProcessInfo.processInfo.environment["VIBEWAND_SENSEVOICE_LIVE"] else {
            throw XCTSkip("Set VIBEWAND_SENSEVOICE_LIVE to the folder of the harness's SenseVoice plug-in")
        }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: plugin).appendingPathComponent("runtime/assets.json"))) as? [String: Any])
        func asset(_ key: String) throws -> SenseVoice.Asset {
            let entry = try XCTUnwrap(manifest[key] as? [String: Any])
            return SenseVoice.Asset(name: try XCTUnwrap(entry["name"] as? String), url: try XCTUnwrap(URL(string: entry["url"] as? String ?? "")),
                                    bytes: try XCTUnwrap(entry["bytes"] as? NSNumber).int64Value, sha256: try XCTUnwrap(entry["sha256"] as? String))
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let origins = await SenseVoice.ordered(for: try asset("tokens").url, session: session)
        print("SenseVoice live: origins by who answered first:", origins)
        for key in ["tokens", "vad"] {
            let file = try asset(key), target = folder.appendingPathComponent(file.name)
            try await SenseVoice.fetch(file, into: folder, session: session, origins: origins) { _ in }
            XCTAssertEqual(try SenseVoice.digest(target), file.sha256, file.name)
        }
        // Half of the voice detector as an interrupted transfer would leave it: only the rest is asked for.
        let detector = try asset("vad"), target = folder.appendingPathComponent(detector.name)
        let whole = try Data(contentsOf: target), half = whole.count / 2
        try whole.prefix(half).write(to: URL(fileURLWithPath: target.path + ".part"))
        try FileManager.default.removeItem(at: target)
        let seen = Progress()
        try await SenseVoice.fetch(detector, into: folder, session: session, origins: origins) { seen.note($0) }
        XCTAssertEqual(try Data(contentsOf: target), whole)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(seen.first), Int64(half), "the transfer began again from the start")
        print("SenseVoice live: \(detector.name) resumed at \(half) of \(whole.count) bytes and matches its digest")
    }

    func testSenseVoiceIsALocalServiceWithNoAddressOfItsOwn() throws {
        var configuration = SpeechConfiguration()
        configuration.mode = .builtIn
        configuration.selectProvider(.qwenRealtime)
        let qwen = (configuration.endpoint, configuration.model)
        configuration.selectProvider(.senseVoice)
        XCTAssertTrue(SpeechProvider.senseVoice.isLocal && SpeechProvider.system.isLocal && !SpeechProvider.transcriptionAPI.isLocal)
        // The address set for a service is kept for when it is chosen again, and none is made up for SenseVoice.
        XCTAssertEqual(configuration.apiProfiles?.keys.sorted(), [SpeechProvider.qwenRealtime.rawValue])
        try configuration.validate()
        let restored = try JSONDecoder().decode(SpeechConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(restored.provider, .senseVoice)
        configuration.selectProvider(.qwenRealtime)
        XCTAssertEqual(configuration.endpoint, qwen.0); XCTAssertEqual(configuration.model, qwen.1)
    }
}

private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []
    func note(_ value: Int64) { lock.lock(); values.append(value); lock.unlock() }
    var last: Int64? { lock.lock(); defer { lock.unlock() }; return values.last }
    var first: Int64? { lock.lock(); defer { lock.unlock() }; return values.first }
}

/// Stands for the hub and its mirror: serves the bytes set for a host, honours a range, and can break a transfer off.
private final class Hub: URLProtocol {
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var requests: [(host: String, range: String?)] = []
    nonisolated(unsafe) static var cutAfter: (host: String, bytes: Int)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let host = request.url?.host ?? "", range = request.value(forHTTPHeaderField: "Range")
        if request.httpMethod != "HEAD" { Self.requests.append((host, range)) }
        guard let file = Self.files[host] else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let from = range.flatMap { Int($0.dropFirst("bytes=".count).dropLast()) } ?? 0
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: range == nil ? 200 : 206, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        guard request.httpMethod != "HEAD" else { client?.urlProtocolDidFinishLoading(self); return }
        if let cut = Self.cutAfter, cut.host == host {
            client?.urlProtocol(self, didLoad: file.subdata(in: from..<cut.bytes))
            // A line that drops does so after what it carried has been read.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
        } else {
            client?.urlProtocol(self, didLoad: file.subdata(in: from..<file.count))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
