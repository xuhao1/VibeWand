import Foundation

/// The wire between VibeWand and its input method: where the two meet and what they say to each other, one JSON
/// object per line over a Unix socket in VibeWand's own folder.
public enum InputLink {
    /// macOS takes a bundle for an input method only when its identifier contains ".inputmethod.". This one keeps
    /// the name it had before the app became `org.vibewand.bridge`: macOS remembers by identifier which input
    /// methods of other makers the user has enabled, selects none that is not among them, and gives an app no
    /// way to add one (tried on 2026-10-07: `TISEnableInputSource` returns no error, brings System Settings to
    /// the front and enables nothing). Under another identifier it would be off for everyone who has it on.
    public static let bundleID = "org.vibekey.inputmethod.VibeWand"
    /// The name InputMethodKit itself derives for an input method: its identifier and "_Connection".
    public static let connectionName = bundleID + "_Connection"
    /// The only program the input method takes text from.
    public static let owner = "org.vibewand.bridge"
    /// What the app was called until 0.11.0; the settings it kept under that name are taken over.
    public static let formerOwner = "org.vibekey.bridge"
    public static var socketPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeWand/input.sock").path
    }

    public static func connect(to path: String) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard var address = socketAddress(path), descriptor >= 0, withUnsafePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }) == 0 else { close(descriptor); return nil }
        return descriptor
    }
    fileprivate static func listen(at path: String) throws -> Int32 {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard var address = socketAddress(path), descriptor >= 0, withUnsafePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }) == 0, Darwin.listen(descriptor, 4) == 0 else {
            let code = errno; close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        chmod(path, 0o600)
        return descriptor
    }
    private static func socketAddress(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return nil }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        return address
    }
}

public enum InputMessage: Codable, Equatable {
    /// VibeWand: a dictation starts in the active text field of this app.
    case begin(String)
    /// VibeWand: everything heard so far, in place of what was shown before.
    case show(String)
    /// VibeWand: the finished text, in place of what was shown.
    case commit(String)
    /// VibeWand: take back what was shown. Answered with `committed(false)` once the field no longer holds it.
    case cancel
    /// Input method: the app whose text field it can write into now, or nil.
    case client(String?)
    /// Input method: whether the finished text was written.
    case committed(Bool)
    /// Input method: the text field ended the dictation by itself; what was shown stays as written.
    case interrupted
    /// Input method: the text field takes no provisional text; nothing was written there.
    case refused
}

/// One end of the link. Messages arrive on the main queue.
public final class InputLine {
    public var onMessage: ((InputMessage) -> Void)?
    public var onClose: (() -> Void)?
    private let descriptor: Int32
    private let source: DispatchSourceRead
    private var buffer = Data()
    private var open = true

    public init(descriptor: Int32) {
        self.descriptor = descriptor
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.read() }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }
    deinit { source.cancel() }

    public func send(_ message: InputMessage) {
        guard open, var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = write(descriptor, bytes.baseAddress! + sent, bytes.count - sent)
                guard count > 0 else { return }
                sent += count
            }
        }
    }
    public func close() { open = false; source.cancel() }

    private func read() {
        var bytes = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        guard count > 0 else { close(); onClose?(); return }
        buffer.append(contentsOf: bytes[..<count])
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            // A line this version does not know is not ours to interpret.
            if let message = try? JSONDecoder().decode(InputMessage.self, from: line) { onMessage?(message) }
        }
    }
}

/// The input method's end of the socket: one connection at a time, from a process it admits.
public final class InputListener {
    private let source: DispatchSourceRead

    public init(path: String, admits: @escaping (pid_t) -> Bool, onLine: @escaping (InputLine) -> Void) throws {
        let listener = try InputLink.listen(at: path)
        source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
        source.setEventHandler {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            var peer: pid_t = 0, size = socklen_t(MemoryLayout<pid_t>.size)
            guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) == 0, admits(peer) else { close(client); return }
            onLine(InputLine(descriptor: client))
        }
        source.setCancelHandler { close(listener); unlink(path) }
        source.resume()
    }
    deinit { source.cancel() }
}
