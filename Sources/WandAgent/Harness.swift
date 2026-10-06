import Foundation

/// A DeepSeek Harness that runs VibeWand's coordinator: the one inside the app,
/// or one the user installed themselves. This is the only place that knows the
/// kernel is DeepSeek Harness; the rest of VibeWand speaks the Agent Client
/// Protocol to the process it describes.
///
/// Either harness is used the same way. VibeWand writes a profile named
/// `vibewand` into the harness's home that names VibeWand's bundle, says in the
/// profile's own patch where the models come from, and starts the harness on
/// it. The shipped harness is there so that nothing has to be installed first:
/// it has no home but the folder VibeWand keeps for it, and its model is the
/// one set up in VibeWand. An installed one brings its own home, with its
/// models, sign-ins and session store, which its desktop and web apps show.
public struct Harness: Sendable {
    /// A model as the harness names it: one of its provider routes and a model on it.
    public struct Model: Hashable, Codable, Sendable {
        public var provider: String
        public var model: String
        public init(provider: String, model: String) { self.provider = provider; self.model = model }
    }
    /// Where the model a conversation runs on is set up.
    public enum Models: Equatable, Sendable {
        /// In VibeWand: the route is handed over at launch with its key, and neither is written to disk.
        case route(ModelRoute)
        /// In the harness's own apps. A nil model follows the default the harness is set to; the reasoning effort
        /// is asked for by name and applies when that model offers it.
        case harness(Model?, reasoning: ModelRoute.Reasoning = .automatic)
    }
    /// How much the model may reach for.
    public enum Tools: String, CaseIterable, Sendable {
        /// VibeWand's catalog and nothing else.
        case own
        /// Every tool the harness ships as well: shell, files, web, skills, subagents.
        case all
    }
    public enum Failure: Error, Equatable {
        /// The harness reports a version the bundles do not declare, and the user has not chosen to try it.
        case unverified(String)
        /// This harness carries no tools of its own to add.
        case noTools
    }

    /// Harness versions the coordinator has been run on. The bundles' own manifests declare the same
    /// versions, and a harness refuses to load them on any other unless the user grants an exemption.
    public static let verified = ["0.2.0-rc.2"]
    static let profile = "vibewand"
    /// What a fresh harness starts new sessions on.
    static let stock = Model(provider: "deepseek-official", model: "deepseek-flash")
    /// The rows that say which models a harness serves. Only these are taken from the user's own profile.
    static let modelRows = ["llm-pi-ai", "llm-deepseek", "llm-deepseek-account"]
    /// The provider a route set up in VibeWand is served under, and the one row that reads it from the environment.
    static let routeProvider = "vibewand"
    static let routeRows = "- id: llm-pi-ai\n  config:\n    providers: !!js JSON.parse(process.env.VIBEWAND_ROUTE ?? \"{}\")\n"

    /// The harness's launcher followed by its leading arguments.
    public var command: [String]
    /// The harness's home, where its profiles, credentials and sessions live. nil for the shipped harness,
    /// whose home is the folder VibeWand keeps for it.
    public var home: URL?
    /// VibeWand's coordinator as a harness bundle: a manifest and one patch file that is the complete tree.
    public var coordinator: URL
    /// The bundle that sets VibeWand on top of the harness's own agent and tools. nil for a harness that ships none.
    public var overlay: URL?

    public init(command: [String], home: URL?, coordinator: URL, overlay: URL? = nil) {
        self.command = command; self.home = home; self.coordinator = coordinator; self.overlay = overlay
    }
    public static let defaultHome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")

    /// The harness VibeWand ships: `kernel` in the app's resources, as scripts/build-kernel.sh assembles it.
    /// The coordinator is one of its packages, which is where the harness finds the packages the coordinator names.
    public static func shipped(resources: URL) -> Harness? {
        let files = FileManager.default
        let root = resources.appendingPathComponent("kernel"), packages = root.appendingPathComponent("node_modules")
        let node = root.appendingPathComponent("node/bin/node"), entry = packages.appendingPathComponent("@deepseek-ai/dsh/lib/bin.js")
        let coordinator = packages.appendingPathComponent("vibewand-coordinator")
        guard files.isExecutableFile(atPath: node.path), files.fileExists(atPath: entry.path),
              files.fileExists(atPath: coordinator.appendingPathComponent("package.json").path) else { return nil }
        return Harness(command: [node.path, entry.path], home: nil, coordinator: coordinator)
    }

    /// A harness the user installed: the command its desktop app carries, or one installed for the terminal.
    /// `bundles` holds VibeWand's `coordinator` and `overlay` apart from any package folder, so that the
    /// harness resolves what they name from its own installation.
    public static func installed(desktopApp: URL?, bundles: URL, home: URL = Harness.defaultHome) -> Harness? {
        let files = FileManager.default
        let coordinator = bundles.appendingPathComponent("coordinator"), overlay = bundles.appendingPathComponent("overlay")
        guard files.fileExists(atPath: coordinator.appendingPathComponent("package.json").path) else { return nil }
        let carried = desktopApp?.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
        let terminal = ["/opt/homebrew/bin/dsh", "/usr/local/bin/dsh", NSHomeDirectory() + "/.local/bin/dsh"].map(URL.init(fileURLWithPath:))
        guard let launcher = ([carried].compactMap { $0 } + terminal).first(where: { files.isExecutableFile(atPath: $0.path) }) else { return nil }
        return Harness(command: [launcher.path], home: home, coordinator: coordinator,
                       overlay: files.fileExists(atPath: overlay.appendingPathComponent("package.json").path) ? overlay : nil)
    }

    public var launcher: URL { URL(fileURLWithPath: command[0]) }

    /// The harness's SenseVoice plug-in as files a plain Node runs: that Node, the worker the plug-in's own
    /// speech provider starts, and the plug-in's list of the model files that worker loads. The shipped harness
    /// has its packages as files. An installed desktop app keeps them in an archive only its own runtime
    /// reads, so it offers none; its home is still where the models are looked for first.
    public struct Speech: Equatable, Sendable {
        public var node: URL, worker: URL, assets: URL
    }
    public var speech: Speech? {
        guard home == nil else { return nil }
        let plugin = coordinator.deletingLastPathComponent().appendingPathComponent("@deepseek-ai/dsh-experimental-speech-to-text-sensevoice")
        let speech = Speech(node: launcher, worker: plugin.appendingPathComponent("lib/worker.js"), assets: plugin.appendingPathComponent("runtime/assets.json"))
        return [speech.worker, speech.assets].allSatisfy { FileManager.default.fileExists(atPath: $0.path) } ? speech : nil
    }
    /// Where a harness keeps that plug-in's models, inside its home: the folder its own bundle names.
    public static func speechData(in home: URL) -> URL { home.appendingPathComponent("speech-to-text/sensevoice") }

    /// The version the harness reports, or nil when it does not start.
    public func version() async -> String? { await run(["--version"]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }

    private func run(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(), output = Pipe()
                process.executableURL = launcher; process.arguments = Array(command.dropFirst()) + arguments
                process.environment = environment(home: home)
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }

    /// The interactive profile whose model settings are followed: the desktop app's, else the web app's.
    public var source: String? {
        ["desktop", "web"].first { patch(of: $0).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    }
    private func patch(of profile: String) -> URL? { home?.appendingPathComponent("profiles/\(profile)/cordis.patch.yml") }
    private var settings: String { source.flatMap { patch(of: $0) }.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" }
    /// The model an installed harness starts new sessions on.
    public var defaultModel: Model { Self.defaultModel(in: settings) ?? Self.stock }

    /// What the harness needs to run, and nothing of VibeWand's own environment. An installed harness finds its
    /// keys and sign-ins in its home. Its telemetry exporters are told to stay off for what VibeWand starts.
    private func environment(home: URL?) -> [String: String] {
        var environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8",
                           "DSH_TELEMETRY_DISABLED": "1"]
        environment["DSH_HOME"] = home?.path
        return environment
    }

    /// Writes VibeWand's profile into the harness's home and describes the process to start. Nothing else in an
    /// installed harness's home is written by VibeWand. `support` is VibeWand's own folder for this harness: its
    /// `VibeWand` subfolder is the working directory, which is no project of the user's, so an installed
    /// harness's apps file the conversations under no project. `keeping` names the conversation that may be
    /// taken up again; in the shipped harness's store, which nothing else reads, the others are spent and removed.
    /// `hearing` says the model is one that hears the user's recording and speaks its answers.
    public func launch(version: String, allowUnverified: Bool = false, support: URL, models: Models, tools: Tools = .own,
                       permission: PermissionMode = .risky, instructions: String = "", sight: Bool = false, hearing: Bool = false,
                       keeping: String? = nil) throws -> KernelLaunch {
        guard Self.verified.contains(version) || allowUnverified else { throw Failure.unverified(version) }
        guard let bundle = tools == .all ? overlay : coordinator else { throw Failure.noTools }
        let files = FileManager.default
        let home = self.home ?? support
        if self.home == nil { Self.discardSessions(in: home, except: keeping) }
        let profile = home.appendingPathComponent("profiles/\(Self.profile)"), modules = profile.appendingPathComponent("node_modules")
        let logs = support.appendingPathComponent("logs"), workspace = support.appendingPathComponent("VibeWand")
        // Only the bundle of the scope in force is beside the profile.
        try? files.removeItem(at: modules)
        for directory in [modules, logs, workspace] { try files.createDirectory(at: directory, withIntermediateDirectories: true) }
        let manifest = JSONValue(data: try Data(contentsOf: bundle.appendingPathComponent("package.json")))
        guard let package = manifest?["name"]?.string, let release = manifest?["version"]?.string else { throw CocoaError(.fileReadCorruptFile) }
        // The whole harness is its own base bundle and its ACP app, with VibeWand's rows over them.
        let stack = tools == .all ? ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-acp-app", package] : [package]
        try Data(JSONValue.object([
            "name": "dsh-profile-vibewand", "private": true, "dependencies": [:],
            "dsh": ["profile": ["bundles": .array(stack.map(JSONValue.string)), "patchReload": "startup"]]
        ]).text.utf8).write(to: profile.appendingPathComponent("package.json"))
        try Data("# VibeWand's profile. The tree comes from its bundles; this root stays empty.\n[]\n".utf8).write(to: profile.appendingPathComponent("cordis.yml"))
        // The harness finds a profile's bundles beside the profile, and a bundle's packages from where the bundle really lives.
        try files.createSymbolicLink(at: modules.appendingPathComponent(package), withDestinationURL: bundle)

        var environment = environment(home: home)
        let rows: String, origin: String, chosen: Model, effort: ModelRoute.Reasoning
        switch models {
        case .route(let route):
            rows = Self.routeRows; origin = "the model set up in VibeWand"
            chosen = Model(provider: Self.routeProvider, model: route.model); effort = route.reasoning
            environment["VIBEWAND_ROUTE"] = Self.provider(route).text
            // A local server asks for no key, but the harness's client will not start a request without one.
            environment["VIBEWAND_MODEL_KEY"] = route.key ?? "none"
        case .harness(let picked, let reasoning):
            // Models are set up in the harness's own apps, which write them to the profile they run on. Copied at
            // every start, so a change made there is in force for the next conversation.
            rows = Self.rows(Self.modelRows, in: settings); origin = "the \(source ?? "(no)") profile's model rows"
            chosen = picked ?? defaultModel; effort = reasoning
        }
        let header = "# Written by VibeWand at each start from \(origin). Edits here are lost.\n"
        try Data((header + (rows.isEmpty ? "[]\n" : rows)).utf8).write(to: profile.appendingPathComponent("cordis.patch.yml"))
        // The harness loads a bundle only on the versions its manifest declares. Trying another is the user's
        // decision, recorded the way the harness itself records it: for this exact pair and no other.
        let exemption = profile.appendingPathComponent("compatibility.json")
        if Self.verified.contains(version) { try? files.removeItem(at: exemption) }
        else { try Data(JSONValue.object(["\(package)@\(release)": [.string(version)]]).text.utf8).write(to: exemption) }

        environment["VIBEWAND_SYSTEM_PROMPT"] = CoordinatorPrompt.system(instructions: instructions, tools: tools, sight: sight, hearing: hearing)
        environment["VIBEWAND_MODEL"] = JSONValue.object(["provider": .string(chosen.provider), "model": .string(chosen.model)]).text
        // The harness's own tools run inside its sandbox, and it asks before a step leaves it.
        if tools == .all { environment["DSH_PERMISSION_MODE"] = permission.sandbox }
        return KernelLaunch(executable: launcher, arguments: Array(command.dropFirst()) + ["--profile", Self.profile],
                            environment: environment, directory: workspace, log: logs.appendingPathComponent("kernel.log"),
                            effort: effort == .automatic ? nil : effort.rawValue)
    }

    /// Removes every conversation in a home's store but `session`. The store keeps one folder per working
    /// directory with a folder per conversation inside, and beside it one summary file per conversation.
    static func discardSessions(in home: URL, except session: String?) {
        let files = FileManager.default
        func contents(_ folder: URL) -> [URL] { (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] }
        let conversations = contents(home.appendingPathComponent("sessions")).flatMap(contents)
        let summaries = contents(home.appendingPathComponent("storages/session_projcache/sessions"))
        for item in conversations + summaries where item.deletingPathExtension().lastPathComponent != session { try? files.removeItem(at: item) }
    }

    // MARK: A route in the harness's vocabulary

    /// The route as the harness's multi-provider adapter takes it: one provider, serving the one chosen model.
    static func provider(_ route: ModelRoute) -> JSONValue {
        let api: String
        switch route.wire {
        case .openAIChat: api = "openai-completions"
        case .openAIResponses: api = "openai-responses"
        case .anthropic: api = "anthropic-messages"
        }
        var model: [String: JSONValue] = ["id": .string(route.model)]
        var provider: [String: JSONValue] = ["api": .string(api), "baseURL": .string(route.baseURL)]
        if let window = route.contextWindow {
            model["contextWindow"] = .number(Double(window))
            // A reply shares the window with everything already in it.
            provider["defaultMaxTokens"] = .number(Double(min(32_768, max(1_024, window / 4))))
        }
        if route.reasoning != .automatic {
            // Only a model that declares its levels is sent one. `off` has no spelling: it is the others' absence.
            model["reasoningEfforts"] = ["off": .null, "low": "low", "medium": "medium", "high": "high"]
            provider["reasoning"] = .string(route.reasoning.rawValue)
        }
        // A model is sent pictures only when it is declared to take them; the service is not asked.
        if route.images { model["input"] = ["text", "image"] }
        provider["models"] = [.object(model)]
        provider.merge(route.extra) { _, theirs in theirs }
        provider["apiKeyEnv"] = "VIBEWAND_MODEL_KEY"
        return [routeProvider: .object(provider)]
    }

    // MARK: Reading an installed harness's profile

    /// The top-level rows with these ids, copied as they stand. The harness writes one row per list item,
    /// starting at the margin; anything laid out otherwise is left behind rather than guessed at.
    static func rows(_ ids: [String], in patch: String) -> String {
        var kept: [String] = [], current: [String]?
        func close() { if let current { kept.append(current.joined(separator: "\n")) } }
        for line in patch.components(separatedBy: "\n") {
            if line.hasPrefix("- ") {
                close()
                let head = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                current = ids.contains { head == "id: \($0)" || head == "id: '\($0)'" || head == "id: \"\($0)\"" } ? [line] : nil
            } else if line.hasPrefix(" ") || line.isEmpty { current?.append(line) }
            else if !line.hasPrefix("#") { close(); current = nil }
        }
        close()
        return kept.map { $0.trimmingCharacters(in: .newlines) + "\n" }.joined()
    }

    /// The provider and model of the `agent-default-model` row, when the user has set one.
    static func defaultModel(in patch: String) -> Model? {
        func value(_ key: String, in row: String) -> String? {
            row.components(separatedBy: "\n").lazy.compactMap { line -> String? in
                let text = line.trimmingCharacters(in: .whitespaces)
                guard text.hasPrefix(key + ":") else { return nil }
                let value = text.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }.first { !$0.isEmpty }
        }
        // A later row for the same id replaces an earlier one, as it does when the harness composes them.
        let row = rows(["agent-default-model"], in: patch).components(separatedBy: "\n- ").last ?? ""
        guard let provider = value("provider", in: row), let model = value("model", in: row) else { return nil }
        return Model(provider: provider, model: model)
    }
}

extension PermissionMode {
    /// The harness's own permission preset that asks as much: its sandbox, with its approval beyond it.
    var sandbox: String {
        switch self {
        case .ask: return "read-only"
        case .risky: return "workspace-write"
        case .bypass: return "danger-full-access"
        }
    }
}
