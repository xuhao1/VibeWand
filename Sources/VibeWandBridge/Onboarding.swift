import AppKit
import SwiftUI
import SpeechInput

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

/// The steps of the guide, in the order they are walked. Any of them can be opened from the list at its side.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, access, device, voice, keys, command, done
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .welcome: return tr("欢迎", "Welcome")
        case .access: return tr("权限", "Permissions")
        case .device: return tr("设备", "Your device")
        case .voice: return tr("语音", "Voice")
        case .keys: return tr("按键", "Buttons")
        case .command: return tr("命令模式", "Command mode")
        case .done: return tr("完成", "All set")
        }
    }
    var symbol: String {
        switch self {
        case .welcome: return "wand.and.stars"
        case .access: return "lock.shield"
        case .device: return "gamecontroller"
        case .voice: return "waveform"
        case .keys: return "keyboard"
        case .command: return "sparkles"
        case .done: return "checkmark.seal"
        }
    }
    var tint: Color {
        switch self {
        case .welcome: return .indigo
        case .access: return .orange
        case .device: return .blue
        case .voice: return .pink
        case .keys: return .teal
        case .command: return .purple
        case .done: return .green
        }
    }
}

/// Whether the guide is owed at launch. It is shown once to someone new, never sprung on someone who set
/// VibeWand up before the guide existed, and can always be opened from Settings.
enum Onboarding {
    static let key = "onboardingState"
    /// Settings an earlier launch leaves behind.
    static let earlier = [SpeechPreferences.storageKey, DeviceTemplateStore.storageKey, "gestureConfiguration", "inputMappings", "hudVisible", "hudScale",
                          "commandModeEnabled", "commandEndpoint", L10n.storageKey, "VibeWandBridge.overlayOrigin"]

    /// Read once at launch, before anything else writes a preference. A first launch is remembered as owing the
    /// guide until the guide has been closed.
    static func owed(_ defaults: UserDefaults = .standard) -> Bool {
        switch defaults.string(forKey: key) {
        case "pending": return true
        case "done": return false
        default:
            let fresh = !earlier.contains { defaults.object(forKey: $0) != nil }
            defaults.set(fresh ? "pending" : "done", forKey: key)
            return fresh
        }
    }
    static func close(_ defaults: UserDefaults = .standard) { defaults.set("done", forKey: key) }
    /// For trying the first launch again: the guide opens by itself the next time VibeWand starts.
    static func showAtNextLaunch(_ defaults: UserDefaults = .standard) { defaults.set("pending", forKey: key) }
}

/// Where the guide is and what it has seen on the way.
@MainActor
final class OnboardingModel: ObservableObject {
    let runtime: BridgeRuntime
    @Published private(set) var step = OnboardingStep.welcome
    @Published private(set) var visited: Set<OnboardingStep> = [.welcome]
    /// Controls the user has pressed while the device step was open.
    @Published var tested: Set<DeviceControl> = []
    /// What the device was doing with its input before the device step borrowed it.
    private var captureBefore: Bool?
    var openSettings: ((SettingsSection) -> Void)?
    var close: (() -> Void)?

    init(runtime: BridgeRuntime) { self.runtime = runtime }

    func go(to next: OnboardingStep) {
        guard next != step else { return }
        leave(step)
        step = next; visited.insert(next)
        // While the device is being tried, its buttons light up here and reach no app.
        if next == .device { captureBefore = runtime.captureOnly; runtime.captureOnly = true }
    }
    func advance(_ direction: Int) {
        if let next = OnboardingStep(rawValue: step.rawValue + direction) { go(to: next) } else if direction > 0 { close?() }
    }
    /// Gives back what a step borrowed. Also called when the window closes.
    func leave(_ step: OnboardingStep) {
        if step == .device, let captureBefore { runtime.captureOnly = captureBefore; self.captureBefore = nil }
        if step == .voice { runtime.voiceInput.cancel() }
    }
}

/// The guide's window. It walks someone new through what VibeWand needs before it is useful: permissions, a
/// device that answers, a way to dictate, the buttons, and command mode.
@MainActor
final class OnboardingController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    private let guide: OnboardingModel
    var onClose: (() -> Void)?

    init(runtime: BridgeRuntime, overlay: OverlayController, openSettings: @escaping (SettingsSection) -> Void) {
        model = SettingsModel(runtime: runtime, overlay: overlay)
        guide = OnboardingModel(runtime: runtime)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: OnboardingView.size.width, height: OnboardingView.size.height),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = tr("欢迎使用 VibeWand", "Welcome to VibeWand")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        guide.openSettings = openSettings
        guide.close = { [weak self] in self?.close() }
        let host = NSHostingController(rootView: OnboardingView(model: model, guide: guide))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(OnboardingView.size)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func present(at step: OnboardingStep = .welcome) {
        guide.go(to: step)
        model.refresh(); showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func update(_ snapshot: HUDSnapshot) { model.snapshot = snapshot }
    func windowWillClose(_ notification: Notification) {
        guide.leave(guide.step)
        Onboarding.close()
        onClose?()
    }
}
