import AppKit
import ApplicationServices

/// Chromium/Electron requires a normal editing action. Keep the user's
/// clipboard in memory and restore it only if nobody copied something else.
final class ClipboardTextDelivery {
    private let board: NSPasteboard
    private let original: [[NSPasteboard.PasteboardType: Data]]
    private var ownedChangeCount: Int?
    private var timer: Timer?
    private var postedAt: TimeInterval = 0
    init(board: NSPasteboard = .general) {
        self.board = board
        original = board.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        } ?? []
    }
    func post(_ text: String, pid: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        prepare(text)
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
            event?.post(tap: .cghidEventTap)
        }
        // Cleanup is also scheduled if the session disappears before ACK.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [self] _ in
            restore(confirmed: false)
        }
    }
    func prepare(_ text: String) {
        board.clearContents(); board.setString(text, forType: .string); ownedChangeCount = board.changeCount
        postedAt = ProcessInfo.processInfo.systemUptime
    }
    func restore(confirmed: Bool = true) {
        timer?.invalidate(); timer = nil
        let remaining = 0.15 - (ProcessInfo.processInfo.systemUptime - postedAt)
        if !confirmed, remaining > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [self] _ in restore(confirmed: true) }
            return
        }
        guard let count = ownedChangeCount, board.changeCount == count else { ownedChangeCount = nil; return }
        ownedChangeCount = nil; board.clearContents()
        let items = original.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
    }
}
