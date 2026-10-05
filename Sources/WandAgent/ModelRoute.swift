import Foundation

/// The model the coordinator reasons with: where it is served, the protocol
/// that endpoint speaks, and what was chosen on it. Nothing here names a vendor.
public struct ModelRoute: Equatable, Sendable {
    public enum Wire: String, CaseIterable, Codable, Sendable {
        /// `POST {base}/chat/completions`, what most services and local servers offer.
        case openAIChat = "openai-chat"
        /// `POST {base}/responses`.
        case openAIResponses = "openai-responses"
        /// `POST {base}/v1/messages`.
        case anthropic
    }
    /// How hard the model thinks before it acts. `automatic` sends nothing and leaves the service's own default.
    public enum Reasoning: String, CaseIterable, Codable, Sendable { case automatic, off, low, medium, high }

    public var wire: Wire
    public var baseURL: String
    public var model: String
    /// nil for a server that asks for none.
    public var key: String?
    /// Tokens the model's context holds. nil leaves the kernel's own assumption.
    public var contextWindow: Int?
    public var reasoning: Reasoning
    /// The model takes pictures as well as text. It is the user's word for it: the service is not asked.
    public var images: Bool
    /// Further provider settings in the kernel's own vocabulary. They win over the ones derived from the fields above.
    public var extra: [String: JSONValue]

    public init(wire: Wire, baseURL: String, model: String, key: String? = nil, contextWindow: Int? = nil,
                reasoning: Reasoning = .automatic, images: Bool = false, extra: [String: JSONValue] = [:]) {
        self.wire = wire; self.baseURL = baseURL; self.model = model; self.key = key
        self.contextWindow = contextWindow; self.reasoning = reasoning; self.images = images; self.extra = extra
    }
}

/// One model an endpoint says it serves.
public struct ListedModel: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var contextWindow: Int?
    public init(id: String, name: String? = nil, contextWindow: Int? = nil) {
        self.id = id; self.name = name; self.contextWindow = contextWindow
    }
}

/// Asks an endpoint which models it serves, so a model is picked rather than typed.
public enum ModelListing {
    public enum Failure: Error, Equatable {
        case address
        case unreachable
        case status(Int)
        /// The endpoint answered, but not with a list of models.
        case unreadable
    }

    /// Where the endpoint lists its models, with the credential the way its protocol expects it.
    public static func request(wire: ModelRoute.Wire, baseURL: String, key: String?) -> URLRequest? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        var address = base + "/models"
        if wire == .anthropic {
            // Documentation publishes this root both with and without the version segment.
            address = (base.hasSuffix("/v1") ? String(base.dropLast(3)) : base) + "/v1/models?limit=1000"
        }
        guard let url = URL(string: address), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if wire == .anthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "x-api-key") }
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Reads the usual `data` array, or the `models` array some servers answer with. Entries without an id are dropped.
    public static func parse(_ data: Data) -> [ListedModel]? {
        guard let body = JSONValue(data: data), let entries = body["data"]?.array ?? body["models"]?.array else { return nil }
        return entries.compactMap { entry in
            if let id = entry.string { return ListedModel(id: id) }
            guard let id = entry["id"]?.string ?? entry["name"]?.string, !id.isEmpty else { return nil }
            let name = (entry["display_name"] ?? entry["name"])?.string
            let window = ["context_window", "context_length", "max_context_length", "max_model_len", "inputTokenLimit"]
                .lazy.compactMap { entry[$0]?.int }.first { $0 > 0 }
            return ListedModel(id: id, name: name == id ? nil : name, contextWindow: window)
        }
    }

    public static func fetch(wire: ModelRoute.Wire, baseURL: String, key: String?, session: URLSession = .shared) async throws -> [ListedModel] {
        guard let request = request(wire: wire, baseURL: baseURL, key: key) else { throw Failure.address }
        guard let (data, response) = try? await session.data(for: request) else { throw Failure.unreachable }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.status(status) }
        guard let models = parse(data), !models.isEmpty else { throw Failure.unreadable }
        return models
    }
}
