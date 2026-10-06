import Foundation

/// Paces a transcript that arrives in bursts into text that grows a few characters at a time. A recogniser hands
/// over whole phrases; shown as they come they jump, shown through this they are typed.
public struct TranscriptTypewriter {
    public private(set) var shown = ""
    private var target = ""
    private var revised = false
    public init() {}

    /// The newest reading of the whole recording. Where it disagrees with what is shown, the shown text is put
    /// right in place, at the length it already has.
    public mutating func aim(_ text: String) {
        target = text
        if !text.hasPrefix(shown) { shown = String(text.prefix(shown.count)); revised = true }
    }
    /// The next text to show, or nil when what is shown is already the target. A long backlog is caught up
    /// within a few steps; a short one goes a character at a time.
    public mutating func advance() -> String? {
        let backlog = target.count - shown.count
        guard backlog > 0 || revised else { return nil }
        revised = false
        if backlog > 0 { shown = String(target.prefix(shown.count + max(1, backlog / 8))) }
        return shown
    }
}
