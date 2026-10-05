import XCTest
@testable import WandAgent

final class LineRPCTests: XCTestCase {
    /// Two endpoints joined by pipes, as a client and the process it drives would be.
    private func pair() -> (LineRPC, LineRPC, close: () -> Void) {
        let down = Pipe(), up = Pipe()
        let client = LineRPC(input: up.fileHandleForReading, output: down.fileHandleForWriting)
        let server = LineRPC(input: down.fileHandleForReading, output: up.fileHandleForWriting)
        return (client, server, { try? up.fileHandleForWriting.close() })
    }

    func testRequestIsAnsweredAndNotificationDelivered() async throws {
        let (client, server, _) = pair()
        let notified = expectation(description: "notification")
        server.onRequest = { method, params, reply in
            reply(.success(["echo": .string(method), "value": params["value"] ?? nil]))
        }
        server.onNotification = { method, params in
            if method == "session/cancel", params["sessionId"]?.string == "s1" { notified.fulfill() }
        }
        client.start(); server.start()
        let result = try await client.request("ping", ["value": 3])
        XCTAssertEqual(result, ["echo": "ping", "value": 3])
        client.notify("session/cancel", ["sessionId": "s1"])
        await fulfillment(of: [notified], timeout: 2)
    }

    func testUnhandledRequestAndErrorReplyReachTheCaller() async {
        let (client, server, _) = pair()
        client.start(); server.start()
        do { _ = try await client.request("fs/read_text_file"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? RPCError, .methodNotFound) }
        server.onRequest = { _, _, reply in reply(.failure(RPCError(code: -32602, message: "bad"))) }
        do { _ = try await client.request("x"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? RPCError, RPCError(code: -32602, message: "bad")) }
    }

    func testClosedPeerFailsWaitingRequestsAndSkipsNoise() async {
        let (client, server, closeServerOutput) = pair()
        let closed = expectation(description: "closed")
        client.onClose = { closed.fulfill() }
        // A line that is not JSON, then silence: the request must fail only when the stream ends.
        server.onRequest = { _, _, _ in closeServerOutput() }
        client.start(); server.start()
        do { _ = try await client.request("never"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? RPCError, .closed) }
        await fulfillment(of: [closed], timeout: 2)
        do { _ = try await client.request("after"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? RPCError, .closed) }
    }

    func testMessagesSplitAcrossReadsAreReassembled() async throws {
        let down = Pipe(), up = Pipe()
        let client = LineRPC(input: up.fileHandleForReading, output: down.fileHandleForWriting)
        client.start()
        async let result = client.request("slow")
        _ = down.fileHandleForReading.availableData
        let reply = Data(#"not json at all\n{"id":1,"result":{"title":"麦克风 延迟"}}\n"#.replacingOccurrences(of: "\\n", with: "\n").utf8)
        up.fileHandleForWriting.write(reply.prefix(27))
        try await Task.sleep(nanoseconds: 30_000_000)
        up.fileHandleForWriting.write(reply.dropFirst(27))
        let value = try await result
        XCTAssertEqual(value["title"]?.string, "麦克风 延迟")
    }
}
