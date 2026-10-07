import Foundation

/// A dictated passage as VibeWand wrote it and as the user left it once they had gone over it. What they changed
/// is where the recogniser was wrong, and that is what the vocabulary is learned from.
public struct DictationRevision: Codable, Equatable, Identifiable, Sendable {
    public struct Change: Codable, Equatable, Sendable {
        public var from: String
        public var to: String
        public init(from: String, to: String) { self.from = from; self.to = to }
    }
    public var id: String
    public var time: Date
    /// The app the passage was written in, by name.
    public var app: String
    public var said: String
    public var kept: String
    /// The places where the two differ, in order.
    public var changes: [Change]

    /// A passage longer than this is not a sentence someone corrected a word in.
    public static let longest = 1_000

    /// Reads a revision out of a text field. `written` is what dictation put into it, `before` the field's
    /// whole text right after that, and `after` its text when the user was done with it. nil when the passage
    /// cannot be found again, was left as it was, was only added to, or was written anew rather than corrected.
    public static func read(written: String, before: String, after: String, app: String, now: Date = Date()) -> DictationRevision? {
        guard !written.isEmpty, written.count <= longest, let place = before.range(of: written, options: .backwards) else { return nil }
        // What stood around the passage has to stand there still: otherwise there is no telling what became of it.
        let head = before[..<place.lowerBound], tail = before[place.upperBound...]
        guard after.count >= head.count + tail.count, after.hasPrefix(head), after.hasSuffix(tail) else { return nil }
        let kept = String(after.dropFirst(head.count).dropLast(tail.count))
        guard kept != written, kept.count <= longest else { return nil }
        let old = tokens(written), new = tokens(kept)
        var changes = differences(old, new)
        // Typing on after the passage, or in front of it, corrects nothing in it.
        if let last = changes.last, last.old.isEmpty, last.at == old.count { changes.removeLast() }
        if let first = changes.first, first.old.isEmpty, first.at == 0 { changes.removeFirst() }
        // Words side by side that were both changed are one correction: "cloud code" became "Claude Code".
        var joined: [(at: Int, old: [String], new: [String])] = []
        for change in changes {
            if let last = joined.last {
                let between = old[(last.at + last.old.count)..<change.at]
                if between.allSatisfy({ $0.allSatisfy(\.isWhitespace) }) {
                    joined[joined.count - 1].old += between + change.old; joined[joined.count - 1].new += between + change.new
                    continue
                }
            }
            joined.append(change)
        }
        changes = joined
        let worded = changes.map { Change(from: $0.old.joined().trimmingCharacters(in: .whitespacesAndNewlines), to: $0.new.joined().trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.from != $0.to && ($0.from + $0.to).contains(where: { $0.isLetter || $0.isNumber }) }
        // A passage that was mostly replaced was said again in other words. A short one changed in a single
        // place may still be little more than the word that was wrong.
        let replaced = changes.reduce(0) { $0 + $1.old.count }
        guard !worded.isEmpty, replaced * 5 <= old.count * (old.count <= 12 && changes.count == 1 ? 4 : 3) else { return nil }
        return DictationRevision(id: UUID().uuidString, time: now, app: app, said: written, kept: kept, changes: worded)
    }

    /// Words of a script written with spaces stay whole; everything else is taken a character at a time.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = [], word = ""
        for character in text {
            if character.isASCII, character.isLetter || character.isNumber { word.append(character); continue }
            if !word.isEmpty { tokens.append(word); word = "" }
            tokens.append(String(character))
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    /// The stretches where two token lists differ, each with where it starts in the first.
    static func differences(_ old: [String], _ new: [String]) -> [(at: Int, old: [String], new: [String])] {
        // The longest common subsequence, by the lengths of what remains from each pair of places.
        var rest = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                rest[i][j] = old[i] == new[j] ? rest[i + 1][j + 1] + 1 : max(rest[i + 1][j], rest[i][j + 1])
            }
        }
        var found: [(at: Int, old: [String], new: [String])] = [], open: (at: Int, old: [String], new: [String])?
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                if let stretch = open { found.append(stretch); open = nil }
                i += 1; j += 1
            } else if j < new.count, i == old.count || rest[i][j + 1] >= rest[i + 1][j] {
                open = open ?? (i, [], []); open?.new.append(new[j]); j += 1
            } else {
                open = open ?? (i, [], []); open?.old.append(old[i]); i += 1
            }
        }
        if let open { found.append(open) }
        return found
    }
}

/// The revisions waiting to be learned from, in a file of VibeWand's own on this Mac. They leave it when the
/// vocabulary has been brought up to date with them, or when the user stops the learning.
public struct VocabularyNotebook: Sendable {
    /// As many as are kept; the oldest give way.
    public static let limit = 300
    public let file: URL
    public init(directory: URL) { file = directory.appendingPathComponent("revisions.jsonl") }

    public func pending() -> [DictationRevision] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n")
            .compactMap { try? decoder.decode(DictationRevision.self, from: Data($0.utf8)) }
    }
    public func add(_ revision: DictationRevision) { write(Array((pending() + [revision]).suffix(Self.limit))) }
    /// Takes out the revisions that have been learned from.
    public func settle(_ ids: Set<String>) { write(pending().filter { !ids.contains($0.id) }) }
    public func clear() { try? FileManager.default.removeItem(at: file) }

    private func write(_ revisions: [DictationRevision]) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = revisions.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8).write(to: file, options: .atomic)
    }
}
