import Foundation

/// A DeepSeek Harness the user installed themselves, running VibeWand's
/// coordinator as one of its plugins instead of the kernel VibeWand ships.
/// The model providers, sign-ins and session store are then that harness's
/// own: its desktop and web apps show each conversation, and are where models
/// are set up. What the model can do is unchanged: VibeWand's bundle is the
/// complete tree, with no tools but the ones mounted per session.
public struct HarnessPlugin: Sendable {
    /// A model as the harness names it: one of its provider routes and a model on it.
    public struct Model: Hashable, Codable, Sendable {
        public var provider: String
        public var model: String
        public init(provider: String, model: String) { self.provider = provider; self.model = model }
    }
    public enum Failure: Error, Equatable {
        /// The harness reports a version the bundle does not declare, and the user has not chosen to try it.
        case unverified(String)
    }

    /// Harness versions the coordinator has been run on. The bundle's own manifest declares the same
    /// versions, and the harness refuses to load it on any other unless the user grants an exemption.
    public static let verified = ["0.2.0-rc.2"]
    static let profile = "vibewand"
    /// What a fresh harness starts new sessions on.
    static let stock = Model(provider: "deepseek-official", model: "deepseek-flash")
    /// The rows that say which models a harness serves. Only these are taken from the user's own profile.
    static let modelRows = ["llm-pi-ai", "llm-deepseek", "llm-deepseek-account"]

    /// The harness's own `dsh` command.
    public var launcher: URL
    /// VibeWand's coordinator as a harness bundle: a manifest and one patch file.
    public var bundle: URL
    /// The harness's home, where its profiles, credentials and sessions live.
    public var home: URL

    public init(launcher: URL, bundle: URL, home: URL = HarnessPlugin.defaultHome) {
        self.launcher = launcher; self.bundle = bundle; self.home = home
    }
    public static let defaultHome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")

    /// The command the harness's desktop app carries, or one installed for the terminal.
    public static func locate(desktopApp: URL?, bundle: URL, home: URL = HarnessPlugin.defaultHome) -> HarnessPlugin? {
        let files = FileManager.default
        guard files.fileExists(atPath: bundle.appendingPathComponent("package.json").path) else { return nil }
        let carried = desktopApp?.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
        let installed = ["/opt/homebrew/bin/dsh", "/usr/local/bin/dsh", NSHomeDirectory() + "/.local/bin/dsh"].map(URL.init(fileURLWithPath:))
        guard let launcher = ([carried].compactMap { $0 } + installed).first(where: { files.isExecutableFile(atPath: $0.path) }) else { return nil }
        return HarnessPlugin(launcher: launcher, bundle: bundle, home: home)
    }

    /// The version the harness reports, or nil when it does not start.
    public func version() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(), output = Pipe()
                process.executableURL = launcher; process.arguments = ["--version"]
                process.environment = environment
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 && !text.isEmpty ? text : nil)
            }
        }
    }

    /// The interactive profile whose model settings are followed: the desktop app's, else the web app's.
    public var source: String? {
        ["desktop", "web"].first { FileManager.default.fileExists(atPath: patch(of: $0).path) }
    }
    private func patch(of profile: String) -> URL { home.appendingPathComponent("profiles/\(profile)/cordis.patch.yml") }
    private var settings: String { source.flatMap { try? String(contentsOf: patch(of: $0), encoding: .utf8) } ?? "" }
    /// The model the user's harness starts new sessions on.
    public var defaultModel: Model { Self.defaultModel(in: settings) ?? Self.stock }

    /// The harness's own environment, and nothing of VibeWand's: it finds its keys and sign-ins in its home.
    private var environment: [String: String] {
        ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8", "DSH_HOME": home.path]
    }

    /// Writes VibeWand's profile into the harness's home and describes the process to start. Nothing else in
    /// that home is written by VibeWand: its sessions, credentials and other profiles are the harness's.
    /// `support` is VibeWand's own folder for this mode. Its `VibeWand` subfolder is the working directory the
    /// conversations are filed under in the harness's apps.
    public func launch(version: String, allowUnverified: Bool, support: URL, model: Model?, instructions: String = "") throws -> KernelLaunch {
        guard Self.verified.contains(version) || allowUnverified else { throw Failure.unverified(version) }
        let files = FileManager.default
        let profile = home.appendingPathComponent("profiles/\(Self.profile)"), modules = profile.appendingPathComponent("node_modules")
        let logs = support.appendingPathComponent("logs"), workspace = support.appendingPathComponent("VibeWand")
        for directory in [modules, logs, workspace] { try files.createDirectory(at: directory, withIntermediateDirectories: true) }
        let manifest = JSONValue(data: try Data(contentsOf: bundle.appendingPathComponent("package.json")))
        guard let package = manifest?["name"]?.string, let release = manifest?["version"]?.string else { throw CocoaError(.fileReadCorruptFile) }
        try Data("""
            {
              "name": "dsh-profile-vibewand",
              "private": true,
              "dependencies": {},
              "dsh": { "profile": { "bundles": ["\(package)"], "patchReload": "startup" } }
            }

            """.utf8).write(to: profile.appendingPathComponent("package.json"))
        try Data("# VibeWand's profile. The tree comes from its bundle; this root stays empty.\n[]\n".utf8).write(to: profile.appendingPathComponent("cordis.yml"))
        // The harness resolves a profile's bundles from beside the profile, and its own packages from its installation.
        let link = modules.appendingPathComponent(package)
        try? files.removeItem(at: link)
        try files.createSymbolicLink(at: link, withDestinationURL: bundle)
        // Models are set up in the harness's own apps, which write them to the profile they run on. Copied at every
        // start, so a change made there is in force for the next conversation.
        let rows = Self.rows(Self.modelRows, in: settings)
        let header = "# Written by VibeWand at each start from the \(source ?? "(no)") profile's model rows. Edits here are lost.\n"
        try Data((header + (rows.isEmpty ? "[]\n" : rows)).utf8).write(to: profile.appendingPathComponent("cordis.patch.yml"))
        // The harness loads a bundle only on the versions its manifest declares. Trying another is the user's
        // decision, recorded the way the harness itself records it: for this exact pair and no other.
        let exemption = profile.appendingPathComponent("compatibility.json")
        if Self.verified.contains(version) { try? files.removeItem(at: exemption) }
        else { try Data(JSONValue.object(["\(package)@\(release)": [.string(version)]]).text.utf8).write(to: exemption) }

        var environment = environment
        environment["VIBEWAND_SYSTEM_PROMPT"] = CoordinatorPrompt.system(instructions: instructions)
        let chosen = model ?? defaultModel
        environment["VIBEWAND_MODEL"] = JSONValue.object(["provider": .string(chosen.provider), "model": .string(chosen.model)]).text
        return KernelLaunch(executable: launcher, arguments: ["--profile", Self.profile], environment: environment,
                            directory: workspace, log: logs.appendingPathComponent("kernel.log"))
    }

    // MARK: Reading the user's profile

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
