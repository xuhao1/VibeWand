import Foundation

/// A chat in a downstream app, as that app's own list reports it.
public struct ChatSession: Equatable, Sendable {
    public var id: String
    public var title: String
    /// Last component of the project directory.
    public var folder: String
    public var updated: Date
    public init(id: String, title: String, folder: String, updated: Date) {
        self.id = id; self.title = title; self.folder = folder; self.updated = updated
    }

    /// Keeps the chats whose title or folder contains a word of the query, newest first.
    /// Speech rarely reproduces a title exactly, so when nothing matches the recent chats are
    /// returned, marked as unmatched, for the model to judge.
    public static func rank(_ sessions: [ChatSession], query: String?, limit: Int) -> (sessions: [ChatSession], matched: Bool) {
        let recent = sessions.sorted { $0.updated > $1.updated }
        let words = (query ?? "").lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        let matches = recent.filter { session in
            let text = (session.title + " " + session.folder).lowercased()
            return words.contains { text.contains($0) }
        }
        return (Array((matches.isEmpty ? recent : matches).prefix(limit)), words.isEmpty || !matches.isEmpty)
    }
}

/// Codex's own JSON-RPC interface. It lists chats without touching the Codex window.
public final class CodexAppServer {
    private let process = Process()
    private let stdin = Pipe()
    private let rpc: LineRPC
    private var handshake: Task<Void, Error>?

    public init(executable: URL) throws {
        signal(SIGPIPE, SIG_IGN)
        let stdout = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        rpc = LineRPC(input: stdout.fileHandleForReading, output: stdin.fileHandleForWriting)
        process.terminationHandler = { [rpc] _ in rpc.close() }
        try process.run()
        rpc.start()
    }

    /// The most recently updated chats, as many as `limit`.
    public func sessions(limit: Int) async throws -> [ChatSession] {
        if handshake == nil {
            handshake = Task { [rpc] in
                _ = try await rpc.request("initialize", ["clientInfo": ["name": "vibewand", "title": "VibeWand", "version": "1"]])
                rpc.notify("initialized")
            }
        }
        try await handshake?.value
        return Self.parse(try await rpc.request("thread/list", ["limit": .number(Double(limit)), "sortKey": "updated_at"]))
    }

    public func stop() {
        try? stdin.fileHandleForWriting.close()
        let process = self.process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if process.isRunning { process.terminate() } }
    }

    static func parse(_ result: JSONValue) -> [ChatSession] {
        (result["data"]?.array ?? []).compactMap { thread in
            guard let id = thread["id"]?.string else { return nil }
            // A thread the user never named is known by the start of its first message.
            let preview = thread["preview"]?.string?.split(separator: "\n").first.map(String.init) ?? ""
            let name = thread["name"]?.string ?? ""
            return ChatSession(id: id, title: String((name.isEmpty ? preview : name).prefix(80)),
                               folder: URL(fileURLWithPath: thread["cwd"]?.string ?? "").lastPathComponent,
                               updated: Date(timeIntervalSince1970: thread["updatedAt"]?.number ?? 0))
        }
    }

    /// The CLI inside the desktop app matches the app's version; a separate install is the fallback.
    public static func locate(desktopApp: URL?) -> URL? {
        let bundled = desktopApp.map { [$0.appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path] } ?? []
        let installed = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex"]
        return (bundled + installed).first(where: FileManager.default.isExecutableFile).map(URL.init(fileURLWithPath:))
    }
}
