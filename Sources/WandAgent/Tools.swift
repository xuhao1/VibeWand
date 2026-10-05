import Foundation

/// One tool the coordinator model may call. The catalog is the whole of what
/// VibeWand lets a model do: there is no shell, file access or coordinate click behind it.
public struct ToolDefinition: Equatable, Sendable {
    public enum Effect: Sendable {
        /// Reads state or talks to the user through the overlay.
        case read
        /// Changes what is in front or presses a control the user can see.
        case navigate
        /// Puts text into a field and leaves it there.
        case write
        /// Starts downstream work or sends content to another service.
        case submit
    }
    public let name: String
    public let summary: String
    public let schema: JSONValue
    public let effect: Effect

    var wire: JSONValue { ["name": .string(name), "description": .string(summary), "inputSchema": schema] }
}

public struct ToolOutcome: Equatable, Sendable {
    public var text: String
    public var isError: Bool
    /// false when an action was carried out but its result could not be read back.
    public var verified: Bool
    /// A JPEG picture that goes to the model beside the text.
    public var image: Data?
    public init(text: String, isError: Bool = false, verified: Bool = true, image: Data? = nil) {
        self.text = text; self.isError = isError; self.verified = verified; self.image = image
    }
    public static func ok(_ value: JSONValue, verified: Bool = true) -> ToolOutcome {
        ToolOutcome(text: value.string ?? value.text, verified: verified)
    }
    public static func failure(_ message: String) -> ToolOutcome { ToolOutcome(text: message, isError: true) }
}

public enum ToolCatalog {
    public static let all: [ToolDefinition] = navigation + interface
    /// What a session mounts: the catalog, with the window's picture when the user lets the model see.
    public static func mounted(sight: Bool) -> [ToolDefinition] { sight ? all + [screenshot] : all }

    /// Finding and opening apps and chats, and talking to the user.
    public static let navigation: [ToolDefinition] = [
        tool("list_targets", .read, """
            List the apps VibeWand can operate. For each: its id, whether it is running and frontmost, and how chats \
            are found in it: "list" (find_sessions, then search_in_app when that has no match), "search" (search_in_app) \
            or neither (interface tools only). Also names the app and window the user was in when they spoke. Any \
            other app on this Mac, running or not, is not listed: open it by its name with activate_app.
            """),
        tool("find_sessions", .read, """
            Search the chats of an app whose sessions are "list". Returns id, title, project folder and last-updated \
            time, newest first. Only ids returned here may be opened.
            """, [
                "app": string("App id from list_targets."),
                "query": string("Keywords from the title or project. Omit for the most recent chats."),
                "limit": ["type": "integer", "minimum": 1, "maximum": 20]
            ], required: ["app"]),
        tool("open_session", .navigate, "Open one chat by an id from find_sessions and bring its app to the front.", [
            "app": string("App id from list_targets."), "id": string("Chat id from find_sessions.")
        ], required: ["app", "id"]),
        tool("search_in_app", .navigate, """
            Bring an app to the front, open its own chat search and type the query. The user then picks a result \
            with the dial, so call finish right after. This is the route for an app whose sessions are "search", and \
            for a "list" app when find_sessions has no match; do not rebuild it from the ui_ tools.
            """, ["app": string("App id from list_targets."), "query": string("Keywords to type into the search.")],
             required: ["app", "query"]),
        tool("activate_app", .navigate, """
            Bring an app to the front, by id from list_targets or by its name. Optionally open a file path or URL in it.
            """, ["app": string("App id or application name."), "open": string("Absolute file path or URL to open.")],
             required: ["app"]),
        tool("choose", .read, """
            Ask the user to pick one of up to six options on the overlay with the dial. Use it when several candidates \
            fit and the difference matters; never guess. Returns the chosen id, or "cancelled".
            """, [
                "question": string("One short line, in the user's language."),
                "options": ["type": "array", "minItems": 2, "maxItems": 6, "items": [
                    "type": "object", "required": ["id", "label"], "properties": [
                        "id": string("Returned when chosen."), "label": string("What the user reads."),
                        "detail": string("Project, time or another short hint.")]]]
            ], required: ["question", "options"]),
        tool("finish", .read, "End the task. Tell the user what happened in one short line, in their language.",
             ["summary": string("One short line.")], required: ["summary"]),
        tool("need_user", .read, """
            Stop and hand back to the user when the task cannot be completed or something is missing. Say what is \
            needed in one short line, in their language.
            """, ["reason": string("One short line.")], required: ["reason"])
    ]

    /// Operating the window in front through its accessibility tree. No screenshots, no coordinates.
    public static let interface: [ToolDefinition] = [
        tool("ui_snapshot", .read, """
            List the controls in the front window of the app being operated: id, role, label and state. What is new or \
            changed since the snapshot before comes first, so after a press that opens a menu or a popover its entries \
            lead the list. A status line is what the app announces, such as the level a control stands at; it cannot \
            be pressed. Pass filter to keep only controls whose label or state contains it; do that for busy windows: \
            "model" finds an assistant app's model picker, which VibeWand marks as such whatever its label. Ids are \
            valid until the next snapshot.
            """, ["filter": string("Part of a label or state, case-insensitive.")]),
        tool("ui_press", .navigate, "Press a control by an id from the latest ui_snapshot.",
             ["id": string("Control id, such as e12.")], required: ["id"]),
        tool("ui_key", .navigate, """
            Send one keyboard shortcut to the app being operated, for example "cmd+p", "ctrl+tab", "escape", "down" \
            or "return". Pass id to send it to one control, which takes keyboard focus first: that is how a slider, \
            or a control a snapshot lists with keys, is set, one step for each call. The answer carries what the app \
            announced in reply, when it announced anything: read it before the next step.
            """, ["keys": string("Modifiers and one key joined by +."), "id": string("Control id from the latest ui_snapshot.")],
                 required: ["keys"]),
        tool("ui_menu", .navigate, """
            Choose a menu bar item of the app being operated by its path of titles, for example \
            ["File", "Open Recent", "notes.md"].
            """, ["path": ["type": "array", "minItems": 1, "items": ["type": "string"]]], required: ["path"]),
        tool("ui_type", .write, """
            Type text into a control by id, or into the focused one when id is omitted. The text stays in the field: \
            Return is not pressed.
            """, ["text": string("Text to type."), "id": string("Control id from the latest ui_snapshot.")],
             required: ["text"])
    ]

    /// Mounted only when the user has turned on letting the model see: a picture of the window leaves this Mac.
    public static let screenshot = tool("ui_screenshot", .read, """
        See the front window of the app being operated as a picture, with the ids of the latest ui_snapshot marked \
        on its controls. Use it to read what the window shows, to tell look-alike controls apart, or to check a \
        result that only shows visually. It needs a model that takes pictures.
        """)

    private static func tool(_ name: String, _ effect: ToolDefinition.Effect, _ summary: String,
                             _ properties: [String: JSONValue] = [:], required: [String] = []) -> ToolDefinition {
        ToolDefinition(name: name, summary: summary, schema: [
            "type": "object", "properties": .object(properties), "required": .array(required.map(JSONValue.string))
        ], effect: effect)
    }
    private static func string(_ description: String) -> JSONValue { ["type": "string", "description": .string(description)] }
}

/// Labels that mean pressing the control destroys something, sends it away, or hands out access.
/// These always wait for the user, whatever the model intended.
public enum ControlRisk {
    private static let words = [
        "delete", "remove", "discard", "don't save", "dont save", "erase", "trash", "uninstall", "reset", "revert",
        "overwrite", "format", "sign out", "log out", "send", "submit", "post", "publish", "pay", "buy", "purchase",
        "allow", "grant", "authorize", "authorise", "approve", "full access",
        "删除", "移除", "丢弃", "放弃", "不保存", "不存储", "清空", "抹掉", "卸载", "还原", "重置", "覆盖", "格式化",
        "退出登录", "注销", "发送", "提交", "发布", "支付", "购买", "付款", "允许", "授权", "批准", "同意", "完全访问"
    ]
    public static func needsConfirmation(_ label: String) -> Bool {
        let text = label.lowercased()
        return words.contains { text.contains($0) }
    }
}
