import XCTest
@testable import WandAgent

final class ToolSocketTests: XCTestCase {
    private func connect(_ path: String) throws -> LineRPC {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw POSIXError(.ECONNREFUSED) }
        // The server drops refused peers; a write after that must fail, not kill the test run.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let rpc = LineRPC(input: handle, output: handle); rpc.start()
        return rpc
    }
    private func path() -> String { NSTemporaryDirectory() + "vw-test-\(UInt32.random(in: 0...UInt32.max)).sock" }

    func testServesTheCatalogAndRoutesCalls() async throws {
        let socket = try ToolSocket(path: path()) { name, arguments in
            name == "open_session" ? .ok(["opened": arguments["id"] ?? nil]) : .failure("nope")
        }
        defer { socket.close() }
        let client = try connect(socket.path)
        // Clients that speak a newer protocol probe first and fall back when declined.
        do { _ = try await client.request("server/discover"); XCTFail("expected a refusal") }
        catch { XCTAssertEqual(error as? RPCError, .methodNotFound) }
        let hello = try await client.request("initialize", ["protocolVersion": "2025-11-25"])
        XCTAssertEqual(hello["protocolVersion"]?.string, "2025-11-25")
        XCTAssertNotNil(hello["capabilities"]?["tools"])
        let listed = try await client.request("tools/list")
        XCTAssertEqual(listed["tools"]?.array?.compactMap { $0["name"]?.string }, ToolCatalog.all.map(\.name))
        XCTAssertEqual(listed["tools"]?.array?.first?["inputSchema"]?["type"]?.string, "object")
        let opened = try await client.request("tools/call", ["name": "open_session", "arguments": ["app": "codex", "id": "t-1"]])
        XCTAssertEqual(opened["isError"], false)
        XCTAssertEqual(opened["content"]?.array?.first?["text"]?.string, #"{"opened":"t-1"}"#)
        let refused = try await client.request("tools/call", ["name": "rm"])
        XCTAssertEqual(refused["isError"], true)
    }

    func testOnlyAnAdmittedProcessMayConnect() async throws {
        let socket = try ToolSocket(path: path()) { _, _ in .ok("ok") }
        defer { socket.close() }
        var asked: [pid_t] = []
        socket.admits = { asked.append($0); return false }
        let client = try connect(socket.path)
        do { _ = try await client.request("tools/list"); XCTFail("expected the connection to be dropped") }
        catch { XCTAssertEqual(error as? RPCError, .closed) }
        XCTAssertEqual(asked, [getpid()])
    }

    func testRelayIsNetcatOnTheSocketAndThePathIsPrivate() throws {
        let socket = try ToolSocket(path: path()) { _, _ in .ok("ok") }
        defer { socket.close() }
        XCTAssertEqual(socket.relay, ToolRelay(name: "vibewand", command: "/usr/bin/nc", arguments: ["-U", socket.path]))
        let mode = try FileManager.default.attributesOfItem(atPath: socket.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        socket.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket.path))
    }

    func testProcessTreeFollowsParents() throws {
        XCTAssertTrue(ProcessTree.descends(getpid(), from: getpid()))
        XCTAssertFalse(ProcessTree.descends(1, from: getpid()))
        // A grandchild, as netcat is to the app when the kernel starts it.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "/bin/sleep 5 & echo $!; wait"]
        let output = Pipe(); child.standardOutput = output
        try child.run()
        defer { child.terminate() }
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        let grandchild = try XCTUnwrap(pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(ProcessTree.descends(grandchild, from: getpid()))
        XCTAssertTrue(ProcessTree.descends(grandchild, from: child.processIdentifier))
        XCTAssertFalse(ProcessTree.descends(getpid(), from: grandchild))
    }
}
