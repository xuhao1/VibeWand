import XCTest
@testable import WandAgent

/// One coordinator on either harness: the one VibeWand ships and one the user installed.
/// Nothing here starts a harness; the opt-in `KernelLiveTests` do.
final class HarnessTests: XCTestCase {
    private let kernel = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("kernel")
    private var coordinator: URL { kernel.appendingPathComponent("coordinator") }
    private var overlay: URL { kernel.appendingPathComponent("overlay") }
    private func manifest(_ bundle: URL) throws -> JSONValue { try XCTUnwrap(JSONValue(data: try Data(contentsOf: bundle.appendingPathComponent("package.json")))) }
    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
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


    /// The coordinator's tree is an allowlist by construction. Nothing that runs commands, touches files,
    /// browses or spawns agents may appear in it, and a package it names is a deliberate decision.
    func testTheCoordinatorIsACompleteTreeWithNoToolsOfItsOwnAndDeclaresWhatItNeeds() throws {
        let manifest = try manifest(coordinator)
        // The harness enforces the peer range before it loads a bundle; `engines.dsh` states the same for a reader.
        let declared = Harness.verified.joined(separator: " || ")
        XCTAssertEqual(manifest["peerDependencies"]?["@deepseek-ai/dsh"]?.string, declared)
        XCTAssertEqual(manifest["engines"]?["dsh"]?.string, declared)
        XCTAssertEqual(manifest["dsh"]?["manifestVersion"], 1)
        XCTAssertEqual(manifest["dsh"]?["bundle"]?["patch"], "./cordis.patch.yml")

        let patch = try text(coordinator.appendingPathComponent("cordis.patch.yml"))
        let rows = patch.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let packages = rows.filter { $0.hasPrefix("name: '") }.map { String($0.dropFirst("name: '".count).dropLast()) }
        XCTAssertEqual(Set(packages.map { $0.replacingOccurrences(of: "@deepseek-ai/", with: "") }), [
            "dsh-acp-app", "dsh-acp", "cordis-plugin-timer", "dsh-credentials-local", "dsh-authorization", "dsh-llm", "dsh-llm-retry",
            "dsh-llm-pi-ai", "dsh-llm-deepseek-api-key", "dsh-deepseek-account-platform", "dsh-llm-deepseek-account", "dsh-session",
            "dsh-session-projection", "dsh-session-title", "dsh-session-persistence-jsonl", "dsh-attachment-local", "dsh-storage",
            "dsh-storage-json", "dsh-storage-domain", "dsh-session-projection-cache", "dsh-system-prompt", "dsh-tools", "dsh-agent",
            "dsh-agent-loop", "dsh-jobs-local", "dsh-token-meter", "dsh-user-approval"
        ])
        XCTAssertEqual(packages.count, 27)
        XCTAssertFalse(rows.contains { $0.hasPrefix("- id: tool-") })
        XCTAssertTrue(patch.contains("policy: never"))
        // The model rows of either harness land on the ids the harness's own base bundle gives them.
        for id in Harness.modelRows { XCTAssertTrue(rows.contains("- id: \(id)"), id) }
        // What the rows name is what the bundle says it needs: the shipped harness is assembled from this list,
        // and the harness resolves the rows through it.
        XCTAssertEqual(Set(manifest["dependencies"]?.object?.keys.map { $0 } ?? []), Set(packages))
    }

    /// The shipped harness is the coordinator, what its launcher imports, and one plug-in of the harness that VibeWand
    /// runs a part of by itself: SenseVoice, for dictation, with the service definition its recogniser imports.
    func testTheShippedHarnessIsAssembledFromTheCoordinatorsOwnList() throws {
        let manifest = try manifest(kernel)
        let named = Set(manifest["dependencies"]?.object?.keys.map { $0 } ?? [])
        let speech = ["@deepseek-ai/dsh-experimental-speech-to-text", "@deepseek-ai/dsh-experimental-speech-to-text-sensevoice"]
        XCTAssertEqual(named, Set(["vibewand-coordinator", "@deepseek-ai/dsh-app-boot", "@deepseek-ai/dsh-cmdline", "@deepseek-ai/dsh-home-paths",
                                   "@deepseek-ai/dsh-http-proxy", "@deepseek-ai/dsh-launch-environment", "commander"] + speech))
        XCTAssertEqual(manifest["dependencies"]?["vibewand-coordinator"], "file:coordinator")
        // The plug-in is the one of the harness version the coordinator runs on. No row names it: the harness does
        // not load it, and command mode never starts it.
        for package in speech { XCTAssertEqual(manifest["dependencies"]?[package], .string(Harness.verified[0])) }
        XCTAssertFalse(try text(coordinator.appendingPathComponent("cordis.patch.yml")).contains("speech"))
        // The launcher taken at assembly is of a version the coordinator declares.
        let script = try text(kernel.deletingLastPathComponent().appendingPathComponent("scripts/build-kernel.sh"))
        XCTAssertTrue(script.contains("task_launcher=@deepseek-ai/dsh@\(Harness.verified[0])"))
        // The lock was made from this list, with the coordinator as the files it is rather than a link.
        let lock = try XCTUnwrap(JSONValue(data: try Data(contentsOf: kernel.appendingPathComponent("package-lock.json"))))
        XCTAssertEqual(lock["packages"]?["node_modules/vibewand-coordinator"]?["resolved"], "file:coordinator")
        XCTAssertNil(lock["packages"]?["node_modules/vibewand-coordinator"]?["link"])
        XCTAssertNil(lock["packages"]?["node_modules/@deepseek-ai/dsh-base"], "the harness's whole product was pulled in")
        XCTAssertTrue(try text(kernel.appendingPathComponent(".npmrc")).contains("install-links=true"))
    }

    /// The overlay restates a few rows over the harness's own agent; it inserts nothing and names no package.
    func testTheOverlayOnlyRestatesRowsOfTheHarnessesOwnAgent() throws {
        let manifest = try manifest(overlay)
        XCTAssertEqual(manifest["peerDependencies"]?["@deepseek-ai/dsh"]?.string, Harness.verified.joined(separator: " || "))
        XCTAssertNil(manifest["dependencies"])
        XCTAssertEqual(manifest["version"], try self.manifest(coordinator)["version"])
        let patch = try text(overlay.appendingPathComponent("cordis.patch.yml"))
        let rows = patch.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init)
        XCTAssertEqual(rows.filter { $0.hasPrefix("- ") }, ["- id: acp", "- id: system-prompt", "- id: session-title"])
        XCTAssertFalse(patch.contains("insert") || rows.contains { $0.contains("name:") })
        // The harness's own sandbox and approval stay as it ships them: they follow the permission mode handed over.
        XCTAssertFalse(rows.contains { $0.contains("approval") || $0.contains("sandbox") })
    }

    func testOnlyTheModelRowsOfTheUsersProfileAreTakenAndTheyAreCopiedAsTheyStand() {
        let rows = Harness.rows(Harness.modelRows, in: profile)
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
        XCTAssertEqual(Harness.rows(Harness.modelRows, in: "[]\n"), "")
        XCTAssertEqual(Harness.rows(Harness.modelRows, in: "- {id: llm-pi-ai, config: {}}\n"), "", "a layout the harness does not write is left behind")

        // The later of two rows for the default model is the one in force.
        XCTAssertEqual(Harness.defaultModel(in: profile), Harness.Model(provider: "local", model: "Qwen-Local"))
        XCTAssertNil(Harness.defaultModel(in: "- id: llm-pi-ai\n  config:\n    providers: {}\n"))
    }

    func testAnInstalledHarnessGetsVibeWandsOwnProfileAndNothingElseInItsHome() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vw-harness-\(UUID().uuidString)")
        let home = root.appendingPathComponent("dsh"), support = root.appendingPathComponent("support")
        defer { try? files.removeItem(at: root) }
        for directory in ["profiles/desktop", "sessions/--Users-someone-project--/theirs"] {
            try files.createDirectory(at: home.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try profile.write(to: home.appendingPathComponent("profiles/desktop/cordis.patch.yml"), atomically: true, encoding: .utf8)
        try "theirs".write(to: home.appendingPathComponent("sessions/--Users-someone-project--/theirs/session.jsonl"), atomically: true, encoding: .utf8)
        try "SECRET: value".write(to: home.appendingPathComponent(".credentials.yaml"), atomically: true, encoding: .utf8)

        let harness = Harness(command: ["/opt/harness/bin/dsh"], home: home, coordinator: coordinator, overlay: overlay)
        XCTAssertEqual(harness.source, "desktop")
        XCTAssertEqual(harness.defaultModel, Harness.Model(provider: "local", model: "Qwen-Local"))
        let launch = try harness.launch(version: Harness.verified[0], support: support, models: .harness(nil, reasoning: .high),
                                        instructions: "那个项目指 VibeWand", keeping: "kept")
        XCTAssertEqual(launch.executable.path, "/opt/harness/bin/dsh")
        XCTAssertEqual(launch.arguments, ["--profile", "vibewand"])
        // The working directory is VibeWand's own folder, which is no project of the user's.
        XCTAssertEqual(launch.directory.path, support.appendingPathComponent("VibeWand").path)
        XCTAssertEqual(launch.log?.path, support.appendingPathComponent("logs/kernel.log").path)
        XCTAssertEqual(launch.effort, "high")
        // The harness is given its own home and no key: it finds its keys and sign-ins there itself.
        XCTAssertEqual(Set(launch.environment.keys), ["PATH", "HOME", "TMPDIR", "LANG", "DSH_HOME", "DSH_TELEMETRY_DISABLED", "VIBEWAND_SYSTEM_PROMPT", "VIBEWAND_MODEL"])
        XCTAssertEqual(launch.environment["DSH_HOME"], home.path)
        XCTAssertEqual(launch.environment["VIBEWAND_MODEL"], #"{"model":"Qwen-Local","provider":"local"}"#)
        XCTAssertTrue(launch.environment["VIBEWAND_SYSTEM_PROMPT"]!.hasSuffix("那个项目指 VibeWand"))

        let installed = home.appendingPathComponent("profiles/vibewand")
        XCTAssertEqual(try manifest(installed)["dsh"]?["profile"]?["bundles"], ["vibewand-coordinator"])
        XCTAssertEqual(try files.contentsOfDirectory(atPath: installed.appendingPathComponent("node_modules").path), ["vibewand-coordinator"])
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: installed.appendingPathComponent("node_modules/vibewand-coordinator").path), coordinator.path)
        let patch = try text(installed.appendingPathComponent("cordis.patch.yml"))
        XCTAssertTrue(patch.hasPrefix("# Written by VibeWand at each start from the desktop profile's model rows."))
        XCTAssertTrue(patch.contains("- id: llm-pi-ai\n") && patch.contains("baseURL: http://127.0.0.1:8000/v1"))
        XCTAssertFalse(patch.contains("insert") || patch.contains("agent-default-model") || patch.contains("ui-"))
        XCTAssertFalse(files.fileExists(atPath: installed.appendingPathComponent("compatibility.json").path))
        // Everything that was in the home is as it was: their conversations are theirs, whatever VibeWand keeps.
        XCTAssertEqual(try files.contentsOfDirectory(atPath: home.path).sorted(), [".credentials.yaml", "profiles", "sessions"])
        XCTAssertEqual(try files.contentsOfDirectory(atPath: home.appendingPathComponent("profiles").path).sorted(), ["desktop", "vibewand"])
        XCTAssertEqual(try text(home.appendingPathComponent("profiles/desktop/cordis.patch.yml")), profile)
        XCTAssertEqual(try text(home.appendingPathComponent("sessions/--Users-someone-project--/theirs/session.jsonl")), "theirs")
        XCTAssertEqual(try text(home.appendingPathComponent(".credentials.yaml")), "SECRET: value")

        // A model picked in VibeWand is used instead of the harness's default, and no effort is asked for unless one was chosen.
        let picked = try harness.launch(version: Harness.verified[0], support: support, models: .harness(Harness.Model(provider: "deepseek-official", model: "deepseek-v4-pro")))
        XCTAssertEqual(picked.environment["VIBEWAND_MODEL"], #"{"model":"deepseek-v4-pro","provider":"deepseek-official"}"#)
        XCTAssertNil(picked.effort)

        // A version the bundle does not declare is refused, unless the user chose to try it: then the exemption the
        // harness itself asks for is recorded, for exactly that pair, and taken away again on a verified version.
        XCTAssertThrowsError(try harness.launch(version: "0.3.0", support: support, models: .harness(nil))) {
            XCTAssertEqual($0 as? Harness.Failure, .unverified("0.3.0"))
        }
        _ = try harness.launch(version: "0.3.0", allowUnverified: true, support: support, models: .harness(nil))
        let release = try XCTUnwrap(try manifest(coordinator)["version"]?.string)
        XCTAssertEqual(JSONValue(data: try Data(contentsOf: installed.appendingPathComponent("compatibility.json"))), ["vibewand-coordinator@\(release)": ["0.3.0"]])
        _ = try harness.launch(version: Harness.verified[0], allowUnverified: true, support: support, models: .harness(nil))
        XCTAssertFalse(files.fileExists(atPath: installed.appendingPathComponent("compatibility.json").path))

        // A harness with no interactive profile yet starts on what a fresh one starts on, with no rows to copy.
        let bare = Harness(command: harness.command, home: root.appendingPathComponent("bare"), coordinator: coordinator)
        XCTAssertNil(bare.source)
        let fresh = try bare.launch(version: Harness.verified[0], support: support, models: .harness(nil))
        XCTAssertEqual(fresh.environment["VIBEWAND_MODEL"], #"{"model":"deepseek-flash","provider":"deepseek-official"}"#)
        XCTAssertTrue(try text(root.appendingPathComponent("bare/profiles/vibewand/cordis.patch.yml")).hasSuffix("\n[]\n"))
    }

    /// The shipped harness is started by the same call. What differs is all in what it is given: no home of
    /// its own, and a model that is described to it rather than found in its settings.
    func testTheShippedHarnessIsLaunchedTheSameWayOnTheModelSetUpInVibeWand() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vw-kernel-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("kernel")
        defer { try? files.removeItem(at: root) }
        // What earlier commands left in its store: one conversation that can still be carried on, and two that cannot.
        for id in ["kept", "spent", "older"] {
            try files.createDirectory(at: folder.appendingPathComponent("sessions/--work--/\(id)"), withIntermediateDirectories: true)
            try files.createDirectory(at: folder.appendingPathComponent("storages/session_projcache/sessions"), withIntermediateDirectories: true)
            try "{}".write(to: folder.appendingPathComponent("storages/session_projcache/sessions/\(id).json"), atomically: true, encoding: .utf8)
        }
        let harness = Harness(command: ["/opt/node", "/opt/dsh/bin.js"], home: nil, coordinator: coordinator)
        XCTAssertNil(harness.source)
        let route = ModelRoute(wire: .openAIChat, baseURL: "https://models.example/v1", model: "wand-large", key: "test-key", reasoning: .off)
        let launch = try harness.launch(version: Harness.verified[0], support: folder, models: .route(route), keeping: "kept")
        XCTAssertEqual(launch.executable.path, "/opt/node")
        XCTAssertEqual(launch.arguments, ["/opt/dsh/bin.js", "--profile", "vibewand"])
        XCTAssertEqual(launch.directory.path, folder.appendingPathComponent("VibeWand").path)
        XCTAssertEqual(launch.effort, "off")
        // Its home is the folder VibeWand keeps for it. The key travels in the environment only; the route names the variable, never the value.
        XCTAssertEqual(Set(launch.environment.keys), ["PATH", "HOME", "TMPDIR", "LANG", "DSH_HOME", "DSH_TELEMETRY_DISABLED", "VIBEWAND_SYSTEM_PROMPT",
                                                      "VIBEWAND_MODEL", "VIBEWAND_ROUTE", "VIBEWAND_MODEL_KEY"])
        XCTAssertEqual(launch.environment["DSH_HOME"], folder.path)
        XCTAssertEqual(launch.environment["VIBEWAND_SYSTEM_PROMPT"], CoordinatorPrompt.system)
        XCTAssertEqual(launch.environment["VIBEWAND_MODEL"], #"{"model":"wand-large","provider":"vibewand"}"#)
        XCTAssertEqual(launch.environment["VIBEWAND_MODEL_KEY"], "test-key")
        XCTAssertFalse(launch.environment["VIBEWAND_ROUTE"]!.contains("test-key"))
        // The same profile as on an installed harness, down to the one bundle beside it. Only the model row differs.
        let installed = folder.appendingPathComponent("profiles/vibewand")
        XCTAssertEqual(try manifest(installed)["dsh"]?["profile"]?["bundles"], ["vibewand-coordinator"])
        XCTAssertEqual(try files.destinationOfSymbolicLink(atPath: installed.appendingPathComponent("node_modules/vibewand-coordinator").path), coordinator.path)
        XCTAssertEqual(try text(installed.appendingPathComponent("cordis.patch.yml")),
                       "# Written by VibeWand at each start from the model set up in VibeWand. Edits here are lost.\n" + Harness.routeRows)
        XCTAssertTrue(Harness.routeRows.hasPrefix("- id: llm-pi-ai\n") && Harness.routeRows.contains("process.env.VIBEWAND_ROUTE"))
        // Nothing but the coordinator reads this store, so only the conversation that can be carried on is kept.
        XCTAssertEqual(try files.contentsOfDirectory(atPath: folder.appendingPathComponent("sessions/--work--").path), ["kept"])
        XCTAssertEqual(try files.contentsOfDirectory(atPath: folder.appendingPathComponent("storages/session_projcache/sessions").path), ["kept.json"])

        // A server without a key is still sent a placeholder, and the user's notes follow the rules.
        let keyless = try harness.launch(version: Harness.verified[0], support: folder,
                                         models: .route(ModelRoute(wire: .openAIChat, baseURL: "http://127.0.0.1:8000/v1", model: "qwen")), instructions: " 那个项目指 VibeWand \n")
        XCTAssertEqual(keyless.environment["VIBEWAND_MODEL_KEY"], "none")
        XCTAssertNil(keyless.effort)
        let prompt = try XCTUnwrap(keyless.environment["VIBEWAND_SYSTEM_PROMPT"])
        XCTAssertTrue(prompt.hasPrefix(CoordinatorPrompt.system) && prompt.hasSuffix("never override the rules above.\n那个项目指 VibeWand"))
        // With nothing to keep, the store is emptied.
        XCTAssertEqual(try files.contentsOfDirectory(atPath: folder.appendingPathComponent("sessions/--work--").path), [])
        // It ships no tools of its own to add.
        XCTAssertThrowsError(try harness.launch(version: Harness.verified[0], support: folder, models: .route(route), tools: .all)) {
            XCTAssertEqual($0 as? Harness.Failure, .noTools)
        }
    }

    /// The other tool scope: the harness's own agent with its tools, and VibeWand's rows over it.
    func testTheWholeHarnessIsItsOwnBaseAndAcpBundlesUnderTheOverlayWithItsSandboxSetFromThePermissionMode() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vw-harness-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let harness = Harness(command: ["/opt/harness/bin/dsh"], home: root.appendingPathComponent("dsh"), coordinator: coordinator, overlay: overlay)
        let installed = root.appendingPathComponent("dsh/profiles/vibewand")
        for (permission, sandbox) in [(PermissionMode.ask, "read-only"), (.risky, "workspace-write"), (.bypass, "danger-full-access")] {
            let launch = try harness.launch(version: Harness.verified[0], support: root.appendingPathComponent("support"), models: .harness(nil),
                                            tools: .all, permission: permission, sight: true)
            XCTAssertEqual(launch.environment["DSH_PERMISSION_MODE"], sandbox)
            let prompt = try XCTUnwrap(launch.environment["VIBEWAND_SYSTEM_PROMPT"])
            XCTAssertTrue(prompt.contains("this harness's own") && prompt.contains("ui_screenshot"))
        }
        XCTAssertEqual(try manifest(installed)["dsh"]?["profile"]?["bundles"], ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-acp-app", "vibewand-overlay"])
        // Only the bundle of the scope in force is beside the profile; the harness's own bundles come from its installation.
        XCTAssertEqual(try files.contentsOfDirectory(atPath: installed.appendingPathComponent("node_modules").path), ["vibewand-overlay"])
        // Back on VibeWand's own tools the harness's sandbox is not involved, and the model is told of neither.
        let own = try harness.launch(version: Harness.verified[0], support: root.appendingPathComponent("support"), models: .harness(nil))
        XCTAssertNil(own.environment["DSH_PERMISSION_MODE"])
        XCTAssertEqual(own.environment["VIBEWAND_SYSTEM_PROMPT"], CoordinatorPrompt.system)
        XCTAssertEqual(try files.contentsOfDirectory(atPath: installed.appendingPathComponent("node_modules").path), ["vibewand-coordinator"])
        // An exemption for an unverified harness names the bundle that is loaded.
        _ = try harness.launch(version: "0.3.0", allowUnverified: true, support: root.appendingPathComponent("support"), models: .harness(nil), tools: .all)
        let release = try XCTUnwrap(try manifest(overlay)["version"]?.string)
        XCTAssertEqual(JSONValue(data: try Data(contentsOf: installed.appendingPathComponent("compatibility.json"))), ["vibewand-overlay@\(release)": ["0.3.0"]])
    }

    /// VibeWand's view in a harness's own apps is a bundle of its own: one row, a host half that serves the
    /// recordings and a browser half that asks it for them, declared for the harness versions it was checked on.
    func testTheViewIsABundleOfItsOwnDeclaredForTheHarnessItWasCheckedOn() throws {
        let view = kernel.appendingPathComponent("view"), declared = try manifest(view)
        XCTAssertEqual(declared["name"]?.string, Harness.viewName)
        XCTAssertEqual(declared["version"], try manifest(coordinator)["version"])
        XCTAssertEqual(declared["peerDependencies"]?["@deepseek-ai/dsh"]?.string.map { [$0] }, Harness.verified)
        XCTAssertEqual(declared["dsh"]?["client"]?["platform"]?.string, "web")
        XCTAssertEqual(declared["exports"]?["./client"]?.string, "./lib/client.js")
        let rows = try text(view.appendingPathComponent("cordis.patch.yml"))
        XCTAssertTrue(rows.contains("id: vibewand-view") && rows.contains("name: 'vibewand-view'"))
        let host = try text(view.appendingPathComponent("lib/index.js")), browser = try text(view.appendingPathComponent("lib/client.js"))
        XCTAssertTrue(browser.contains(#"id: "vibewand-view""#))
        // The browser asks at the address the host answers at, and only for a record's own recording.
        XCTAssertTrue(host.contains("'/api/vibewand.recording'") && browser.contains("api/vibewand.recording?task="))
        XCTAssertTrue(host.contains(TaskJournal.recording))
        // The line a spoken command ends with is the one the browser reads.
        let spoken = CoordinatorPrompt.task("打开计算器", frontApp: "Finder", window: "", recording: ("20261007-040200-ab12cd", 7))
        XCTAssertTrue(browser.contains(#"/^Spoken, (\d+) s\. Recording (\d{8}-\d{6}-[0-9a-f]{6})$/"#))
        XCTAssertNotNil(spoken.split(separator: "\n").last?.range(of: #"^Spoken, (\d+) s\. Recording (\d{8}-\d{6}-[0-9a-f]{6})$"#, options: .regularExpression))
    }

    /// The view is in a harness's app once that app's profile lists it, which the harness's own plugin command
    /// sees to. The shipped harness has no apps and no view.
    func testAHarnesssAppShowsTheViewOnceItsProfileListsIt() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-view-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let launcher = home.appendingPathComponent("dsh")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("profiles/desktop"), withIntermediateDirectories: true)
        let harness = Harness(command: [launcher.path], home: home, coordinator: coordinator, overlay: overlay, view: kernel.appendingPathComponent("view"))
        XCTAssertFalse(harness.showsView(in: "desktop"))
        try Data(#"{"name":"dsh-profile-desktop","dsh":{"profile":{"bundles":["@deepseek-ai/dsh-base","vibewand-view"]}}}"#.utf8)
            .write(to: home.appendingPathComponent("profiles/desktop/package.json"))
        XCTAssertTrue(harness.showsView(in: "desktop"))
        XCTAssertFalse(harness.showsView(in: "web"))
        XCTAssertNil(Harness(command: [launcher.path], home: nil, coordinator: coordinator).view)
    }

    /// A job that is not a command runs on the same profile under rules of its own.
    func testAJobOfVibeWandsOwnIsLaunchedUnderItsOwnRules() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vw-errand-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let harness = Harness(command: ["/usr/bin/true"], home: home.appendingPathComponent("dsh"), coordinator: coordinator)
        let launch = try harness.launch(version: Harness.verified[0], support: home.appendingPathComponent("support"), models: .harness(nil),
                                        prompt: VocabularyPrompt.system)
        XCTAssertEqual(launch.environment["VIBEWAND_SYSTEM_PROMPT"], VocabularyPrompt.system)
        XCTAssertEqual(launch.arguments.suffix(2), ["--profile", "vibewand"])
    }

    func testEitherHarnessIsFoundWhereItLives() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vw-harness-app-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        func executable(_ url: URL) throws {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            files.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        }
        // An installed harness: the command its desktop app carries, with VibeWand's bundles for it.
        let app = root.appendingPathComponent("DeepSeek Harness.app"), command = app.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
        try executable(command)
        let installed = try XCTUnwrap(Harness.installed(desktopApp: app, bundles: kernel))
        XCTAssertEqual(installed.command, [command.path])
        XCTAssertEqual(installed.home?.path, NSHomeDirectory() + "/.dsh")
        XCTAssertEqual(installed.coordinator.path, coordinator.path)
        XCTAssertEqual(installed.overlay?.path, overlay.path)
        XCTAssertNil(Harness.installed(desktopApp: app, bundles: app), "a build without the bundles has nothing to run there")

        // The shipped harness: a runtime, the launcher, and the coordinator among its packages.
        XCTAssertNil(Harness.shipped(resources: root))
        let packages = root.appendingPathComponent("kernel/node_modules")
        try executable(root.appendingPathComponent("kernel/node/bin/node"))
        try executable(packages.appendingPathComponent("@deepseek-ai/dsh/lib/bin.js"))
        XCTAssertNil(Harness.shipped(resources: root), "a kernel without the coordinator cannot run it")
        try files.copyItem(at: coordinator, to: packages.appendingPathComponent("vibewand-coordinator"))
        let shipped = try XCTUnwrap(Harness.shipped(resources: root))
        XCTAssertEqual(shipped.command, [root.appendingPathComponent("kernel/node/bin/node").path, packages.appendingPathComponent("@deepseek-ai/dsh/lib/bin.js").path])
        XCTAssertNil(shipped.home)
        XCTAssertNil(shipped.overlay)
        XCTAssertEqual(shipped.coordinator.path, packages.appendingPathComponent("vibewand-coordinator").path)

        // Its SenseVoice plug-in is offered as the files a plain Node runs, once the kernel carries it. An installed
        // desktop app keeps its packages in an archive, so it offers none; the models are still shared through its home.
        XCTAssertNil(shipped.speech)
        XCTAssertNil(installed.speech)
        let plugin = packages.appendingPathComponent("@deepseek-ai/dsh-experimental-speech-to-text-sensevoice")
        try executable(plugin.appendingPathComponent("lib/worker.js")); try executable(plugin.appendingPathComponent("runtime/assets.json"))
        XCTAssertEqual(shipped.speech, Harness.Speech(node: root.appendingPathComponent("kernel/node/bin/node"), worker: plugin.appendingPathComponent("lib/worker.js"),
                                                      assets: plugin.appendingPathComponent("runtime/assets.json")))
        XCTAssertEqual(Harness.speechData(in: installed.home!).path, NSHomeDirectory() + "/.dsh/speech-to-text/sensevoice")
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
