import XCTest
@testable import WandAgent

final class DownstreamTests: XCTestCase {
    private let sessions = [
        ChatSession(id: "a", title: "VibeWand 麦克风延迟排查", folder: "VibekeyPluginCodex", updated: Date(timeIntervalSince1970: 300)),
        ChatSession(id: "b", title: "修复登录问题", folder: "webapp", updated: Date(timeIntervalSince1970: 400)),
        ChatSession(id: "c", title: "DualSense 麦克风蓝牙桥接", folder: "VibekeyPluginCodex", updated: Date(timeIntervalSince1970: 100))
    ]

    func testCodexThreadListIsReducedToWhatTheCoordinatorNeeds() {
        let parsed = CodexAppServer.parse(["data": [
            ["id": "019f-1", "name": "VibeWand 麦克风延迟排查", "preview": "第一条消息\n第二行", "cwd": "/Users/me/develop/VibekeyPluginCodex",
             "updatedAt": 1_791_186_069, "status": ["type": "notLoaded"], "path": "/Users/me/.codex/sessions/x.jsonl"],
            ["id": "019f-2", "name": nil, "preview": "帮我看看这个报错\n堆栈……", "cwd": "/tmp/demo", "updatedAt": 1_791_100_000],
            ["name": "no id"]
        ], "nextCursor": nil])
        XCTAssertEqual(parsed, [
            ChatSession(id: "019f-1", title: "VibeWand 麦克风延迟排查", folder: "VibekeyPluginCodex", updated: Date(timeIntervalSince1970: 1_791_186_069)),
            ChatSession(id: "019f-2", title: "帮我看看这个报错", folder: "demo", updated: Date(timeIntervalSince1970: 1_791_100_000))
        ])
    }

    func testRankingPrefersMatchesAndFallsBackToRecent() {
        XCTAssertEqual(ChatSession.rank(sessions, query: "麦克风", limit: 5).sessions.map(\.id), ["a", "c"])
        XCTAssertEqual(ChatSession.rank(sessions, query: "webapp 登录", limit: 5).sessions.map(\.id), ["b"])
        XCTAssertEqual(ChatSession.rank(sessions, query: "VIBEKEYPLUGINCODEX", limit: 1).sessions.map(\.id), ["a"])
        XCTAssertTrue(ChatSession.rank(sessions, query: "麦克风", limit: 5).matched)
        // Nothing matches a misheard name: the recent chats go back, marked, for the model to judge.
        let misheard = ChatSession.rank(sessions, query: "卖克风", limit: 2)
        XCTAssertEqual(misheard.sessions.map(\.id), ["b", "a"])
        XCTAssertFalse(misheard.matched)
        let recent = ChatSession.rank(sessions, query: nil, limit: 5)
        XCTAssertEqual(recent.sessions.map(\.id), ["b", "a", "c"])
        XCTAssertTrue(recent.matched)
    }

    func testCodexIsFoundInsideItsDesktopAppFirst() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("vw-codex-\(UUID().uuidString).app")
        let binary = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: app) }
        XCTAssertEqual(CodexAppServer.locate(desktopApp: app)?.path, binary.path)
    }

    func testAModelRouteBecomesOneProviderInTheKernelsVocabulary() throws {
        func provider(_ route: ModelRoute) -> JSONValue { Harness.provider(route)["vibewand"]! }
        // The least a route says: where, how, and which model.
        let plain = provider(ModelRoute(wire: .openAIChat, baseURL: "http://127.0.0.1:8000/v1", model: "qwen"))
        XCTAssertEqual(plain, ["api": "openai-completions", "baseURL": "http://127.0.0.1:8000/v1", "apiKeyEnv": "VIBEWAND_MODEL_KEY", "models": [["id": "qwen"]]])

        // A context length sizes the model and leaves room for the reply; a reasoning level is declared so that it is sent.
        let tuned = provider(ModelRoute(wire: .anthropic, baseURL: "https://api.anthropic.com", model: "claude", key: "k",
                                        contextWindow: 32_000, reasoning: .off))
        XCTAssertEqual(tuned["api"], "anthropic-messages")
        XCTAssertEqual(tuned["defaultMaxTokens"], 8_000)
        XCTAssertEqual(tuned["reasoning"], "off")
        XCTAssertEqual(tuned["models"], [["id": "claude", "contextWindow": 32_000,
                                          "reasoningEfforts": ["off": nil, "low": "low", "medium": "medium", "high": "high"]]])
        XCTAssertEqual(provider(ModelRoute(wire: .openAIResponses, baseURL: "https://api.openai.com/v1", model: "gpt", contextWindow: 2_000_000))["defaultMaxTokens"], 32_768)
        XCTAssertEqual(provider(ModelRoute(wire: .openAIResponses, baseURL: "https://api.openai.com/v1", model: "gpt"))["api"], "openai-responses")

        // The user's own settings win over the derived ones, except where the key comes from.
        let extra = provider(ModelRoute(wire: .openAIChat, baseURL: "http://127.0.0.1:8000/v1", model: "qwen", reasoning: .low,
                                        extra: ["compat": ["thinkingFormat": "qwen-chat-template"], "reasoning": "high", "apiKeyEnv": "HOME"]))
        XCTAssertEqual(extra["compat"], ["thinkingFormat": "qwen-chat-template"])
        XCTAssertEqual(extra["reasoning"], "high")
        XCTAssertEqual(extra["apiKeyEnv"], "VIBEWAND_MODEL_KEY")

        // A model is sent pictures only when the user says it takes them.
        XCTAssertNil(plain["models"]?.array?.first?["input"])
        XCTAssertEqual(provider(ModelRoute(wire: .openAIChat, baseURL: "http://127.0.0.1:8000/v1", model: "qwen", images: true))["models"], [["id": "qwen", "input": ["text", "image"]]])
    }

    func testModelListingAsksEachProtocolItsOwnWayAndReadsWhatServersAnswer() throws {
        let chat = try XCTUnwrap(ModelListing.request(wire: .openAIChat, baseURL: " https://api.deepseek.com/ ", key: " sk-test "))
        XCTAssertEqual(chat.url?.absoluteString, "https://api.deepseek.com/models")
        XCTAssertEqual(chat.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        // A gateway's path is kept; a server that needs no key is asked without one.
        let local = try XCTUnwrap(ModelListing.request(wire: .openAIResponses, baseURL: "http://127.0.0.1:8000/v1", key: nil))
        XCTAssertEqual(local.url?.absoluteString, "http://127.0.0.1:8000/v1/models")
        XCTAssertNil(local.value(forHTTPHeaderField: "Authorization"))
        for base in ["https://api.anthropic.com", "https://api.anthropic.com/v1/"] {
            let anthropic = try XCTUnwrap(ModelListing.request(wire: .anthropic, baseURL: base, key: "sk-ant"))
            XCTAssertEqual(anthropic.url?.absoluteString, "https://api.anthropic.com/v1/models?limit=1000")
            XCTAssertEqual(anthropic.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            XCTAssertEqual(anthropic.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertNil(anthropic.value(forHTTPHeaderField: "Authorization"))
        }
        XCTAssertNil(ModelListing.request(wire: .openAIChat, baseURL: "api.deepseek.com", key: nil))
        XCTAssertNil(ModelListing.request(wire: .openAIChat, baseURL: "file:///etc", key: nil))

        let deepseek = #"{"object":"list","data":[{"id":"deepseek-flash","name":"DeepSeek-V4.1-Flash","context_window":1048576},{"id":"deepseek-v4-pro","name":"deepseek-v4-pro"},{"object":"model"}]}"#
        XCTAssertEqual(ModelListing.parse(Data(deepseek.utf8)), [
            ListedModel(id: "deepseek-flash", name: "DeepSeek-V4.1-Flash", contextWindow: 1_048_576), ListedModel(id: "deepseek-v4-pro")])
        let anthropic = #"{"data":[{"type":"model","id":"claude-x","display_name":"Claude X"}],"has_more":false}"#
        XCTAssertEqual(ModelListing.parse(Data(anthropic.utf8)), [ListedModel(id: "claude-x", name: "Claude X")])
        let router = #"{"data":[{"id":"vendor/model","name":"Vendor: Model","context_length":200000}]}"#
        XCTAssertEqual(ModelListing.parse(Data(router.utf8))?.first?.contextWindow, 200_000)
        XCTAssertEqual(ModelListing.parse(Data(#"{"models":["a","b"]}"#.utf8))?.map(\.id), ["a", "b"])
        XCTAssertNil(ModelListing.parse(Data(#"{"error":"unauthorized"}"#.utf8)))
        XCTAssertNil(ModelListing.parse(Data("<html>".utf8)))
    }

    func testKernelEventsCarryContextUse() {
        XCTAssertEqual(KernelEvent.parse(["sessionUpdate": "usage_update", "used": 128, "size": 262_144]), .usage(used: 128, size: 262_144))
        XCTAssertNil(KernelEvent.parse(["sessionUpdate": "usage_update", "used": 128, "size": 0]))
        XCTAssertNil(KernelEvent.parse(["sessionUpdate": "config_option_update"]))
    }
}
