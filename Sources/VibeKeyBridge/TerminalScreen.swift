import ApplicationServices

/// What a command-line agent shows where the terminal cursor is.
enum TerminalPrompt: Equatable {
    /// A recognised prompt with nothing typed: the place a typed command may go.
    case empty
    /// A recognised prompt holding text.
    case draft
    /// No prompt, and a key hint for Esc on screen: a list or dialog covers it.
    case list
    case unknown
}

/// A terminal draws its whole interface as text, so the prompt can only be
/// found by reading the rows around the cursor. They are reduced to a
/// `TerminalPrompt` and dropped: never kept, logged or exported.
struct TerminalScreen {
    /// Rows from a few above the cursor's down to the end of the screen.
    let rows: [String]
    /// The cursor's row in `rows`, and its UTF-16 offset in that row.
    let row: Int
    let column: Int

    init(rows: [String], row: Int, column: Int) {
        // Cells an agent never wrote come back as NUL, and Claude Code pads with them.
        self.rows = rows.map { $0.replacingOccurrences(of: "\0", with: " ").replacingOccurrences(of: "\u{A0}", with: " ") }
        self.row = row; self.column = column
    }

    /// A draft with the cursor at its very start looks like an empty prompt
    /// showing a placeholder. `draft` holds the `fingerprints` from when the
    /// prompt last had text before the cursor: text still matching one of
    /// them is that draft, not a placeholder.
    func prompt(draft: Set<Int> = []) -> TerminalPrompt {
        let (prompt, _, rest) = reading
        return prompt == .empty && rest.map { draft.contains($0.hashValue) } == true ? .draft : prompt
    }

    /// Fingerprints of a one-row prompt's text and of the part after the
    /// cursor, which is what remains once everything before it is deleted.
    /// The text itself is not kept.
    var fingerprints: Set<Int> {
        guard case let (_, typed?, rest?) = reading else { return [] }
        return Set([Self.leadingText(typed + rest), rest].filter { !$0.isEmpty }.map(\.hashValue))
    }

    /// True while the prompt is one row with exactly `command` before the
    /// cursor, which is what it looks like after VibeWand typed that command
    /// into an empty prompt. Claude Code may show the command's argument
    /// hint after the cursor; any other text there was a draft.
    func promptHolds(_ command: String) -> Bool {
        guard case let (.draft, typed?, rest?) = reading else { return false }
        return typed == command && (rest.isEmpty || Self.matches(Self.argumentHint, rest))
    }

    private static let rowsAbove = 12
    private static let marks = ["› ", "❯ "]
    private static let numbered = try! NSRegularExpression(pattern: "^\\d+\\. ")
    private static let escapeHint = try! NSRegularExpression(pattern: "\\besc\\b", options: .caseInsensitive)
    private static let argumentHint = try! NSRegularExpression(pattern: "^[\\[<][^\\]>]*[\\]>]$")
    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
    }
    private static func blank(_ text: Substring) -> Bool { text.allSatisfy { $0 == " " } }
    /// Text up to the first wide gap; a sidebar may share the prompt's row.
    private static func leadingText(_ text: String) -> String {
        (text.range(of: "  ").map { String(text[..<$0.lowerBound]) } ?? text).trimmingCharacters(in: .whitespaces)
    }

    /// The prompt state and, when the prompt is a single row, its text before
    /// and after the cursor. After the cursor of an empty prompt stands its placeholder.
    private var reading: (prompt: TerminalPrompt, typed: String?, rest: String?) {
        guard rows.indices.contains(row) else { return (.unknown, nil, nil) }
        let cursorRow = rows[row] as NSString
        let offset = min(max(column, 0), cursorRow.length)
        let before = cursorRow.substring(to: offset), after = cursorRow.substring(from: offset)
        if let found = leadingPrompt(before: before, after: after) ?? boxedPrompt(before: before, after: after) { return found }
        return (rows.contains { Self.matches(Self.escapeHint, $0) } ? .list : .unknown, nil, nil)
    }

    /// Codex and Claude Code open the prompt's first row with a mark in the
    /// first column; wrapped and further rows are indented by two.
    private func leadingPrompt(before: String, after: String) -> (TerminalPrompt, String?, String?)? {
        var first = row
        while !Self.marks.contains(where: { rows[first].hasPrefix($0) }) {
            guard first > 0, row - first < Self.rowsAbove, rows[first].hasPrefix("  "),
                  first == row || !Self.blank(rows[first][...]) else { return nil }
            first -= 1
        }
        // Codex marks the selected row of a numbered list the same way.
        guard !Self.matches(Self.numbered, String(rows[first].dropFirst(2))) else { return nil }
        if first < row { return (.draft, nil, nil) }
        let below = rows.indices.contains(row + 1) ? rows[row + 1] : ""
        if below.hasPrefix("  ") && !Self.blank(below[...]) { return (.draft, nil, nil) }
        let typed = before.dropFirst(2)
        return (typed.isEmpty ? .empty : .draft, String(typed), Self.leadingText(after))
    }

    /// OpenCode opens every row of its prompt box with a bar, and closes the
    /// box with a corner below the bar after a spacer and the agent's row.
    private func boxedPrompt(before: String, after: String) -> (TerminalPrompt, String?, String?)? {
        guard let bar = before.range(of: "┃", options: .backwards) else { return nil }
        let inside = before[bar.upperBound...], typed = inside.dropFirst(2)
        // A draft's text ends at the cursor; a gap before it means the cursor is in something drawn over the box.
        guard inside.hasPrefix("  "), !typed.hasSuffix("  "), typed.isEmpty || !Self.blank(typed) else { return nil }
        let barOffset = before[..<bar.lowerBound].utf16.count
        func cell(_ index: Int) -> String {
            let text = rows[index] as NSString
            return barOffset < text.length ? text.substring(with: NSRange(location: barOffset, length: 1)) : ""
        }
        /// Text of another row of the box; nil for a row that is not part of
        /// its text area, such as the command list OpenCode stacks on top.
        func text(_ index: Int) -> String? {
            guard cell(index) == "┃" else { return nil }
            let content = (rows[index] as NSString).substring(from: barOffset + 1)
            return content.hasPrefix("  ") || Self.blank(content[...]) ? Self.leadingText(String(content.dropFirst(2))) : nil
        }
        var bottom = row + 1
        while rows.indices.contains(bottom), cell(bottom) == "┃", bottom - row < Self.rowsAbove { bottom += 1 }
        guard rows.indices.contains(bottom), cell(bottom) == "╹" else { return nil }
        var others = ((row + 1)..<max(row + 1, bottom - 2)).contains { text($0)?.isEmpty == false }
        var above = row - 1
        while above >= 0, row - above <= Self.rowsAbove, let line = text(above) { others = others || !line.isEmpty; above -= 1 }
        if others { return (.draft, nil, nil) }
        return (typed.isEmpty ? .empty : .draft, String(typed), Self.leadingText(after))
    }
}

extension TerminalScreen {
    /// Reads the rows next to the cursor of a terminal's text area: one range
    /// from a few rows above the cursor to the end, never the scrollback.
    init?(area: AXUIElement) {
        AXUIElementSetMessagingTimeout(area, 0.02)
        func range(_ value: CFTypeRef?) -> CFRange? {
            guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
        }
        func attribute(_ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(area, name as CFString, &value) == .success ? value : nil
        }
        func parameter(_ name: String, _ argument: CFTypeRef) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyParameterizedAttributeValue(area, name as CFString, argument, &value) == .success ? value : nil
        }
        guard let cursor = range(attribute(kAXSelectedTextRangeAttribute)),
              let line = (parameter(kAXLineForIndexParameterizedAttribute, cursor.location as CFNumber) as? NSNumber)?.intValue,
              let cursorLine = range(parameter(kAXRangeForLineParameterizedAttribute, line as CFNumber)) else { return nil }
        let first = max(0, line - Self.rowsAbove)
        guard var span = range(parameter(kAXRangeForLineParameterizedAttribute, first as CFNumber)),
              let total = (attribute(kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue else { return nil }
        span.length = min(total - span.location, 20_000)
        guard span.length > 0, let value = AXValueCreate(.cfRange, &span),
              let text = parameter(kAXStringForRangeParameterizedAttribute, value) as? String else { return nil }
        self.init(rows: text.components(separatedBy: "\n"), row: line - first, column: cursor.location - cursorLine.location)
    }
}
