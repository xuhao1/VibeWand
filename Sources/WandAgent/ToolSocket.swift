import Foundation

/// Serves the tools to the kernel as an MCP server on a Unix socket. The kernel
/// reaches it through `nc -U`, so no network port is opened.
public final class ToolSocket {
    public typealias Call = (String, JSONValue) async -> ToolOutcome
    public let path: String
    public var relay: ToolRelay { ToolRelay(name: "vibewand", command: "/usr/bin/nc", arguments: ["-U", path]) }
    /// Whoever connects can press controls with this app's Accessibility grant,
    /// so only a process the owner vouches for is let in.
    public var admits: (pid_t) -> Bool = { _ in true }

    private let listener: Int32
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "vibewand.tools")
    private let tools: [ToolDefinition]
    private let call: Call
    private var connections: [LineRPC] = []

    public init(path: String, tools: [ToolDefinition] = ToolCatalog.all, call: @escaping Call) throws {
        self.path = path; self.tools = tools; self.call = call
        listener = try Self.listen(at: path)
        source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { [listener] in Darwin.close(listener) }
        source.resume()
    }

    public func close() {
        source.cancel()
        unlink(path)
        queue.async { self.connections.forEach { $0.close() }; self.connections.removeAll() }
    }

    private static func listen(at path: String) throws -> Int32 {
        unlink(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { Darwin.close(descriptor); throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(descriptor, 4) == 0 else {
            let code = errno; Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        chmod(path, 0o600)
        return descriptor
    }

    private func accept() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        var peer: pid_t = 0, size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) == 0, admits(peer) else { Darwin.close(client); return }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let handle = FileHandle(fileDescriptor: client, closeOnDealloc: true)
        let rpc = LineRPC(input: handle, output: handle)
        rpc.onRequest = { [weak self] method, params, reply in self?.answer(method, params, reply) }
        rpc.onClose = { [weak self, weak rpc] in self?.queue.async { self?.connections.removeAll { $0 === rpc } } }
        connections.append(rpc)
        rpc.start()
    }

    private func answer(_ method: String, _ params: JSONValue, _ reply: @escaping LineRPC.Reply) {
        switch method {
        case "initialize":
            reply(.success(["protocolVersion": params["protocolVersion"] ?? "2025-06-18", "capabilities": ["tools": [:]],
                            "serverInfo": ["name": "vibewand", "version": "1"]]))
        case "tools/list": reply(.success(["tools": .array(tools.map(\.wire))]))
        case "tools/call":
            guard let name = params["name"]?.string else { reply(.failure(RPCError(code: -32602, message: "Missing tool name"))); return }
            let call = self.call
            Task {
                let outcome = await call(name, params["arguments"] ?? [:])
                var content: [JSONValue] = [["type": "text", "text": .string(outcome.text)]]
                if let image = outcome.image { content.append(["type": "image", "data": .string(image.base64EncodedString()), "mimeType": "image/jpeg"]) }
                reply(.success(["content": .array(content), "isError": .bool(outcome.isError)]))
            }
        case "ping": reply(.success([:]))
        // Newer discovery methods are declined; clients fall back to `initialize`.
        default: reply(.failure(.methodNotFound))
        }
    }
}

public enum ProcessTree {
    /// Whether `pid` is `ancestor` itself or was started, directly or not, by it.
    public static func descends(_ pid: pid_t, from ancestor: pid_t) -> Bool {
        var current = pid
        for _ in 0..<16 {
            if current == ancestor { return true }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard current > 1, proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
            current = pid_t(info.pbi_ppid)
        }
        return false
    }
}
