import Foundation

/// The local record of one instruction: what was asked, each step, how it ended.
/// The overlay's "done" comes from here, not from what the model says last.
/// Lines are appended as they happen, so a crash leaves the steps taken so far.
public final class TaskJournal: @unchecked Sendable {
    public let directory: URL
    private let handle: FileHandle
    private let lock = NSLock()

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
        var line = fields
        line["kind"] = .string(kind)
        line["time"] = .string(ISO8601DateFormatter().string(from: Date()))
        lock.lock(); defer { lock.unlock() }
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
}
