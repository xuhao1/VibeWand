import XCTest
@testable import WandAgent

/// Plugin mode: VibeWand's coordinator on a DeepSeek Harness the user installed.
/// Nothing here starts a harness; the opt-in `KernelLiveTests` do.
final class HarnessPluginTests: XCTestCase {
    private let bundle = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("kernel/plugin")
    /// The shape the harness's own apps write: one row per list item, starting at the margin.
    private let profile = """
        # Your patch layer for this dsh profile, applied after every bundle layer:
        # a top-level YAML array of loader patch entries.
        - id: ui-settings-general
          name: "@deepseek-ai/dsh-client-ui-settings-general"
          config:
            welcomeNoticeVersion: 2026-08-13.1
        - id: agent-default-model
          name: "@deepseek-ai/dsh-agent-default-model"
          config:
            provider: deepseek-official
            model: deepseek-flash
        - id: llm-pi-ai
          name: "@deepseek-ai/dsh-llm-pi-ai"
          config:
            providers:
              local:
                api: openai-completions
                baseURL: http://127.0.0.1:8000/v1
                models:
                  - id: Qwen-Local
                    name: Qwen Local
                apiKeyEnv: LOCAL_API_KEY
        # a note the user left at the margin
        - insert:
            - id: tool-of-their-own
              name: some-tool-plugin
        - id: 'llm-deepseek'
          name: "@deepseek-ai/dsh-llm-deepseek-api-key"
          config:
            models:
              - id: deepseek-flash

        - id: agent-default-model
          name: "@deepseek-ai/dsh-agent-default-model"
          config:
            provider: "local"
            model: 'Qwen-Local'
            reasoningEffort: high
        - id: ui-chat
          name: "@deepseek-ai/dsh-client-ui-chat"
          config:
            transcriptView: standard
        """

    func testTheBundleDeclaresTheHarnessVersionsItWasVerifiedOnAndMountsNoToolsOfItsOwn() throws {
        let manifest = try XCTUnwrap(JSONValue(data: try Data(contentsOf: bundle.appendingPathComponent("package.json"))))
        // The harness enforces the peer range before it loads a bundle; `engines.dsh` states the same for a reader.
        let declared = HarnessPlugin.verified.joined(separator: " || ")
        XCTAssertEqual(manifest["peerDependencies"]?["@deepseek-ai/dsh"]?.string, declared)
        XCTAssertEqual(manifest["engines"]?["dsh"]?.string, declared)
        XCTAssertEqual(manifest["dsh"]?["manifestVersion"], 1)
        XCTAssertEqual(manifest["dsh"]?["bundle"]?["patch"], "./cordis.patch.yml")
        XCTAssertNil(manifest["dependencies"])

        let patch = try String(contentsOf: bundle.appendingPathComponent("cordis.patch.yml"), encoding: .utf8)
        let rows = patch.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let packages = rows.filter { $0.hasPrefix("name: '@deepseek-ai/") }.map { String($0.dropFirst("name: '@deepseek-ai/".count).dropLast()) }
        // An allowlist by construction: the harness's own model, credential and session rows, and the protocol bridge.
        XCTAssertEqual(Set(packages), [
            "dsh-acp-app", "dsh-acp", "cordis-plugin-timer", "dsh-credentials-local", "dsh-authorization", "dsh-llm", "dsh-llm-retry",
            "dsh-llm-pi-ai", "dsh-llm-deepseek-api-key", "dsh-deepseek-account-platform", "dsh-llm-deepseek-account", "dsh-session",
            "dsh-session-projection", "dsh-session-title", "dsh-session-persistence-jsonl", "dsh-storage", "dsh-storage-json",
            "dsh-storage-domain", "dsh-session-projection-cache", "dsh-system-prompt", "dsh-tools", "dsh-agent", "dsh-agent-loop",
            "dsh-jobs-local", "dsh-token-meter", "dsh-user-approval"
        ])
        XCTAssertEqual(packages.count, 26)
        XCTAssertFalse(rows.contains { $0.hasPrefix("- id: tool-") })
        XCTAssertTrue(patch.contains("policy: never"))
        // The rows the user's own model settings are copied onto exist under the ids the harness gives them.
        for id in HarnessPlugin.modelRows { XCTAssertTrue(rows.contains("- id: \(id)"), id) }
    }

    func testOnlyTheModelRowsOfTheUsersProfileAreTakenAndTheyAreCopiedAsTheyStand() {
        let rows = HarnessPlugin.rows(HarnessPlugin.modelRows, in: profile)
        XCTAssertEqual(rows, """
            - id: llm-pi-ai
              name: "@deepseek-ai/dsh-llm-pi-ai"
              config:
                providers:
                  local:
                    api: openai-completions
                    baseURL: http://127.0.0.1:8000/v1
                    models:
                      - id: Qwen-Local
                        name: Qwen Local
                    apiKeyEnv: LOCAL_API_KEY
            - id: 'llm-deepseek'
              name: "@deepseek-ai/dsh-llm-deepseek-api-key"
              config:
                models:
                  - id: deepseek-flash

            """)
        // A plugin the user inserted into their own profile, and their interface settings, stay where they are.
        XCTAssertFalse(rows.contains("insert") || rows.contains("tool-of-their-own") || rows.contains("ui-"))
        XCTAssertEqual(HarnessPlugin.rows(HarnessPlugin.modelRows, in: "[]\n"), "")
        XCTAssertEqual(HarnessPlugin.rows(HarnessPlugin.modelRows, in: "- {id: llm-pi-ai, config: {}}\n"), "", "a layout the harness does not write is left behind")

        // The later of two rows for the default model is the one in force.
        XCTAssertEqual(HarnessPlugin.defaultModel(in: profile), HarnessPlugin.Model(provider: "local", model: "Qwen-Local"))
        XCTAssertNil(HarnessPlugin.defaultModel(in: "- id: llm-pi-ai\n  config:\n    providers: {}\n"))
    }

    func testLaunchWritesVibeWandsOwnProfileIntoTheHarnessHomeAndNothingElse() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vw-harness-\(UUID().uuidString)")
        let home = root.appendingPathComponent("dsh"), support = root.appendingPathComponent("support")
        defer { try? files.removeItem(at: root) }
        for directory in ["profiles/desktop", "sessions/--Users-someone-project--"] {
            try files.createDirectory(at: home.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try profile.write(to: home.appendingPathComponent("profiles/desktop/cordis.patch.yml"), atomically: true, encoding: .utf8)
        try "theirs".write(to: home.appendingPathComponent("sessions/--Users-someone-project--/session.jsonl"), atomically: true, encoding: .utf8)
        try "SECRET: value".write(to: home.appendingPathComponent(".credentials.yaml"), atomically: true, encoding: .utf8)

        let plugin = HarnessPlugin(launcher: URL(fileURLWithPath: "/opt/harness/bin/dsh"), bundle: bundle, home: home)
        XCTAssertEqual(plugin.source, "desktop")
        XCTAssertEqual(plugin.defaultModel, HarnessPlugin.Model(provider: "local", model: "Qwen-Local"))
        let launch = try plugin.launch(version: HarnessPlugin.verified[0], allowUnverified: false, support: support, model: nil, instructions: "那个项目指 VibeWand")
        XCTAssertEqual(launch.executable.path, "/opt/harness/bin/dsh")
        XCTAssertEqual(launch.arguments, ["--profile", "vibewand"])
        // Conversations are filed in the harness's apps under this folder's name.
        XCTAssertEqual(launch.directory.path, support.appendingPathComponent("VibeWand").path)
        XCTAssertEqual(launch.log?.path, support.appendingPathComponent("logs/kernel.log").path)
        // The harness is given its own home and no key: it finds its keys and sign-ins there itself.
        XCTAssertEqual(Set(launch.environment.keys), ["PATH", "HOME", "TMPDIR", "LANG", "DSH_HOME", "VIBEWAND_SYSTEM_PROMPT", "VIBEWAND_MODEL"])
        XCTAssertEqual(launch.environment["DSH_HOME"], home.path)
        XCTAssertEqual(launch.environment["VIBEWAND_MODEL"], #"{"model":"Qwen-Local","provider":"local"}"#)
        XCTAssertTrue(launch.environment["VIBEWAND_SYSTEM_PROMPT"]!.hasSuffix("那个项目指 VibeWand"))

        let installed = home.appendingPathComponent("profiles/vibewand")
        let manifest = try XCTUnwrap(JSONValue(data: try Data(contentsOf: installed.appendingPathComponent("package.json"))))
        XCTAssertEqual(manifest["dsh"]?["profile"]?["bundles"], ["vibewand-coordinator"])
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: installed.appendingPathComponent("node_modules/vibewand-coordinator").path), bundle.path)
        let patch = try String(contentsOf: installed.appendingPathComponent("cordis.patch.yml"), encoding: .utf8)
        XCTAssertTrue(patch.hasPrefix("# Written by VibeWand at each start from the desktop profile's model rows."))
        XCTAssertTrue(patch.contains("- id: llm-pi-ai\n") && patch.contains("baseURL: http://127.0.0.1:8000/v1"))
        XCTAssertFalse(patch.contains("insert") || patch.contains("agent-default-model") || patch.contains("ui-"))
        XCTAssertFalse(files.fileExists(atPath: installed.appendingPathComponent("compatibility.json").path))
        // Everything that was in the home is as it was.
        XCTAssertEqual(try files.contentsOfDirectory(atPath: home.path).sorted(), [".credentials.yaml", "profiles", "sessions"])
        XCTAssertEqual(try files.contentsOfDirectory(atPath: home.appendingPathComponent("profiles").path).sorted(), ["desktop", "vibewand"])
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("profiles/desktop/cordis.patch.yml"), encoding: .utf8), profile)
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("sessions/--Users-someone-project--/session.jsonl"), encoding: .utf8), "theirs")
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".credentials.yaml"), encoding: .utf8), "SECRET: value")

        // A model picked in VibeWand is used instead of the harness's default.
        let picked = try plugin.launch(version: HarnessPlugin.verified[0], allowUnverified: false, support: support,
                                       model: HarnessPlugin.Model(provider: "deepseek-official", model: "deepseek-v4-pro"))
        XCTAssertEqual(picked.environment["VIBEWAND_MODEL"], #"{"model":"deepseek-v4-pro","provider":"deepseek-official"}"#)

        // A version the bundle does not declare is refused, unless the user chose to try it: then the exemption the
        // harness itself asks for is recorded, for exactly that pair, and taken away again on a verified version.
        XCTAssertThrowsError(try plugin.launch(version: "0.3.0", allowUnverified: false, support: support, model: nil)) {
            XCTAssertEqual($0 as? HarnessPlugin.Failure, .unverified("0.3.0"))
        }
        _ = try plugin.launch(version: "0.3.0", allowUnverified: true, support: support, model: nil)
        let release = try XCTUnwrap(JSONValue(data: try Data(contentsOf: bundle.appendingPathComponent("package.json")))?["version"]?.string)
        XCTAssertEqual(JSONValue(data: try Data(contentsOf: installed.appendingPathComponent("compatibility.json"))), ["vibewand-coordinator@\(release)": ["0.3.0"]])
        _ = try plugin.launch(version: HarnessPlugin.verified[0], allowUnverified: true, support: support, model: nil)
        XCTAssertFalse(files.fileExists(atPath: installed.appendingPathComponent("compatibility.json").path))

        // A harness with no interactive profile yet starts on what a fresh one starts on, with no rows to copy.
        let bare = HarnessPlugin(launcher: plugin.launcher, bundle: bundle, home: root.appendingPathComponent("bare"))
        XCTAssertNil(bare.source)
        let fresh = try bare.launch(version: HarnessPlugin.verified[0], allowUnverified: false, support: support, model: nil)
        XCTAssertEqual(fresh.environment["VIBEWAND_MODEL"], #"{"model":"deepseek-flash","provider":"deepseek-official"}"#)
        XCTAssertTrue(try String(contentsOf: bare.home.appendingPathComponent("profiles/vibewand/cordis.patch.yml"), encoding: .utf8).hasSuffix("\n[]\n"))
    }

    func testTheHarnessIsFoundInItsDesktopAppAndOnlyWhenThisBuildCarriesThePlugin() throws {
        let files = FileManager.default
        let app = files.temporaryDirectory.appendingPathComponent("vw-harness-app-\(UUID().uuidString)/DeepSeek Harness.app")
        defer { try? files.removeItem(at: app.deletingLastPathComponent()) }
        let command = app.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
        try files.createDirectory(at: command.deletingLastPathComponent(), withIntermediateDirectories: true)
        files.createFile(atPath: command.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(HarnessPlugin.locate(desktopApp: app, bundle: bundle)?.launcher.path, command.path)
        XCTAssertEqual(HarnessPlugin.locate(desktopApp: app, bundle: bundle)?.home.path, NSHomeDirectory() + "/.dsh")
        XCTAssertNil(HarnessPlugin.locate(desktopApp: app, bundle: app), "a build without the plugin has nothing to run there")
    }

    func testASessionSaysWhichModelsAndReasoningEffortsCanBeChosen() {
        let options = KernelOptions([
            ["id": "model", "category": "model", "type": "select", "currentValue": #"["local","Qwen-Local"]"#, "options": [
                ["group": "local", "name": "Local", "options": [["value": #"["local","Qwen-Local"]"#, "name": "Qwen Local"]]],
                ["group": "deepseek-official", "name": "DeepSeek", "options": [
                    ["value": #"["deepseek-official","deepseek-flash"]"#, "name": "DeepSeek-V4.1-Flash"], ["value": "not a pair", "name": "?"]]]]],
            ["id": "reasoning_effort", "category": "thought_level", "type": "select", "currentValue": "high",
             "options": [["value": "off", "name": "Off"], ["value": "low", "name": "Low"], ["value": "high", "name": "High"]]]
        ])
        XCTAssertEqual(options.models.map(\.id), ["local/Qwen-Local", "deepseek-official/deepseek-flash"])
        XCTAssertEqual(options.models[1].group, "DeepSeek")
        XCTAssertEqual(options.models[1].name, "DeepSeek-V4.1-Flash")
        XCTAssertEqual(options.efforts, ["off", "low", "high"])
        XCTAssertEqual(KernelOptions([]), KernelOptions())
    }
}
