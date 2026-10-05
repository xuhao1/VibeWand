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

    func testKernelLaunchUsesItsOwnHomeAndAMinimalEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vw-kernel-\(UUID().uuidString)")
        let profile = root.appendingPathComponent("profile"), home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("[]\n".utf8).write(to: profile.appendingPathComponent("cordis.yml"))
        defer { try? FileManager.default.removeItem(at: root) }
        let install = KernelInstall(command: ["/opt/node", "/opt/dsh/bin.js"], profile: profile)
        let launch = try install.launch(home: home, apiKey: "test-key", model: "deepseek-v4-pro")
        XCTAssertEqual(launch.executable.path, "/opt/node")
        XCTAssertEqual(launch.arguments, ["/opt/dsh/bin.js", "--profile", "vibewand"])
        XCTAssertEqual(launch.directory.path, home.appendingPathComponent("workspace").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("profiles/vibewand/cordis.yml").path))
        XCTAssertEqual(Set(launch.environment.keys), ["PATH", "HOME", "TMPDIR", "LANG", "DSH_HOME", "DEEPSEEK_API_KEY", "VIBEWAND_SYSTEM_PROMPT", "VIBEWAND_MODEL"])
        XCTAssertEqual(launch.environment["DSH_HOME"], home.path)
        XCTAssertEqual(launch.environment["VIBEWAND_SYSTEM_PROMPT"], CoordinatorPrompt.system)
        // A newer app replaces the installed profile rather than keeping a stale one.
        try Data("[1]\n".utf8).write(to: profile.appendingPathComponent("cordis.yml"))
        _ = try install.launch(home: home, apiKey: "test-key")
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("profiles/vibewand/cordis.yml"), encoding: .utf8), "[1]\n")
        XCTAssertNil(KernelInstall(resources: root))

        // A bundled kernel's packages are linked beside the installed profile, where the runtime looks for them.
        let modules = root.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        _ = try KernelInstall(command: ["/opt/node"], profile: profile, packages: modules).launch(home: home, apiKey: "test-key")
        let link = home.appendingPathComponent("profiles/vibewand/node_modules")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), modules.path)
    }

    /// The shipped profile is an allowlist by construction. Nothing that runs
    /// commands, touches files, browses or spawns agents may appear in it.
    func testShippedKernelProfileMountsNoToolsOfItsOwn() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let patch = try String(contentsOf: repository.appendingPathComponent("kernel/profile/cordis.patch.yml"), encoding: .utf8)
        let packages = patch.split(separator: "\n").compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("name: '@deepseek-ai/") else { return nil }
            return String(text.dropFirst("name: '@deepseek-ai/".count).dropLast())
        }
        XCTAssertEqual(Set(packages), [
            "dsh-acp-app", "dsh-acp", "dsh-llm-deepseek-api-key", "dsh-llm", "dsh-llm-retry", "cordis-plugin-timer", "dsh-session",
            "dsh-session-projection", "dsh-session-title", "dsh-session-persistence-jsonl", "dsh-system-prompt", "dsh-tools",
            "dsh-agent", "dsh-agent-loop", "dsh-jobs-local", "dsh-token-meter", "dsh-user-approval"
        ])
        XCTAssertEqual(packages.count, 17)
        XCTAssertTrue(patch.contains("policy: never"))
        let manifest = try String(contentsOf: repository.appendingPathComponent("kernel/profile/package.json"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("\"bundles\": []"))
    }
}
