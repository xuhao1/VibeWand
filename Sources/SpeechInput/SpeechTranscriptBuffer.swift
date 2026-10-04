import Foundation

/// Providers may revise tentative words. Replace each item's current preview
/// instead of appending full snapshots and accidentally duplicating phrases.
public struct SpeechTranscriptBuffer {
    private var order: [String] = []
    private var items: [String: String] = [:]
    public private(set) var completedItems: Set<String> = []
    public init() {}
    public var text: String { order.compactMap { items[$0] }.joined() }
    @discardableResult
    public mutating func accept(_ event: [String: Any]) -> Bool {
        guard let type = event["type"] as? String,
              type == "conversation.item.input_audio_transcription.delta" ||
              type == "conversation.item.input_audio_transcription.completed" else { return false }
        let id = event["item_id"] as? String ?? "input"
        if !order.contains(id) { order.append(id) }
        if type.hasSuffix(".completed") {
            items[id] = event["transcript"] as? String ?? items[id] ?? ""
            completedItems.insert(id)
        } else if !completedItems.contains(id) {
            if event["text"] != nil || event["stash"] != nil {
                items[id] = (event["text"] as? String ?? "") + (event["stash"] as? String ?? "")
            } else if let delta = event["delta"] as? String { items[id, default: ""] += delta }
        }
        return true
    }
}
