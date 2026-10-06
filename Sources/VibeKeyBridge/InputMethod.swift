import AppKit
import InputLink

/// VibeWand's side of its input method: putting it on this Mac, and the text of a dictation sent to it. With it,
/// a dictation appears in the text field of any app while it is spoken, the way a keyboard input method's own
/// voice input does; without it, only native fields fill in live and the rest get one paste on release.
@MainActor
final class InputMethod: ObservableObject {
    /// Whether the input method is on this Mac and switched on.
    @Published private(set) var enabled = false
    /// Switching on takes macOS a moment; this says it is under way.
    @Published private(set) var starting = false
    /// macOS did not start or select the input method.
    @Published private(set) var failed = false
    @Published private(set) var connected = false
    /// The app whose text field it can write into now.
    @Published private(set) var client: String?
    /// The dictation's text field stopped taking its text: either it kept what was shown and ended the
    /// dictation by itself, or it takes no provisional text and nothing was written.
    var onEnded: ((_ kept: Bool) -> Void)?

    private static let wanted = "dictationInputMethod"
    private let embedded: URL, installed: URL, socket: String
    private var line: InputLine?
    private var committed: ((Bool) -> Void)?

    init(embedded: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VibeWandInput.app"),
         installed: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Input Methods/VibeWandInput.app"),
         socket: String = InputLink.socketPath) {
        self.embedded = embedded; self.installed = installed; self.socket = socket
    }

    /// Whether this build carries the input method at all.
    var available: Bool { FileManager.default.fileExists(atPath: embedded.path) }

    /// At launch: the input method the user asked for is kept the one this build carries, and switched on.
    func start() {
        guard available, UserDefaults.standard.bool(forKey: Self.wanted) else { return }
        try? install()
    }
    func install() throws {
        if stale { quit(); try place() }
        UserDefaults.standard.set(true, forKey: Self.wanted)
        starting = true; failed = false
        run("select") { [weak self] selected in
            guard let self, UserDefaults.standard.bool(forKey: Self.wanted) else { return }
            self.starting = false; self.enabled = selected; self.failed = !selected
            if selected { self.join(attempts: 20) }
        }
    }
    func remove() {
        UserDefaults.standard.set(false, forKey: Self.wanted)
        enabled = false; starting = false; failed = false
        run("deselect") { [weak self] _ in
            guard let self else { return }
            self.quit(); try? FileManager.default.removeItem(at: self.installed)
        }
    }
    /// The input method switches itself on and off in macOS; see `InputSource` there for why it is not done here.
    private func run(_ verb: String, completion: @escaping (Bool) -> Void) {
        let task = Process()
        task.executableURL = installed.appendingPathComponent("Contents/MacOS/VibeWandInput")
        task.arguments = [verb]
        task.terminationHandler = { task in DispatchQueue.main.async { MainActor.assumeIsolated { completion(task.terminationStatus == 0) } } }
        do { try task.run() } catch { completion(false) }
    }
    /// macOS starts a selected input method when an app's text field needs it; this starts it now, so that the
    /// first dictation finds it.
    private func join(attempts: Int) {
        connect()
        guard line == nil, attempts > 0 else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: InputLink.bundleID).contains(where: { !$0.isTerminated }) {
            let quiet = NSWorkspace.OpenConfiguration(); quiet.activates = false; quiet.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: installed, configuration: quiet)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self.join(attempts: attempts - 1) } }
    }
    /// Whether the copy where macOS looks for input methods is missing or is not the one this build carries.
    var stale: Bool {
        ["Contents/MacOS/VibeWandInput", "Contents/Info.plist"].contains {
            !FileManager.default.contentsEqual(atPath: embedded.appendingPathComponent($0).path, andPath: installed.appendingPathComponent($0).path)
        }
    }
    func place() throws {
        let files = FileManager.default
        try files.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? files.removeItem(at: installed)
        try files.copyItem(at: embedded, to: installed)
        // A downloaded VibeWand is quarantined file by file and a copy keeps the mark; macOS would then refuse
        // to start a part of the app the user has already let run.
        let copied = [installed] + (files.enumerator(at: installed, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        for url in copied { removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }
    private func quit() {
        line?.close(); dropped()
        NSRunningApplication.runningApplications(withBundleIdentifier: InputLink.bundleID).forEach { $0.terminate() }
    }
    /// Joins the input method if it is running. macOS starts a selected one when an app needs it.
    func connect() {
        guard line == nil, let descriptor = InputLink.connect(to: socket) else { return }
        let line = InputLine(descriptor: descriptor); self.line = line; connected = true
        line.onMessage = { [weak self] message in MainActor.assumeIsolated { self?.receive(message) } }
        line.onClose = { [weak self] in MainActor.assumeIsolated { self?.dropped() } }
    }
    private func receive(_ message: InputMessage) {
        switch message {
        case .client(let application): client = application
        case .committed(let written): let answer = committed; committed = nil; answer?(written)
        case .interrupted: onEnded?(true)
        case .refused: onEnded?(false)
        case .begin, .show, .commit, .cancel: break
        }
    }
    private func dropped() {
        line = nil; connected = false; client = nil
        let answer = committed; committed = nil; answer?(false)
    }

    /// Starts a dictation in the active text field of `application`; false when the input method cannot write there.
    func begin(_ application: String) -> Bool {
        connect()
        guard client == application, let line else { return false }
        line.send(.begin(application)); return true
    }
    func show(_ text: String) { line?.send(.show(text)) }
    func commit(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let line else { completion(false); return }
        committed = completion; line.send(.commit(text))
    }
    /// Takes back what was shown; `completion` runs once the text field no longer holds it.
    func cancel(completion: (() -> Void)? = nil) {
        committed = completion.map { done in { _ in done() } }
        guard let line else { committed = nil; completion?(); return }
        line.send(.cancel)
    }
}
