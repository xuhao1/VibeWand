import Foundation
import SpeechInput

struct VoiceHUDSnapshot {
    var enabled = false
    var state: DictationState = .idle
    var style: DictationTextStyle = .verbatim
    var text = ""
    var status = ""
    var showsText: Bool { enabled && (state.active || !text.isEmpty) }
}

/// What the overlay shows for command mode: what was heard, what is being
/// done, and any question that waits for a key.
struct CommandHUDSnapshot: Equatable {
    enum Phase: Equatable { case idle, listening, working, choosing, confirming, done, attention }
    var phase = Phase.idle
    var status = ""
    var text = ""
    var options: [String] = []
    var selection = 0
    /// One small line under the rest: the model acting, how full its context is, the step it is on, how much it asks.
    var detail = ""
    var active: Bool { phase != .idle }
    /// Rows the overlay needs: the text, wrapped to at most three, then one per option.
    var lines: Int { max(1, min(3, (text.count + 21) / 22)) + options.count }
    /// The device answers the coordinator instead of the app in front.
    var capturesControls: Bool { phase == .working || phase == .choosing || phase == .confirming }
}

enum DeviceControl: String, CaseIterable, Codable {
    case dial, left, right, ok, escape, voice, settings, forceEscape
    case l1, l2, leftStickPress, rightStickPress
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case options, create, home, touchpad, mute
    case power, volumeUp, volumeDown

    var isStickDirection: Bool {
        switch self {
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight: return true
        default: return false
        }
    }
}

enum InputPhase: String, Codable {
    case down, up, pulse, cancel
}

struct HUDSnapshot {
    var voice = VoiceHUDSnapshot()
    var command = CommandHUDSnapshot()
    var deviceTemplate: DeviceTemplateID = .vibeKey
    var connectedTemplates: Set<DeviceTemplateID> = []
    /// Name of the chat or model currently highlighted in a picker.
    var selection = ""
    var controlActions: [DeviceControl: String] = [:]
    var scope: GestureScope = .reading
    var controlHints: [DeviceControl: [HUDGestureHint]] = [:]
    var mode = L10n.tr("等待输入", "Waiting for input")
    var action = L10n.tr("按旋钮选会话，转动移动光标", "Press the dial for chats; turn to move the cursor")
    var status = "VibeWand"
    var pressed: Set<DeviceControl> = []
    var rotation = 0
    var demo = false
    var captureOnly = false
    var target = "Codex"
    var connected = false
}

enum InteractionMode: String, Codable {
    case browse, editing, sessions, models, efforts, unavailable

    var title: String {
        switch self {
        case .browse: return L10n.tr("阅读会话", "Reading")
        case .editing: return L10n.tr("编辑文字", "Editing text")
        case .sessions: return L10n.tr("选择会话", "Choose a chat")
        case .models: return L10n.tr("选择模型", "Choose a model")
        case .efforts: return L10n.tr("选择强度", "Choose reasoning effort")
        case .unavailable: return L10n.tr("等待支持的应用", "Waiting for a supported app")
        }
    }
}

struct InteractionContext {
    var targetAvailable: Bool
    var editorFocused: Bool
    var modalOpen: Bool
    var compositionActive: Bool
    var picker: InteractionMode?
    var hasDraftText: Bool? = nil
    var applicationProfile: ApplicationProfile = .codex

    var editingDraft: Bool { editorFocused && hasDraftText != false }

    // A composer that permits cursor movement must also permit deletion.
    // An input method's ability to compose does not prove an active candidate.
    var canEditDraft: Bool {
        targetAvailable && editingDraft && !modalOpen && !compositionActive && picker == nil
    }
}

struct InteractionState {
    var mode: InteractionMode = .browse
}

enum BridgeEffect: Equatable {
    case openSessions, openModels, moveCursor(Int), moveCandidate(Int)
    case confirmCandidate, cancelPicker, deleteBackward, sendReturn, sendEscape
    case scroll(Int), none

    var title: String {
        switch self {
        case .openSessions: return L10n.tr("打开会话选择", "Open chat picker")
        case .openModels: return L10n.tr("打开模型 / 强度", "Open model / effort picker")
        case .moveCursor(let n): return n < 0 ? L10n.tr("光标向左一个字符", "Move cursor one character left") : L10n.tr("光标向右一个字符", "Move cursor one character right")
        case .moveCandidate(let n): return n < 0 ? L10n.tr("上一个候选", "Previous item") : L10n.tr("下一个候选", "Next item")
        case .confirmCandidate: return L10n.tr("确认当前选择", "Confirm selection")
        case .cancelPicker: return L10n.tr("返回 / 取消选择", "Back / cancel selection")
        case .deleteBackward: return L10n.tr("删除光标前字符 / 选区", "Delete previous character / selection")
        case .sendReturn: return "Enter"
        case .sendEscape: return "Escape"
        case .scroll(let n): return n < 0 ? L10n.tr("向上滚动", "Scroll up") : L10n.tr("向下滚动", "Scroll down")
        case .none: return L10n.tr("等待目标 / 保留语音输入", "Waiting for target / keep voice input")
        }
    }
}
