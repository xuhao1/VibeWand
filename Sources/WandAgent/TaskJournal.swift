import Foundation

/// The local record of one instruction: what was asked, what the model thought
/// and said, each tool call with what it answered and showed, and how it ended.
/// The overlay's "done" comes from here, not from what the model says last.
/// Lines are appended as they happen, so a crash leaves the steps taken so far.
public final class TaskJournal: @unchecked Sendable {
    /// A tool's answer is kept up to this many characters; a long window listing is cut.
    public static let resultLimit = 4_000
    public let directory: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private var thought = "", message = ""
    private var pictures = 0
    /// Calls of the runtime's own tools that have started. VibeWand's own are recorded by the gateway, which ran them.
    private var foreign: [String: String] = [:]
    /// The name the runtime gives a tool VibeWand mounted.
    public static let mounted = "mcp__vibewand__"

    public init(root: URL, now: Date = Date()) throws {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyyMMdd-HHmmss"
        directory = root.appendingPathComponent("\(stamp.string(from: now))-\(UUID().uuidString.prefix(6).lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("journal.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try FileHandle(forWritingTo: file)
    }

    public func record(_ kind: String, _ fields: [String: JSONValue] = [:]) {
        lock.lock(); defer { lock.unlock() }
        write(kind, fields)
    }

    /// Follows the kernel's turn. Thinking and speech arrive in pieces and are written whole,
    /// before the step they led to.
    public func note(_ event: KernelEvent) {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case .thought(let text): thought += text
        case .message(let text): message += text
        case .toolStarted(let id, let name, let input):
            flush()
            guard !name.hasPrefix(Self.mounted) else { break }
            foreign[id] = name
            write("call", ["tool": .string(name), "arguments": input])
        case .toolEnded(let id, let failed, let text):
            guard let name = foreign.removeValue(forKey: id) else { break }
            write("result", ["tool": .string(name), "ok": .bool(!failed), "verified": true, "text": .string(String(text.prefix(Self.resultLimit)))])
        case .usage(let used, let size): write("usage", ["used": .number(Double(used)), "size": .number(Double(size))])
        }
    }
    /// Keeps a picture a tool showed the model beside the record and returns its file name.
    public func keep(_ image: Data) -> String? {
        lock.lock(); defer { lock.unlock() }
        pictures += 1
        let name = "picture-\(pictures).jpg"
        return (try? image.write(to: directory.appendingPathComponent(name))) != nil ? name : nil
    }

    /// Writes what the model thought and said since the last step. Called once more when the turn ends.
    public func settle() {
        lock.lock(); defer { lock.unlock() }
        flush()
    }

    private func flush() {
        for (kind, text) in [("thought", thought), ("message", message)] where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            write(kind, ["text": .string(text)])
        }
        thought = ""; message = ""
    }
    private func write(_ kind: String, _ fields: [String: JSONValue]) {
        var line = fields
        line["kind"] = .string(kind)
        line["time"] = .string(ISO8601DateFormatter().string(from: Date()))
        try? handle.write(contentsOf: Data((JSONValue.object(line).text + "\n").utf8))
    }

    /// Removes every task record, or those older than `days`.
    public static func clear(root: URL, olderThan days: Int? = nil) {
        let files = FileManager.default
        guard let tasks = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = days.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        for task in tasks {
            if let cutoff, let created = try? task.resourceValues(forKeys: [.creationDateKey]).creationDate, created > cutoff { continue }
            try? files.removeItem(at: task)
        }
    }

    /// The most recent records, newest first, for the history the user reads.
    public static func recent(root: URL, limit: Int = 100) -> [TaskRecord] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted(by: >)
        return names.prefix(limit).compactMap { name in
            guard let text = try? String(contentsOf: root.appendingPathComponent(name).appendingPathComponent("journal.jsonl"), encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n").compactMap { JSONValue(data: Data($0.utf8)) }
            return lines.isEmpty ? nil : TaskRecord(id: name, lines: lines, directory: root.appendingPathComponent(name))
        }
    }
}

/// One instruction as it was recorded, read back.
public struct TaskRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let lines: [JSONValue]
    /// Where the record and the pictures it names are kept.
    public let directory: URL

    private func first(_ kind: String) -> JSONValue? { lines.first { $0["kind"]?.string == kind } }
    private func last(_ kind: String) -> JSONValue? { lines.last { $0["kind"]?.string == kind } }
    public var instruction: String { first("instruction")?["text"]?.string ?? "" }
    public var app: String { first("instruction")?["app"]?.string ?? "" }
    public var model: String { first("instruction")?["model"]?.string ?? "" }
    /// 1 for the instruction that opened a conversation.
    public var turn: Int { first("instruction")?["turn"]?.int ?? 1 }
    public var started: Date? { (lines.first?["time"]?.string).flatMap { ISO8601DateFormatter().date(from: $0) } }
    public var steps: Int { lines.filter { $0["kind"]?.string == "call" }.count }
    /// Context occupied when the instruction ended, and what the model's context holds.
    public var usage: (used: Int, size: Int)? {
        guard let line = last("usage"), let used = line["used"]?.int, let size = line["size"]?.int else { return nil }
        return (used, size)
    }
    /// What the user was told at the end, and whether that was a completed task.
    public var outcome: (text: String, finished: Bool)? {
        guard let end = last("end") else { return nil }
        return (end["said"]?.string ?? "", end["finished"]?.bool ?? false)
    }
}
