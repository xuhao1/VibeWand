import XCTest
import WandAgent
@testable import VibeWandBridge

final class ListeningModelTests: XCTestCase {
    private func request(_ messages: [JSONValue]) -> JSONValue {
        ["model": "m", "messages": .array(messages), "tools": [["type": "function", "function": [
            "name": "activate_app", "description": "Bring an app forward.", "parameters": ["type": "object", "properties": ["app": ["type": "string"]]]]]]]
    }
    private let earlier: [JSONValue] = [
        ["role": "system", "content": "rules"],
        ["role": "user", "content": "VibeWand · 打开备忘录\n23:10. The user was in Finder"],
        ["role": "assistant", "content": nil, "tool_calls": [["id": "call_a", "type": "function", "function": ["name": "activate_app", "arguments": "{\"app\":\"Notes\"}"]]]],
        ["role": "tool", "tool_call_id": "call_a", "content": "in front"],
        ["role": "assistant", "content": "备忘录已经打开了。"]
    ]

    /// A Realtime session keeps only the calls it made itself, so a conversation is told to a new one as lines:
    /// what was said, and each earlier tool call as a record of what it returned.
    func testARequestIsReadAsTheLinesOfTheConversationAndTheResultsItEndsWith() {
        let turn: JSONValue = ["role": "user", "content": [["type": "text", "text": "VibeWand · 不是这个\n23:12. The user was in Notes"]]]
        let opening = ModelExchange(request(earlier + [turn]))
        XCTAssertEqual(opening.instructions, "rules")
        XCTAssertEqual(opening.tools, [["name": "activate_app", "description": "Bring an app forward.",
                                        "parameters": ["type": "object", "properties": ["app": ["type": "string"]]]]])
        XCTAssertEqual(opening.lines, [.init(text: "VibeWand · 打开备忘录\n23:10. The user was in Finder"),
                                       .init(text: "(tool record) activate_app {\"app\":\"Notes\"} returned: in front"),
                                       .init(fromModel: true, text: "备忘录已经打开了。"),
                                       .init(text: "VibeWand · 不是这个\n23:12. The user was in Notes")])
        XCTAssertTrue(opening.results.isEmpty)

        // The next request of the same turn brings the results of the calls the model just made.
        let called: JSONValue = ["role": "assistant", "content": "", "tool_calls": [
            ["id": "call_b", "type": "function", "function": ["name": "activate_app", "arguments": "{\"app\":\"Reminders\"}"]],
            ["id": "call_c", "type": "function", "function": ["name": "finish", "arguments": "{}"]]]]
        let long = String(repeating: "长", count: ModelExchange.longest + 10)
        let next = ModelExchange(request(earlier + [turn, called, ["role": "tool", "tool_call_id": "call_b", "content": .string(long)],
                                                    ["role": "tool", "tool_call_id": "call_c", "content": "ok"]]))
        XCTAssertEqual(next.results.map(\.call), ["call_b", "call_c"])
        XCTAssertEqual(next.results[0].output.count, ModelExchange.longest, "one piece of a session is cut to what it takes")
        XCTAssertEqual(Array(next.lines.prefix(4)), opening.lines)
        XCTAssertEqual(next.lines.last, .init(text: "(tool record) finish {} returned: ok"))
        // Once the model has spoken again, nothing is waiting to be handed back.
        XCTAssertTrue(ModelExchange(request(earlier)).results.isEmpty)
    }
}
