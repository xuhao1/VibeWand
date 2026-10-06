import Foundation

/// What the input method needs from a text field it writes into.
public protocol InputTextClient: AnyObject {
    /// Bundle identifier of the app the field belongs to.
    var application: String { get }
    /// Shows text that may still change, in place of what was marked before.
    func mark(_ text: String)
    /// Writes text for good, in place of what is marked.
    func insert(_ text: String)
    /// Whether the field still holds marked text.
    var marking: Bool { get }
}

/// Everything the input method does: it shows a dictation's text in the text field that was active when the
/// dictation began, while VibeWand is still hearing it, and writes the finished text over it. A dictation never
/// follows the focus to another field, and what is written is always one line: the input method cannot press
/// Return or Tab, which in a terminal would run what was said.
public final class InputComposer {
    public var send: (InputMessage) -> Void = { _ in }
    private weak var active: (any InputTextClient)?
    /// The field this dictation writes into, and what it shows there so far.
    private weak var field: (any InputTextClient)?
    private var shown: String?
    private var line: InputLine?

    public init() {}

    /// Takes over from any earlier connection: the newest VibeWand is the one being used.
    public func connect(_ line: InputLine) {
        clear()
        self.line?.close()
        self.line = line
        send = { [weak line] in line?.send($0) }
        line.onMessage = { [weak self] in self?.receive($0) }
        // VibeWand went away mid-dictation: nothing provisional is left behind.
        line.onClose = { [weak self, weak line] in if self?.line === line { self?.clear() } }
        send(.client(active?.application))
    }

    public func activate(_ client: any InputTextClient) { active = client; send(.client(client.application)) }
    public func deactivate(_ client: any InputTextClient) {
        interrupt(client)
        if active === client { active = nil; send(.client(nil)) }
    }
    /// The field ends composition, as when the focus leaves it: what was shown is kept as written.
    public func interrupt(_ client: any InputTextClient) {
        guard field === client else { return }
        if let shown, !shown.isEmpty {
            if client.marking { client.insert(shown) }
            send(.interrupted)
        }
        field = nil; shown = nil
    }
    /// A field may also end composition without saying so, as some do on a click: the text it had marked is
    /// then its own, and writing more would put the dictation there a second time.
    private func kept() -> Bool {
        guard let field, let shown, !shown.isEmpty, !field.marking else { return false }
        interrupt(field)
        return true
    }

    /// Takes back what is shown. Asking the field afterwards whether it still marks anything waits for it to
    /// have done so, so whoever is told next can write there another way.
    private func clear() {
        if shown != nil, let field { field.mark(""); _ = field.marking }
        field = nil; shown = nil
    }
    private static func line(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : $0
        }))
    }

    public func receive(_ message: InputMessage) {
        switch message {
        case .begin(let application):
            clear()
            if active?.application == application { field = active }
        case .show(let words):
            let text = Self.line(words)
            guard !kept(), let field else { return }
            field.mark(text)
            // A field that does not hold what it was just given takes no provisional text: VibeWand is told at
            // the first words, while it can still write the dictation another way.
            guard text.isEmpty || field.marking else {
                field.mark("")
                send((shown ?? "").isEmpty ? .refused : .interrupted)
                self.field = nil; shown = nil
                return
            }
            shown = text
        case .commit(let words):
            let text = Self.line(words)
            // The finished text goes the way the shown text went, so "written" is something the field confirmed.
            var written = false
            if !kept(), let field {
                if (shown ?? "").isEmpty { field.mark(text) }
                written = field.marking
                if written { field.insert(text) } else { field.mark("") }
            }
            send(.committed(written))
            field = nil; shown = nil
        case .cancel:
            clear()
            send(.committed(false))
        case .client, .committed, .interrupted, .refused: break
        }
    }
}
