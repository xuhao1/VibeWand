import XCTest
@testable import WandAgent

final class ModelEndpointTests: XCTestCase {
    /// A harness's model client posts a chat request and reads the answer as a stream of chunks.
    func testAReplyIsStreamedToWhoeverHoldsTheKeyAndToNobodyElse() async throws {
        let asked = Locked<JSONValue?>(nil)
        let endpoint = try await ModelEndpoint.open { request, reply in
            asked.value = request
            reply.words("好的"); reply.words("。")
            reply.call(id: "call_1", name: "activate_app", arguments: "{\"app\":\"Notes\"}")
            reply.end(input: 1200, output: 30)
        }
        defer { endpoint.close() }
        var request = URLRequest(url: URL(string: endpoint.baseURL + "/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = Data(JSONValue.object(["model": "m", "stream": true, "messages": [["role": "user", "content": "打开备忘录"]]]).text.utf8)
        let (refused, status) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((status as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertNil(asked.value, String(decoding: refused, as: UTF8.self))

        request.setValue("Bearer \(endpoint.key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(asked.value?["messages"]?.array?.first?["content"], "打开备忘录")
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.last, "data: [DONE]")
        let chunks = lines.dropLast().compactMap { JSONValue(data: Data($0.dropFirst(6).utf8)) }
        XCTAssertEqual(chunks.compactMap { $0["choices"]?.array?.first?["delta"]?["content"]?.string }.joined(), "好的。")
        let call = chunks.compactMap { $0["choices"]?.array?.first?["delta"]?["tool_calls"]?.array?.first }.first
        XCTAssertEqual(call?["id"], "call_1"); XCTAssertEqual(call?["index"], 0)
        XCTAssertEqual(call?["function"], ["name": "activate_app", "arguments": "{\"app\":\"Notes\"}"])
        // A reply that called a tool ends for that reason, and says what it cost last.
        XCTAssertEqual(chunks.compactMap { $0["choices"]?.array?.first?["finish_reason"]?.string }, ["tool_calls"])
        XCTAssertEqual(chunks.last?["usage"], ["prompt_tokens": 1200, "completion_tokens": 30, "total_tokens": 1230])
    }

    /// What could not be served is said in the status and in words, as a model service says it.
    func testAFailureIsAnsweredAsOne() async throws {
        let endpoint = try await ModelEndpoint.open { _, reply in reply.fail(401, "The key was refused.") }
        defer { endpoint.close() }
        var request = URLRequest(url: URL(string: endpoint.baseURL + "/chat/completions")!)
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(endpoint.key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertEqual(JSONValue(data: data)?["error"]?["message"], "The key was refused.")
    }
}
