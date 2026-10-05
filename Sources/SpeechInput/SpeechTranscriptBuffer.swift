import Foundation

/// The two readings of one recording. The session's recogniser streams
/// previews and may revise tentative words, so each item's current preview is
/// replaced instead of appended. After the commit the model writes the same
/// audio down under the vocabulary instructions; its reply is the transcript
/// only while it stays a transcript of what the recogniser heard.
public struct SpeechTranscriptBuffer {
    private var order: [String] = []
    private var items: [String: String] = [:]
    private var completedItems: Set<String> = []
    private var reply = "", unheard = false
    /// Whether each reading is complete.
    public private(set) var recognised = false, replied = false
    public init() {}
    /// What the recogniser heard so far.
    public var text: String { order.compactMap { items[$0] }.joined() }
    /// The model's spelling of what was heard. A model invents speech for
    /// silence and may answer the speaker, so silence stays empty and a missing
    /// or outgrown reply falls back to the recogniser. When the recogniser
    /// itself failed, the model's reading is all there is.
    public var transcript: String {
        if unheard { return replied ? reply : "" }
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return heard.isEmpty || !replied || reply.isEmpty || reply.outgrows(heard) ? heard : reply
    }
    /// Returns whether the preview changed.
    @discardableResult
    public mutating func accept(_ event: [String: Any]) -> Bool {
        switch event["type"] as? String {
        case "response.text.delta", "response.output_text.delta": reply += event["delta"] as? String ?? ""
        case "response.text.done", "response.output_text.done": reply = event["text"] as? String ?? reply
        case "response.done":
            if (event["response"] as? [String: Any])?["status"] as? String != "completed" { reply = "" }
            reply = reply.trimmingCharacters(in: .whitespacesAndNewlines); replied = true
        case "conversation.item.input_audio_transcription.failed": recognised = true; unheard = true
        case "conversation.item.input_audio_transcription.delta":
            let id = item(event)
            guard !completedItems.contains(id) else { return true }
            if event["text"] != nil || event["stash"] != nil {
                items[id] = (event["text"] as? String ?? "") + (event["stash"] as? String ?? "")
            } else if let delta = event["delta"] as? String { items[id, default: ""] += delta }
            return true
        case "conversation.item.input_audio_transcription.completed":
            let id = item(event)
            items[id] = event["transcript"] as? String ?? items[id] ?? ""
            completedItems.insert(id); recognised = true
            return true
        default: break
        }
        return false
    }
    private mutating func item(_ event: [String: Any]) -> String {
        let id = event["item_id"] as? String ?? "input"
        if !order.contains(id) { order.append(id) }
        return id
    }
}
