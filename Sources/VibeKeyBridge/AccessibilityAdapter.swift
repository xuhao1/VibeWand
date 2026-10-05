import AppKit
import ApplicationServices
import Carbon

struct TargetIdentity: Equatable {
    var pid: pid_t
    var windowHash: CFHashCode
    var windowTitle: String
    var focusedHash: CFHashCode
    var focusedIdentifier: String
}

struct AccessibleCandidate {
    var element: AXUIElement
    var frame: CGRect
    var selected: Bool
    /// Shown in the HUD while choosing; never logged or exported.
    var title = ""
}

struct TargetObservation {
    var pid: pid_t?
    var identity: TargetIdentity?
    var sampledAt: Date?
    var context = InteractionContext(targetAvailable: false, editorFocused: false, modalOpen: false, compositionActive: false, picker: nil)
    var status = L10n.tr("请将支持的应用切到前台", "Bring a supported app to the foreground")
    var window: AXUIElement?
    var focused: AXUIElement?
    var editor: AXUIElement?
    var menuHashes: Set<CFHashCode> = []
    var nativeMenu = false
    var pickerFrame: CGRect?
    var scrollPoint: CGPoint?
    var pickerRoot: CFHashCode?
    var candidates: [AccessibleCandidate] = []
    var adjustmentControl: AXUIElement?
    var adjustmentPoint: CGPoint?
    /// An effort control without a slider role: it takes focus and arrow keys.
    var adjustmentItem: AXUIElement?
    /// The row inside a combined effort popover that opens the model list.
    var modelEntry: AXUIElement?
    var customProfile: CustomApplicationProfile?
    /// Dictation never writes into a password field.
    var secureField = false
    /// The picker is VibeWand's own walk over a sidebar list: the app has no
    /// popup open, so confirming and cancelling must not send any key.
    var sidebarPicker = false

    func shortcut(for effect: BridgeEffect, fallback: KeyStroke? = nil) -> KeyStroke? {
        // Confirming an IME candidate or dismissing an unknown dialog must not
        // become a user-configured send/search chord.
        if context.compositionActive || (context.modalOpen && context.picker == nil) {
            if effect == .sendReturn { return KeyStroke(code: 36) }
            if effect == .sendEscape { return KeyStroke(code: 53) }
        }
        guard let customProfile else { return fallback }
        return customProfile.shortcut(for: effect)?.stroke
    }
}

private struct PendingPicker {
    var mode: InteractionMode
    var pid: pid_t
    var requestedAt: Date
    var originFocus: CFHashCode?
    var originWindow: CFHashCode? = nil
    var originMenus: Set<CFHashCode> = []

    var expired: Bool { Date().timeIntervalSince(requestedAt) > 1.2 }
}

/// A terminal draws its pickers as text, so there is nothing to observe. Once
/// a picker command has been typed, the picker is taken to be open in that
/// terminal session until it is confirmed, cancelled or left alone.
private struct TypedPicker {
    var pid: pid_t
    var focus: CFHashCode
    var mode: InteractionMode
    var expires: Date
}

private struct PickerBinding {
    var mode: InteractionMode
    var pid: pid_t
    var elementHash: CFHashCode
    var nativeMenu = false
}

private struct AXSampleRequest {
    var pid: pid_t
    var profile: ApplicationProfile
    var forceEditing: Bool
    var compatibilityPicker: Bool
    var pending: PendingPicker?
    var binding: PickerBinding?
    var inputSourceCanCompose: Bool
    var customProfile: CustomApplicationProfile?
    /// First sample of this process: ask an Electron app to publish its web
    /// content to accessibility clients. Other apps ignore the attribute.
    var enableWebAccessibility = false
    var typedPicker: TypedPicker?
    var sessionList: AXUIElement?
}

private struct AXSampleResult {
    var observation: TargetObservation
    var binding: PickerBinding?
}

@MainActor
final class AccessibilityAdapter {
    nonisolated static let syntheticMarker: Int64 = 0x564942454B4559
    private let worker = DispatchQueue(label: "vibekey.accessibility", qos: .userInteractive)
    private var cached = TargetObservation()
    private var pendingPicker: PendingPicker?
    private var boundPicker: PickerBinding?
    private var candidateNavigation = CandidateNavigation()
    private var originalPointer: CGPoint?
    private var generation = 0
    private var refreshInFlight = false
    private var preparedProcesses: Set<pid_t> = []
    private struct SidebarPicker { var pid: pid_t; var list: AXUIElement; var touched: Date }
    private var sidebarPicker: SidebarPicker?
    private var typedPicker: TypedPicker?
    /// Title of the highlighted candidate, for the HUD only.
    private(set) var selectionTitle = ""
    private var completions: [(TargetObservation) -> Void] = []
    // This widens search-field recognition only; it never invents an open menu.
    var compatibilityPicker = false { didSet { if oldValue != compatibilityPicker { reset() } } }
    var forceEditing = false { didSet { if oldValue != forceEditing { reset() } } }
    var sessionShortcut = KeyStroke(code: 40, flags: .maskCommand)
    private let preferences: UserDefaults
    private var disabledProfiles: Set<String>
    private let customStore: CustomApplicationProfileStore

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        disabledProfiles = Set(preferences.stringArray(forKey: "disabledApplicationProfiles") ?? [])
        customStore = CustomApplicationProfileStore(preferences: preferences)
    }

    var customProfiles: [CustomApplicationProfile] { customStore.profiles }

    func saveCustomProfile(_ profile: CustomApplicationProfile) throws {
        try customStore.save(profile)
        reset()
    }

    func removeCustomProfile(id: UUID) { customStore.remove(id: id); reset() }

    func setCustomProfileEnabled(_ enabled: Bool, id: UUID) {
        customStore.setEnabled(enabled, id: id)
        reset()
    }

    func resolvedProfile(bundleID: String?) -> ApplicationProfile {
        customStore.profile(bundleID: bundleID)?.template.profile ?? ApplicationProfile.resolve(bundleID: bundleID)
    }

    func isApplicationEnabled(bundleID: String?) -> Bool {
        if let custom = customStore.profile(bundleID: bundleID) { return custom.enabled }
        return isEnabled(ApplicationProfile.resolve(bundleID: bundleID))
    }

    var targetDisplayName: String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return L10n.tr("等待应用", "Waiting for an app") }
        if let custom = customStore.profile(bundleID: app.bundleIdentifier) { return custom.name }
        let profile = resolvedProfile(bundleID: app.bundleIdentifier)
        return profile == .browser || profile == .terminal ? (app.localizedName ?? profile.title) : profile.title
    }

    func isEnabled(_ profile: ApplicationProfile) -> Bool {
        profile != .generic && !profile.isCustom && !disabledProfiles.contains(profile.rawValue)
    }

    func setEnabled(_ enabled: Bool, for profile: ApplicationProfile) {
        guard profile != .generic, !profile.isCustom else { return }
        if enabled { disabledProfiles.remove(profile.rawValue) } else { disabledProfiles.insert(profile.rawValue) }
        preferences.set(disabledProfiles.sorted(), forKey: "disabledApplicationProfiles")
        reset()
    }

    private func accepts(_ app: NSRunningApplication) -> Bool {
        isApplicationEnabled(bundleID: app.bundleIdentifier)
    }

    var trusted: Bool { AXIsProcessTrusted() }

    func reset() {
        generation += 1
        pendingPicker = nil
        boundPicker = nil
        sidebarPicker = nil
        typedPicker = nil
        selectionTitle = ""
        cached = TargetObservation()
        restorePointer()
    }

    private func restorePointer() {
        candidateNavigation.reset()
        if let point = originalPointer { SystemPointer.move(to: point); originalPointer = nil }
    }

    /// No AX calls here. Key events and drawing can read this without blocking.
    func observe() -> TargetObservation {
        guard let app = NSWorkspace.shared.frontmostApplication,
              accepts(app) else {
            if cached.pid != nil || pendingPicker != nil || boundPicker != nil { reset() }
            return TargetObservation()
        }
        guard trusted else {
            var waiting = TargetObservation(pid: app.processIdentifier)
            waiting.status = L10n.tr("需要辅助功能权限", "Accessibility permission required")
            return waiting
        }
        guard cached.pid == app.processIdentifier, let sampledAt = cached.sampledAt,
              (0...0.7).contains(Date().timeIntervalSince(sampledAt)) else {
            var waiting = TargetObservation(pid: app.processIdentifier)
            waiting.status = L10n.tr("等待当前界面状态", "Waiting for interface state")
            return waiting
        }
        return cached
    }

    /// Samples the current target on a serial worker. Callers that plan a delayed
    /// click/delete must compare the returned identity to their key-down owner.
    func requestRefresh(completion: @escaping (TargetObservation) -> Void) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              accepts(app), trusted else {
            completion(observe())
            return
        }
        if cached.pid != nil && cached.pid != app.processIdentifier { reset() }
        if pendingPicker?.expired == true { pendingPicker = nil }
        completions.append(completion)
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let token = generation
        var request = AXSampleRequest(
            pid: app.processIdentifier,
            profile: resolvedProfile(bundleID: app.bundleIdentifier),
            forceEditing: forceEditing,
            compatibilityPicker: compatibilityPicker,
            pending: pendingPicker,
            binding: boundPicker,
            inputSourceCanCompose: Self.currentInputSourceCanCompose(),
            customProfile: customStore.profile(bundleID: app.bundleIdentifier),
            enableWebAccessibility: preparedProcesses.insert(app.processIdentifier).inserted
        )
        if let sidebar = sidebarPicker {
            // An untouched sidebar walk ends by itself, like the app switcher.
            if sidebar.pid == app.processIdentifier, Date().timeIntervalSince(sidebar.touched) < 20 { request.sessionList = sidebar.list }
            else { sidebarPicker = nil; selectionTitle = ""; restorePointer() }
        }
        if let typed = typedPicker {
            if typed.pid == app.processIdentifier, Date() < typed.expires { request.typedPicker = typed } else { typedPicker = nil }
        }
        worker.async { [weak self] in
            let result = AXSampler.sample(request)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshInFlight = false
                    // An Electron app that was still starting, or that dropped its web
                    // tree later, exposes no focus: ask it again on the next sample.
                    if result.observation.focused == nil { self.preparedProcesses.remove(request.pid) }
                    if token == self.generation, NSWorkspace.shared.frontmostApplication?.processIdentifier == request.pid {
                        if self.candidateNavigation.root != nil && self.candidateNavigation.root != result.observation.pickerRoot { self.restorePointer() }
                        self.cached = result.observation
                        self.boundPicker = result.binding
                        // Another tab or pane took focus: the list belonged to the one before.
                        if request.typedPicker != nil, result.observation.context.picker == nil { self.typedPicker = nil }
                        // An observed menu owns its binding; the shortcut request
                        // cannot be reused to classify a later unrelated modal.
                        if result.binding != nil || self.pendingPicker?.expired == true { self.pendingPicker = nil }
                        if self.pendingPicker != nil && result.observation.context.picker == nil {
                            self.cached.status = L10n.tr("等待选择器；未确认界面状态", "Waiting for the picker to become available")
                        }
                    }
                    let observation = self.observe()
                    let callbacks = self.completions
                    self.completions.removeAll()
                    callbacks.forEach { $0(observation) }
                }
            }
        }
    }

    @discardableResult
    func perform(_ effect: BridgeEffect, observation: TargetObservation) -> String {
        guard effect != .none else { return observation.status }
        guard trusted else { return L10n.tr("请先开启辅助功能权限", "Enable Accessibility permission first") }
        // `observe()` only ever returns a sample of the accepted frontmost app.
        let current = observe()
        guard let pid = observation.pid, let identity = observation.identity,
              identity == current.identity, current.context.targetAvailable else {
            return L10n.tr("目标 / 焦点状态已变化，操作已取消", "Target or focus changed; action canceled")
        }
        switch effect {
        case .openSessions:
            guard !observation.context.compositionActive, !observation.context.modalOpen else { return L10n.tr("输入法或弹窗正在处理输入，操作已暂停", "Input method or dialog is active; action paused") }
            let profile = observation.context.applicationProfile
            if profile.picksSessionsFromSidebar, observation.customProfile == nil {
                openSidebarSessions(pid: pid)
                return profile.title(for: effect)
            }
            if let command = profile.typedCommand(for: effect), observation.customProfile == nil {
                typeCommand(command, mode: .sessions, identity: identity)
                return profile.title(for: effect)
            }
            if profile.opensSessionsWithButton, observation.customProfile == nil {
                pressLabelledControl(pid: pid, mode: .sessions, identity: identity, menus: observation.menuHashes,
                    fallback: profile.primaryShortcut, ancestorClasses: profile.sessionTriggerAncestorClasses) {
                    profile.isSessionTrigger(role: $0, hint: $1)
                }
                return profile.title(for: effect)
            }
            guard let shortcut = observation.shortcut(for: effect, fallback: profile == .codex ? sessionShortcut : profile.primaryShortcut) else { return L10n.tr("当前应用未配置主操作", "No primary action configured for this app") }
            generation += 1
            pendingPicker = profile.expectsSessionPicker ? PendingPicker(mode: .sessions, pid: pid, requestedAt: Date(), originFocus: identity.focusedHash) : nil
            boundPicker = nil
            post(shortcut, pid: pid)
            return profile.title(for: effect)
        case .openModels:
            if observation.context.picker == .efforts, let entry = observation.modelEntry {
                // Already inside the combined popover: step into its model list.
                AXUIElementSetMessagingTimeout(entry, 0.05)
                guard AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success else { return L10n.tr("模型列表暂不可用", "Model list unavailable") }
                var known = observation.menuHashes
                if let root = observation.pickerRoot { known.insert(root) }
                generation += 1
                pendingPicker = PendingPicker(mode: .models, pid: pid, requestedAt: Date(), originFocus: identity.focusedHash,
                    originWindow: identity.windowHash, originMenus: known)
                boundPicker = nil; cached.sampledAt = nil
                return L10n.tr("选择模型", "Choose a model")
            }
            guard !observation.context.compositionActive, !observation.context.modalOpen else { return L10n.tr("输入法或弹窗正在处理输入，操作已暂停", "Input method or dialog is active; action paused") }
            let profile = observation.context.applicationProfile
            if let command = profile.typedCommand(for: effect), observation.customProfile == nil {
                typeCommand(command, mode: .models, identity: identity)
                return profile.title(for: effect)
            }
            if profile.opensModelsWithButton, observation.customProfile == nil {
                // Codex also has a shortcut in some versions; it is the fallback when no button is found.
                pressLabelledControl(pid: pid, mode: .models, identity: identity, menus: observation.menuHashes,
                                     fallback: profile.secondaryShortcut, roles: profile.modelTriggerRoles) { profile.isModelTrigger(role: $0, hint: $1) }
                return profile.title(for: effect)
            }
            guard let shortcut = observation.shortcut(for: effect, fallback: profile.secondaryShortcut) else { return L10n.tr("当前应用未配置辅助操作", "No secondary action configured for this app") }
            post(shortcut, pid: pid)
            generation += 1
            pendingPicker = profile.expectsSessionPicker ? PendingPicker(mode: profile.isMessaging ? .sessions : .models, pid: pid, requestedAt: Date(), originFocus: identity.focusedHash,
                originWindow: identity.windowHash, originMenus: observation.menuHashes) : nil
            boundPicker = nil
            return profile.title(for: effect)
        case .moveCursor(let direction):
            guard observation.context.canEditDraft else { return L10n.tr("输入框状态已改变", "Editor state changed") }
            guard let shortcut = observation.shortcut(for: effect, fallback: KeyStroke(code: direction < 0 ? 123 : 124)) else { return unassignedAction }
            post(shortcut, pid: pid)
        case .deleteBackward:
            // A terminal's prompt cannot be read; Backspace is harmless on an empty one.
            guard observation.context.canEditDraft || observation.context.applicationProfile == .terminal else { return L10n.tr("当前界面保留原生 Escape", "Native Escape is preserved on this screen") }
            guard let shortcut = observation.shortcut(for: effect, fallback: KeyStroke(code: 51)) else { return unassignedAction }
            post(shortcut, pid: pid)
        case .moveCandidate(let direction):
            guard observation.context.picker != nil, !observation.context.compositionActive else { return L10n.tr("选择器状态已改变", "Picker state changed") }
            if observation.context.picker == .efforts, let slider = observation.adjustmentControl {
                AXUIElementSetMessagingTimeout(slider, 0.01)
                _ = AXUIElementSetAttributeValue(slider, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                let action = direction < 0 ? kAXDecrementAction : kAXIncrementAction
                if AXUIElementPerformAction(slider, action as CFString) != .success {
                    if let point = observation.adjustmentPoint { SystemPointer.click(at: point) }
                    post(KeyStroke(code: direction < 0 ? 123 : 124), pid: pid, systemMenu: true)
                }
                return direction < 0 ? L10n.tr("降低推理强度", "Decrease reasoning effort") : L10n.tr("提高推理强度", "Increase reasoning effort")
            }
            if observation.context.picker == .efforts, let item = observation.adjustmentItem {
                AXUIElementSetMessagingTimeout(item, 0.02)
                _ = AXUIElementSetAttributeValue(item, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                post(KeyStroke(code: direction < 0 ? 123 : 124), pid: pid, systemMenu: true)
                return direction < 0 ? L10n.tr("降低推理强度", "Decrease reasoning effort") : L10n.tr("提高推理强度", "Increase reasoning effort")
            }
            if (observation.context.picker == .models || observation.context.picker == .efforts || observation.sidebarPicker),
               let root = observation.pickerRoot, !observation.candidates.isEmpty,
               let index = candidateNavigation.move(root: root, count: observation.candidates.count,
                   selected: observation.candidates.firstIndex(where: \.selected), direction: direction) {
                if originalPointer == nil { originalPointer = CGEvent(source: nil)?.location }
                let candidate = observation.candidates[index]
                AXUIElementSetMessagingTimeout(candidate.element, 0.02)
                if observation.sidebarPicker { sidebarPicker?.touched = Date() }
                else { _ = AXUIElementSetAttributeValue(candidate.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
                // Long lists scroll; bring the row into view and hover where it now is.
                _ = AXUIElementPerformAction(candidate.element, "AXScrollToVisible" as CFString)
                let frame = Self.currentFrame(of: candidate.element) ?? candidate.frame
                SystemPointer.move(to: CGPoint(x: frame.midX, y: frame.midY))
                selectionTitle = candidate.title
                return L10n.tr("候选 \(index + 1) / \(observation.candidates.count)", "Item \(index + 1) / \(observation.candidates.count)")
            }
            guard !observation.sidebarPicker else { return L10n.tr("没有可选的会话", "No chats to choose from") }
            guard let shortcut = observation.shortcut(for: effect, fallback: KeyStroke(code: direction < 0 ? 126 : 125)) else { return unassignedAction }
            post(shortcut, pid: pid, systemMenu: observation.customProfile == nil || observation.nativeMenu)
            typedPicker?.expires = Date() + 20
        case .confirmCandidate:
            guard observation.context.picker != nil, !observation.context.compositionActive else { return L10n.tr("未确认选择器，操作已取消", "Picker not confirmed; action canceled") }
            if candidateNavigation.root == observation.pickerRoot, let index = candidateNavigation.index,
               observation.candidates.indices.contains(index) {
                let candidate = observation.candidates[index]
                AXUIElementSetMessagingTimeout(candidate.element, 0.01)
                if AXUIElementPerformAction(candidate.element, kAXPressAction as CFString) != .success {
                    SystemPointer.click(at: CGPoint(x: candidate.frame.midX, y: candidate.frame.midY))
                }
            } else if observation.sidebarPicker {
                // Nothing was highlighted: leave the list without touching the draft.
            } else if observation.context.picker == .efforts && (observation.adjustmentControl != nil || observation.adjustmentItem != nil) {
                post(KeyStroke(code: 53), pid: pid, systemMenu: true)
            } else {
                guard let shortcut = observation.shortcut(for: effect, fallback: KeyStroke(code: 36)) else { return unassignedAction }
                post(shortcut, pid: pid, systemMenu: observation.customProfile == nil || observation.nativeMenu)
            }
            restorePointer()
            generation += 1
            pendingPicker = nil; boundPicker = nil
            sidebarPicker = nil; selectionTitle = ""
            cached.sampledAt = nil
            // A typed model list may be followed by another (Codex asks for the effort next).
            if typedPicker?.mode == .sessions { typedPicker = nil } else { typedPicker?.expires = Date() + 4 }
            let profile = observation.context.applicationProfile
            // Choosing a row may open a nested menu (model → variants); keep following it.
            if let mode = observation.context.picker, mode != .sessions, profile.supportsAssistantPickers, !observation.sidebarPicker {
                var known = observation.menuHashes
                if let root = observation.pickerRoot { known.insert(root) }
                pendingPicker = PendingPicker(mode: mode, pid: pid, requestedAt: Date(), originFocus: identity.focusedHash,
                    originWindow: identity.windowHash, originMenus: known)
            }
            if profile == .claude, observation.context.picker == .models {
                // Claude keeps effort in its own menu; continue there like the combined pickers do.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                        self.pressLabelledControl(pid: pid, mode: .efforts, identity: identity, menus: []) { profile.isEffortTrigger(role: $0, hint: $1) }
                    }
                }
            }
        case .cancelPicker, .sendEscape:
            if observation.sidebarPicker {
                restorePointer(); generation += 1
                sidebarPicker = nil; selectionTitle = ""; cached.sampledAt = nil
                return effect.title
            }
            selectionTitle = ""
            guard let shortcut = observation.shortcut(for: effect, fallback: KeyStroke(code: 53)) else { return unassignedAction }
            post(shortcut, pid: pid, systemMenu: observation.context.picker != nil && (observation.customProfile == nil || observation.nativeMenu))
            restorePointer()
            generation += 1
            pendingPicker = nil; boundPicker = nil; typedPicker = nil
            cached.sampledAt = nil
        case .sendReturn:
            guard let shortcut = observation.shortcut(for: effect, fallback: KeyStroke(code: 36)) else { return unassignedAction }
            post(shortcut, pid: pid)
        case .scroll(let direction):
            guard !observation.context.compositionActive,
                  !observation.context.modalOpen || observation.context.picker != nil else { return L10n.tr("弹窗未识别，滚屏暂停", "Unrecognized dialog; scrolling paused") }
            if let shortcut = observation.customProfile?.shortcut(for: effect)?.stroke {
                post(shortcut, pid: pid)
                return effect.title
            }
            let point = observation.scrollPoint ?? Self.frontWindowScrollPoint(pid: pid)
            guard let point else { return L10n.tr("未定位滚动区域，操作已暂停", "Scroll area not found; action paused") }
            SystemPointer.scroll(delta: Int32(direction < 0 ? 80 : -80), at: point)
        case .none: break
        }
        return effect.title
    }

    /// Empties the prompt line, pastes the command and presses Return. Pasting
    /// keeps an active input method from swallowing the letters.
    private func typeCommand(_ command: String, mode: InteractionMode, identity: TargetIdentity) {
        let pid = identity.pid
        post(KeyStroke(code: 32, flags: .maskControl), pid: pid, systemMenu: true) // Ctrl+U
        let delivery = ClipboardTextDelivery()
        delivery.post(command, pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                delivery.restore(confirmed: true)
                guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.post(KeyStroke(code: 36), pid: pid, systemMenu: true)
            }
        }
        generation += 1
        typedPicker = TypedPicker(pid: pid, focus: identity.focusedHash, mode: mode, expires: Date() + 20)
        cached.sampledAt = nil
    }

    private func openSidebarSessions(pid: pid_t) {
        worker.async { [weak self] in
            let list = LabelledControlFinder.find(pid: pid, budget: 2, roles: ["AXOutline", "AXList", "AXTable"], descend: false) {
                ApplicationProfile.isSessionList(role: $0, hint: $1)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    guard let list else {
                        self.onStatus?(L10n.tr("未找到会话列表；请展开侧边栏后重试", "Chat list not found; show the sidebar and retry")); return
                    }
                    self.generation += 1
                    self.sidebarPicker = SidebarPicker(pid: pid, list: list, touched: Date())
                    self.cached.sampledAt = nil
                    self.onStatus?(L10n.tr("选择会话", "Choose a chat"))
                }
            }
        }
    }

    /// Reports the outcome of an asynchronous press, e.g. a model button that was not found.
    var onStatus: ((String) -> Void)?

    /// Finds a labelled control near the composer and presses it. The search
    /// has its own time budget on the worker, so ordinary sampling stays cheap.
    private func pressLabelledControl(pid: pid_t, mode: InteractionMode, identity: TargetIdentity, menus: Set<CFHashCode>,
                                      fallback: KeyStroke? = nil, ancestorClasses: Set<String> = [],
                                      roles: Set<String> = ["AXButton", "AXPopUpButton", "AXMenuButton"],
                                      matches: @escaping @Sendable (String, String) -> Bool) {
        worker.async { [weak self] in
            let control = LabelledControlFinder.find(pid: pid, roles: roles, ancestorClasses: ancestorClasses, matches: matches)
            guard LabelledControlFinder.stillOwnsFocus(identity) else {
                DispatchQueue.main.async { [weak self] in
                    self?.onStatus?(L10n.tr("目标 / 焦点状态已变化，操作已取消", "Target or focus changed; action canceled"))
                }
                return
            }
            let pressed = control.map { AXUIElementPerformAction($0, kAXPressAction as CFString) == .success } ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    if !pressed, let fallback { self.post(fallback, pid: pid) }
                    guard pressed || fallback != nil else {
                        self.onStatus?(mode == .efforts ? L10n.tr("未找到强度按钮", "Effort button not found")
                            : L10n.tr("未找到模型按钮；请回到主会话后重试", "Model button not found; return to the main chat and retry"))
                        return
                    }
                    self.generation += 1
                    self.pendingPicker = PendingPicker(mode: mode, pid: pid, requestedAt: Date(), originFocus: identity.focusedHash,
                        originWindow: identity.windowHash, originMenus: menus)
                    self.boundPicker = nil
                    self.cached.sampledAt = nil
                    self.onStatus?(mode == .sessions ? L10n.tr("选择会话", "Choose a chat") :
                        mode == .efforts ? L10n.tr("选择推理强度", "Choose reasoning effort") : L10n.tr("选择模型", "Choose a model"))
                }
            }
        }
    }

    private var unassignedAction: String { L10n.tr("此应用动作未分配快捷键", "No shortcut assigned for this app action") }

    private func post(_ stroke: KeyStroke, pid: pid_t, systemMenu: Bool = false) {
        let source = CGEventSource(stateID: systemMenu ? .privateState : .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.code, keyDown: down) else { continue }
            event.flags = stroke.flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            if systemMenu { event.post(tap: .cghidEventTap) } else { event.postToPid(pid) }
        }
    }

    private static func currentFrame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private static func frontWindowScrollPoint(pid: pid_t) -> CGPoint? {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows where (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
            if let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 200, frame.height > 200 {
                return ScrollTarget.point(window: frame, composer: nil, scrollArea: nil, popup: nil)
            }
        }
        return nil
    }

    private static func currentInputSourceCanCompose() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return true }
        let type = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
        return type != (kTISTypeKeyboardLayout as String)
    }
}

/// Locates one labelled button or menu button. It starts at the focused
/// element's ancestors (the composer footer is usually a few levels away) and
/// then walks the window, later siblings first. Message text is never read.
enum LabelledControlFinder {
    /// Button lookup can take longer than an ordinary sample. Recheck the
    /// original app, window and focus before pressing or falling back to keys.
    static func stillOwnsFocus(_ identity: TargetIdentity) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid else { return false }
        let application = AXUIElementCreateApplication(identity.pid)
        AXUIElementSetMessagingTimeout(application, 0.02)
        func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
        }
        guard let window = attribute(application, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID(),
              let focused = attribute(application, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let windowElement = window as! AXUIElement, focusedElement = focused as! AXUIElement
        return CFHash(window) == identity.windowHash && CFHash(focused) == identity.focusedHash &&
            (attribute(windowElement, kAXTitleAttribute) as? String ?? "") == identity.windowTitle &&
            (attribute(focusedElement, kAXIdentifierAttribute) as? String ?? "") == identity.focusedIdentifier
    }

    static func find(pid: pid_t, budget: TimeInterval = 1.2, roles: Set<String> = ["AXButton", "AXPopUpButton", "AXMenuButton"],
                     descend: Bool = true, ancestorClasses: Set<String> = [], matches: (String, String) -> Bool) -> AXUIElement? {
        let stop = ProcessInfo.processInfo.systemUptime + budget
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func text(_ node: AXUIElement, _ name: String) -> String { attribute(node, name) as? String ?? "" }
        func inRequiredContainer(_ node: AXUIElement) -> Bool {
            guard !ancestorClasses.isEmpty else { return true }
            var parent = element(attribute(node, kAXParentAttribute))
            for _ in 0..<6 {
                guard let current = parent, ProcessInfo.processInfo.systemUptime < stop else { return false }
                let classes = attribute(current, "AXDOMClassList") as? [String] ?? []
                if !ancestorClasses.isDisjoint(with: classes) { return true }
                if ["AXWindow", "AXApplication"].contains(text(current, kAXRoleAttribute)) { return false }
                parent = element(attribute(current, kAXParentAttribute))
            }
            return false
        }
        var roots: [AXUIElement] = []
        var node = element(attribute(application, kAXFocusedUIElementAttribute))
        while let current = node { roots.append(current); node = element(attribute(current, kAXParentAttribute)) }
        if let window = element(attribute(application, kAXFocusedWindowAttribute)) { roots.append(window) }
        var seen: Set<CFHashCode> = []
        for root in roots {
            var stack = [root]
            while let current = stack.popLast() {
                guard ProcessInfo.processInfo.systemUptime < stop else { return nil }
                guard seen.insert(CFHash(current)).inserted else { continue }
                let role = text(current, kAXRoleAttribute)
                if roles.contains(role) {
                    let hint = [kAXDescriptionAttribute, kAXTitleAttribute].map { text(current, $0) }.first { !$0.isEmpty } ?? ""
                    if matches(role, hint), (attribute(current, kAXEnabledAttribute) as? Bool) != false,
                       inRequiredContainer(current) { return current }
                    continue
                }
                // The window pass looks for sidebar lists as well; buttons are leaves either way.
                guard !["AXStaticText", "AXTextArea", "AXTextField", "AXImage", "AXHeading", "AXLink", "AXButton", "AXPopUpButton", "AXMenuButton", "AXRow"].contains(role),
                      let children = attribute(current, kAXChildrenAttribute) as? [AXUIElement] else { continue }
                // popLast takes the end of the array, so later siblings are visited first.
                stack.append(contentsOf: children.prefix(64))
            }
        }
        return nil
    }
}

/// The sampler never touches app windows on the main run loop, screenshots,
/// conversation contents. Composer value, when needed, is reduced to an empty
/// flag and never logged or exported. All AX calls share a wall-time budget.
private final class AXSampler {
    private let deadline = ProcessInfo.processInfo.systemUptime + 0.06
    private var exhausted = false
    private var profile: ApplicationProfile = .codex
    private enum Value { case found(CFTypeRef), missing }
    private struct AttributeKey: Hashable { let element: CFHashCode; let name: String }
    private var attributes: [AttributeKey: Value] = [:]

    static func sample(_ request: AXSampleRequest) -> AXSampleResult {
        AXSampler().sample(request)
    }

    private func sample(_ request: AXSampleRequest) -> AXSampleResult {
        profile = request.profile
        var result = TargetObservation(pid: request.pid)
        result.context.applicationProfile = request.profile
        result.customProfile = request.customProfile
        let application = AXUIElementCreateApplication(request.pid)
        AXUIElementSetMessagingTimeout(application, 0.01)
        if request.enableWebAccessibility {
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        let focused = element(attribute(application, kAXFocusedUIElementAttribute))
        let window = element(attribute(application, kAXFocusedWindowAttribute))
        result.focused = focused; result.window = window
        let focusRole = focused.map { string($0, kAXRoleAttribute) } ?? ""
        let focusHint = focused.map(hints)?.lowercased() ?? ""
        let windowTitle = window.map { string($0, kAXTitleAttribute) } ?? ""
        let focusIdentifier = focused.map { string($0, kAXIdentifierAttribute) } ?? ""
        result.identity = TargetIdentity(pid: request.pid, windowHash: window.map(CFHash) ?? 0, windowTitle: windowTitle,
                                        focusedHash: focused.map(CFHash) ?? 0, focusedIdentifier: focusIdentifier)
        let isText = ["AXTextArea", "AXTextField"].contains(focusRole)
        let isSearch = Self.containsAny(focusHint, ["search", "搜索", "filter", "筛选", "command menu", "命令菜单"])
        var modal = window.map { (attribute($0, kAXModalAttribute) as? Bool) == true } ?? false
        var picker: InteractionMode?
        var binding: PickerBinding?
        var focusTrail: [AccessibilityFocusMetadata] = []
        var focusElements: [AXUIElement] = []
        var popupElements: [AXUIElement] = []

        // The focused popup's ancestors are both more specific and much smaller
        // than a full conversation tree. A binding is valid only while this
        // observed element still encloses focus.
        var ancestor = focused
        var visited: Set<CFHashCode> = []
        for _ in 0..<16 {
            guard let node = ancestor, visited.insert(CFHash(node)).inserted, !overBudget else { break }
            let role = string(node, kAXRoleAttribute)
            let subrole = string(node, kAXSubroleAttribute)
            let hint = hints(node)
            focusElements.append(node)
            focusTrail.append(AccessibilityFocusMetadata(role: role, subrole: subrole, hint: hint))
            let popup = Self.isPopup(role: role, subrole: subrole, hint: hint)
            modal = modal || popup || role == "AXMenuItem"
            if let mode = profile.pickerKind(hint, focusedSearch: (node === focused) && isText && isSearch), popup || ((node === focused) && isText && isSearch) || role == "AXMenuItem" {
                picker = mode; binding = PickerBinding(mode: mode, pid: request.pid, elementHash: CFHash(node), nativeMenu: role == "AXMenu" || role == "AXMenuItem")
                break
            }
            // The bound element is identified by hash; it need not look like a
            // popup (web model lists are plain groups of menu items).
            if let known = request.binding, known.pid == request.pid, known.elementHash == CFHash(node) {
                picker = known.mode; binding = known; modal = true; break
            }
            if popup { result.menuHashes.insert(CFHash(node)) }
            if popup {
                let childrenHint = descendants(node, limit: 16, depth: 2).map(hints).joined(separator: " ")
                if let mode = profile.pickerKind(hint + " " + childrenHint) {
                    picker = mode; binding = PickerBinding(mode: mode, pid: request.pid, elementHash: CFHash(node), nativeMenu: role == "AXMenu"); break
                }
                if let pending = request.pending,
                   AccessibilityHints.acceptRequestedMenu(mode: pending.mode, age: Date().timeIntervalSince(pending.requestedAt),
                       role: role, menuHash: CFHash(node), previousMenus: pending.originMenus,
                       originWindow: pending.originWindow, currentWindow: result.identity?.windowHash) {
                    picker = pending.mode; binding = PickerBinding(mode: pending.mode, pid: request.pid, elementHash: CFHash(node), nativeMenu: true); break
                }
                // A requested popover that takes focus itself (a web dialog
                // holding a slider or a short option list) is the selector.
                if let pending = request.pending, role != "AXMenu" {
                    let options = candidates(in: node, mode: pending.mode)
                    let slider = descendants(node, limit: 24, depth: 4).contains { string($0, kAXRoleAttribute) == "AXSlider" }
                    if AccessibilityHints.acceptRequestedSelector(mode: pending.mode, age: Date().timeIntervalSince(pending.requestedAt),
                        role: role, menuHash: CFHash(node), previousMenus: pending.originMenus, originWindow: pending.originWindow,
                        currentWindow: result.identity?.windowHash, options: options.count, slider: slider) {
                        let mode: InteractionMode = slider && options.isEmpty ? .efforts : pending.mode
                        picker = mode; binding = PickerBinding(mode: mode, pid: request.pid, elementHash: CFHash(node)); break
                    }
                }
            }
            if role == "AXWindow" || role == "AXApplication" { break }
            ancestor = element(attribute(node, kAXParentAttribute))
        }

        if picker == nil {
            popupElements = visiblePopups(around: focusElements, window: window,
                                          menuGroups: request.pending != nil || request.binding != nil)
            for node in popupElements {
                let role = string(node, kAXRoleAttribute), hash = CFHash(node)
                result.menuHashes.insert(hash)
                modal = true
                if let known = request.binding, known.pid == request.pid, known.elementHash == hash {
                    picker = known.mode; binding = known; break
                }
                if let pending = request.pending, role != "AXMenu", ProcessInfo.processInfo.systemUptime < deadline - 0.020 {
                    let options = candidates(in: node, mode: pending.mode)
                    let slider = descendants(node, limit: 24, depth: 4).contains { string($0, kAXRoleAttribute) == "AXSlider" }
                    if AccessibilityHints.acceptRequestedSelector(mode: pending.mode, age: Date().timeIntervalSince(pending.requestedAt),
                        role: role, menuHash: hash, previousMenus: pending.originMenus, originWindow: pending.originWindow,
                        currentWindow: result.identity?.windowHash, options: options.count, slider: slider) {
                        let mode: InteractionMode = slider && options.isEmpty ? .efforts : pending.mode
                        picker = mode; binding = PickerBinding(mode: mode, pid: request.pid, elementHash: hash); break
                    }
                }
                let hint = hints(node) + " " + descendants(node, limit: 24, depth: 3).map(hints).joined(separator: " ")
                if let mode = profile.pickerKind(hint) {
                    picker = mode; binding = PickerBinding(mode: mode, pid: request.pid, elementHash: hash, nativeMenu: role == "AXMenu"); break
                }
                if let pending = request.pending,
                   AccessibilityHints.acceptRequestedMenu(mode: pending.mode, age: Date().timeIntervalSince(pending.requestedAt),
                       role: role, menuHash: hash, previousMenus: pending.originMenus,
                       originWindow: pending.originWindow, currentWindow: result.identity?.windowHash) {
                    picker = pending.mode; binding = PickerBinding(mode: pending.mode, pid: request.pid, elementHash: hash, nativeMenu: true); break
                }
            }
        }
        if picker == nil, !modal, let list = request.sessionList {
            let rows = sessionRows(in: list)
            if !rows.isEmpty {
                picker = .sessions
                result.candidates = rows; result.sidebarPicker = true
                result.pickerRoot = CFHash(list); result.pickerFrame = frame(list)
            }
        }
        result.nativeMenu = binding?.nativeMenu == true
        if let currentBinding = binding, var node = (focusElements + popupElements).first(where: { CFHash($0) == currentBinding.elementHash }) {
            if string(node, kAXRoleAttribute) == "AXMenuItem", let parent = element(attribute(node, kAXParentAttribute)),
               string(parent, kAXRoleAttribute) == "AXMenu" { node = parent }
            result.pickerFrame = frame(node); result.pickerRoot = CFHash(node)
            if picker == .models || picker == .efforts {
                result.candidates = candidates(in: node, mode: picker!)
                if ProcessInfo.processInfo.systemUptime < deadline - 0.008,
                   let slider = descendants(node, limit: 32, depth: 4).first(where: { string($0, kAXRoleAttribute) == "AXSlider" }) {
                    result.adjustmentControl = slider
                    if let rect = frame(slider) {
                        let value = (attribute(slider, kAXValueAttribute) as? NSNumber)?.doubleValue
                        let minimum = (attribute(slider, kAXMinValueAttribute) as? NSNumber)?.doubleValue
                        let maximum = (attribute(slider, kAXMaxValueAttribute) as? NSNumber)?.doubleValue
                        result.adjustmentPoint = SliderTarget.point(frame: rect, value: value, minimum: minimum, maximum: maximum,
                            vertical: string(slider, kAXOrientationAttribute) == "AXVerticalOrientation")
                    }
                    if picker == .efforts || result.candidates.isEmpty || focusElements.contains(where: { CFEqual($0, slider) }) {
                        picker = .efforts; binding?.mode = .efforts; result.candidates = []
                    }
                }
                // Codex shows effort as a keyboard-adjusted row next to a
                // "Select model" entry. Turning adjusts effort; the model list
                // is one more press of the model action away.
                if picker == .efforts, result.adjustmentControl == nil {
                    result.adjustmentItem = result.candidates.first { AccessibilityHints.isEffortRow($0.title) }?.element
                    result.modelEntry = result.candidates.first { AccessibilityHints.isModelEntry($0.title) }?.element
                    if result.adjustmentItem != nil { result.candidates = [] }
                }
            }
        }

        // A fresh request can recognize a newly focused generic search field,
        // but only with the explicit compatibility option. Arbitrary modals
        // never inherit the kind of an earlier shortcut request.
        if picker == nil, let pending = request.pending, pending.pid == request.pid, let focused,
           AccessibilityHints.acceptCompatibilitySearch(mode: pending.mode,
               age: Date().timeIntervalSince(pending.requestedAt), originFocus: pending.originFocus,
               currentFocus: CFHash(focused), isText: isText, hint: focusHint, enabled: request.compatibilityPicker) {
            picker = .sessions
            binding = PickerBinding(mode: .sessions, pid: request.pid, elementHash: CFHash(focused))
        }

        // Contenteditable composers can expose an anonymous text area, or put
        // accessibility focus on a child of that area. Identify the text owner
        // using only metadata and writable/selection capabilities; never read
        // conversation contents or depend on caret/selection position.
        let textIndex = AccessibilityHints.textOwnerIndex(in: focusTrail)
        let textOwner = textIndex.map { focusElements[$0] }
        if let textIndex, let textOwner {
            focusTrail[textIndex].enabled = attribute(textOwner, kAXEnabledAttribute) as? Bool
            focusTrail[textIndex].editable = attribute(textOwner, "AXEditable") as? Bool
            focusTrail[textIndex].valueSettable = isSettable(textOwner, kAXValueAttribute)
            focusTrail[textIndex].selection = range(attribute(textOwner, kAXSelectedTextRangeAttribute))
        }
        result.context.editorFocused = AccessibilityHints.editorFocused(in: focusTrail, forceEditing: request.forceEditing)
        if result.context.editorFocused { result.editor = textOwner }
        // Browser fields never redirect the wheel into caret navigation. This
        // also keeps the runtime's editing gesture scope from bypassing reduce.
        if profile.alwaysScrolls || profile == .terminal { result.context.editorFocused = false }
        if result.context.editorFocused, let textOwner {
            result.editor = textOwner
            // Prefer length metadata. Only the confirmed composer may fall back
            // to its value; immediately reduce it to presence, never persist text.
            let count = (attribute(textOwner, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
            if let count, count >= 0 { result.context.hasDraftText = count > 0 }
            // Web composers report their placeholder (or a lone line break) as
            // the value of an empty draft. A short value is compared with the
            // field's own labels and reduced to a flag; it is never kept.
            if result.context.hasDraftText != false, (count ?? 0) <= 240, !overBudget,
               let value = attribute(textOwner, kAXValueAttribute) as? String {
                result.context.hasDraftText = profile.hasDraft(value: value,
                    labels: [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue"].map { string(textOwner, $0) })
            }
        }
        let windowFrame = window.flatMap(frame)
        let composerFrame = result.context.editorFocused ? textOwner.flatMap(frame) : nil
        let scrollArea = focusElements.first { string($0, kAXRoleAttribute) == "AXScrollArea" }.flatMap(frame)
        let viewport = profile.alwaysScrolls ? focusElements.first { string($0, kAXRoleAttribute) == "AXWebArea" }.flatMap(frame) : nil
        result.scrollPoint = ScrollTarget.point(window: windowFrame, composer: composerFrame,
                                               scrollArea: profile.alwaysScrolls ? nil : scrollArea, popup: result.pickerFrame, viewport: viewport)
        if picker == nil, let typed = request.typedPicker, typed.focus == focused.map(CFHash) { picker = typed.mode }
        result.context.modalOpen = modal
        result.context.picker = picker
        if let compositionOwner = textOwner ?? focused,
           let marked = range(attribute(compositionOwner, "AXMarkedTextRange")) {
            result.context.compositionActive = marked.length > 0
        }
        if request.inputSourceCanCompose && !overBudget && Self.visibleCandidateWindow() {
            result.context.compositionActive = true
        }
        result.sampledAt = Date()
        _ = overBudget
        result.context.targetAvailable = !exhausted && (window != nil || focused != nil)
        if !result.context.targetAvailable { result.status = L10n.tr("界面状态暂不可读，操作已暂停", "Interface state unavailable; action paused"); binding = nil }
        else if result.context.compositionActive { result.status = L10n.tr("输入法候选中，保留原生确认 / Escape", "Input method candidates active; native confirm / Escape preserved") }
        else if picker != nil { result.status = L10n.tr("选择器就绪", "Picker ready") }
        else if result.context.editingDraft { result.status = L10n.tr("旋转移动光标 · ESC 删除", "Turn to move cursor · ESC to delete") }
        else if profile.alwaysScrolls { result.status = L10n.tr("旋转滚动网页 · 单按切换标签页", "Turn to scroll · press to switch tabs") }
        else if profile == .terminal { result.status = L10n.tr("旋转滚屏 · 按旋钮输入 /resume 选会话", "Turn to scroll · press to type /resume for chats") }
        else if profile.isMessaging { result.status = L10n.tr("旋转滚动聊天 · 单按搜索聊天", "Turn to scroll chats · press to search") }
        else if profile == .custom { result.status = L10n.tr("自定义应用配置已就绪", "Custom app profile ready") }
        else { result.status = L10n.tr("旋转上下滚屏 · 按旋钮选择会话", "Turn to scroll · press the dial for chats") }
        return AXSampleResult(observation: result, binding: binding)
    }

    private var overBudget: Bool {
        if ProcessInfo.processInfo.systemUptime >= deadline { exhausted = true }
        return exhausted
    }
    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        let key = AttributeKey(element: CFHash(node), name: name)
        if let stored = attributes[key] {
            if case .found(let value) = stored { return value }
            return nil
        }
        guard !overBudget else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(node, name as CFString, &value)
        if error == .success, let value { attributes[key] = .found(value); return value }
        attributes[key] = .missing
        return nil
    }
    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func range(_ value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
    private func frame(_ node: AXUIElement) -> CGRect? {
        guard let position = attribute(node, kAXPositionAttribute), let size = attribute(node, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private func isSettable(_ node: AXUIElement, _ name: String) -> Bool {
        guard !overBudget else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(node, name as CFString, &settable) == .success && settable.boolValue
    }
    private func string(_ node: AXUIElement, _ name: String) -> String { (attribute(node, name) as? String) ?? "" }
    private func hints(_ node: AXUIElement) -> String {
        var parts = [kAXIdentifierAttribute, kAXDescriptionAttribute, kAXTitleAttribute, "AXPlaceholderValue"].map { String(string(node, $0).prefix(160)) }
        if profile == .workBuddy {
            parts += (attribute(node, "AXDOMClassList") as? [String] ?? []).prefix(8).map { String($0.prefix(100)) }
        }
        return parts.joined(separator: " ")
    }
    private func descendants(_ root: AXUIElement, limit: Int, depth: Int,
                             stopAt: ((AXUIElement) -> Bool)? = nil) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count && found.count < limit && !overBudget {
            let (node, level) = queue[index]; index += 1
            found.append(node)
            if level < depth, stopAt?(node) != true, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(limit-found.count).map { ($0, level+1) })
            }
        }
        return found
    }
    private func candidates(in root: AXUIElement, mode: InteractionMode) -> [AccessibleCandidate] {
        let webModels = profile == .workBuddy && mode == .models
        let stop = min(deadline - 0.012, ProcessInfo.processInfo.systemUptime + (webModels ? 0.030 : 0.012))
        let rootFrame = frame(root)
        var found: [(AccessibleCandidate, Int)] = []
        // Skip a model row's decorative children, so the bounded walk reaches
        // the options further down WorkBuddy's grouped and scrollable menu.
        let nodes = descendants(root, limit: webModels ? 128 : 48, depth: webModels ? 8 : 5,
            stopAt: webModels ? { (self.attribute($0, "AXDOMClassList") as? [String] ?? []).contains("cr-model-selector__item") } : nil)
        for node in nodes {
            guard ProcessInfo.processInfo.systemUptime < stop else { break }
            let role = string(node, kAXRoleAttribute)
            let webOption = webModels && profile.isWebModelOption(role: role, classes: attribute(node, "AXDOMClassList") as? [String] ?? [])
            guard webModels ? webOption : ["AXMenuItem", "AXRadioButton", "AXButton"].contains(role),
                  (attribute(node, kAXEnabledAttribute) as? Bool) != false, let rect = frame(node),
                  rect.width > 30, rect.height > 14 else { continue }
            if let rootFrame, rect.maxX < rootFrame.minX || rect.minX > rootFrame.maxX { continue }
            if role == "AXButton", mode == .models, let rootFrame, rect.width < rootFrame.width * 0.45 { continue }
            // Web menus mark the current choice as a checked item (value 1).
            let selected = (attribute(node, kAXSelectedAttribute) as? Bool) == true ||
                (["AXRadioButton", "AXMenuItem"].contains(role) && (attribute(node, kAXValueAttribute) as? NSNumber)?.boolValue == true)
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute] + (webOption ? [kAXValueAttribute] : [])
            let title = labels.map { string(node, $0) }.first { !$0.isEmpty } ?? ""
            found.append((AccessibleCandidate(element: node, frame: rect, selected: selected, title: String(title.prefix(40))), role == "AXButton" ? 1 : 0))
        }
        let preferred = found.contains(where: { $0.1 == 0 }) ? found.filter { $0.1 == 0 } : found
        var result: [AccessibleCandidate] = []
        for (candidate, _) in preferred.sorted(by: { ($0.0.frame.minY, $0.0.frame.minX) < ($1.0.frame.minY, $1.0.frame.minX) }) {
            if !result.contains(where: { abs($0.frame.midY - candidate.frame.midY) < 3 && abs($0.frame.midX - candidate.frame.midX) < 3 }) {
                result.append(candidate)
            }
        }
        return result
    }
    /// Visible rows of a sidebar chat list, top to bottom. Titles are navigation labels.
    private func sessionRows(in list: AXUIElement) -> [AccessibleCandidate] {
        let stop = min(deadline - 0.008, ProcessInfo.processInfo.systemUptime + 0.03)
        let bounds = frame(list)
        var rows: [AccessibleCandidate] = []
        for node in descendants(list, limit: 160, depth: 5) {
            guard ProcessInfo.processInfo.systemUptime < stop else { break }
            guard ["AXRow", "AXButton", "AXLink"].contains(string(node, kAXRoleAttribute)), let rect = frame(node),
                  rect.width > 60, rect.height > 14 else { continue }
            if let bounds, rect.maxX < bounds.minX || rect.minX > bounds.maxX { continue }
            let title = [kAXTitleAttribute, kAXDescriptionAttribute].map { string(node, $0) }.first { !$0.isEmpty } ?? ""
            rows.append(AccessibleCandidate(element: node, frame: rect,
                selected: (attribute(node, kAXSelectedAttribute) as? Bool) == true, title: String(title.prefix(40))))
        }
        return rows.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }
    /// `menuGroups`: while a picker was requested or is bound, a plain group
    /// that holds menu items counts too. Web apps render model lists that way,
    /// several levels below a portal at the end of the page.
    private func visiblePopups(around path: [AXUIElement], window: AXUIElement?, menuGroups: Bool = false) -> [AXUIElement] {
        let searchDeadline = min(deadline - 0.020, ProcessInfo.processInfo.systemUptime + (menuGroups ? 0.024 : 0.016))
        func budget() -> Bool { ProcessInfo.processInfo.systemUptime < searchDeadline }
        var roots = path.reversed().map { $0 }
        if let window, !roots.contains(where: { CFEqual($0, window) }) { roots.insert(window, at: 0) }
        let excluded = Set(path.map(CFHash))
        var queue: [(AXUIElement, Int, AXUIElement?)] = []
        for root in roots where budget() {
            if let children = attribute(root, kAXChildrenAttribute) as? [AXUIElement] {
                queue += children.reversed().prefix(24).filter { !excluded.contains(CFHash($0)) }.map { ($0, 0, root) }
            }
        }
        let maximumDepth = menuGroups ? 9 : 4
        var visited: Set<CFHashCode> = [], popups: [AXUIElement] = [], known: Set<CFHashCode> = []
        while !queue.isEmpty && visited.count < (menuGroups ? 140 : 80) && budget() {
            let (node, depth, parent) = queue.removeFirst()
            guard visited.insert(CFHash(node)).inserted else { continue }
            let role = string(node, kAXRoleAttribute)
            if menuGroups, role == "AXMenuItem", let parent, !excluded.contains(CFHash(parent)) {
                if known.insert(CFHash(parent)).inserted, string(parent, kAXRoleAttribute) != "AXMenu" { popups.append(parent) }
                continue
            }
            if ["AXStaticText", "AXTextArea", "AXTextField", "AXImage", "AXButton"].contains(role) { continue }
            let subrole = string(node, kAXSubroleAttribute)
            let hint = ["AXMenu", "AXDialog", "AXSheet"].contains(role) ? "" :
                (string(node, kAXIdentifierAttribute) + " " + string(node, kAXDescriptionAttribute) + " " + String(string(node, kAXTitleAttribute).prefix(60)))
            if Self.isPopup(role: role, subrole: subrole, hint: hint) ||
               (["AXList", "AXOutline"].contains(role) && profile.pickerKind(hint) != nil) {
                if known.insert(CFHash(node)).inserted { popups.append(node) }
                continue
            }
            if depth < maximumDepth, budget(), let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.insert(contentsOf: children.reversed().prefix(16).filter { !excluded.contains(CFHash($0)) }.map { ($0, depth + 1, node) }, at: 0)
            }
        }
        return popups
    }
    private static func isPopup(role: String, subrole: String, hint: String) -> Bool {
        if ["AXMenu", "AXSheet", "AXDialog"].contains(role) ||
            ["AXDialog", "AXSystemDialog", "AXApplicationDialog", "AXApplicationAlertDialog"].contains(subrole) { return true }
        guard !["AXTextArea", "AXTextField", "AXButton", "AXPopUpButton", "AXComboBox", "AXStaticText", "AXWindow", "AXApplication"].contains(role) else { return false }
        let normalized = hint.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return containsAny(normalized, ["dialog", "picker", "listbox", "popover", "command menu", "command palette", "model menu", "effort menu",
                                        "select effort", "select model", "选择强度", "选择模型"])
    }
    private static func containsAny(_ text: String, _ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
    private static func visibleCandidateWindow() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            let owner = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let title = (window[kCGWindowName as String] as? String ?? "").lowercased()
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if containsAny(title, ["候选", "candidate"]) && containsAny(owner, ["input", "doubao", "豆包", "sogou", "搜狗"]) { return true }
            return layer > 0 && containsAny(owner, ["textinputmenuagent", "scim", "tcim", "japaneseim", "kotoeri"])
        }
    }
}

struct KeyStroke {
    var code: CGKeyCode
    var flags: CGEventFlags = []
}

struct AccessibilityFocusMetadata {
    var role: String
    var subrole = ""
    var hint = ""
    var enabled: Bool?
    var editable: Bool?
    var valueSettable = false
    var selection: CFRange?
}

/// UI metadata recognition is pure so unsupported/ambiguous fixtures can be
/// tested without reading or controlling any running application.
enum AccessibilityHints {
    /// The focus path goes from the focused node toward its window. Controls
    /// such as a send button must not inherit the editor around them.
    static func textOwnerIndex(in path: [AccessibilityFocusMetadata]) -> Int? {
        guard let focused = path.first,
              ["AXTextArea", "AXTextField", "AXStaticText", "AXGroup", "AXUnknown"].contains(focused.role) else { return nil }
        for (index, node) in path.enumerated() {
            if ["AXTextArea", "AXTextField"].contains(node.role) { return index }
            if ["AXWindow", "AXApplication"].contains(node.role) { break }
        }
        return nil
    }

    static func editorFocused(in path: [AccessibilityFocusMetadata], forceEditing: Bool = false) -> Bool {
        guard let index = textOwnerIndex(in: path) else { return false }
        let owner = path[index]
        guard owner.enabled != false, owner.editable != false else { return false }
        // Restrict hints to the enclosing UI controls. A chat's window title
        // can contain words such as "search" without making its composer one.
        let controls = path.prefix { !["AXWindow", "AXApplication"].contains($0.role) }
        let hint = controls.map(\.hint).joined(separator: " ").lowercased()
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        guard !controls.contains(where: { $0.subrole == "AXSearchField" }),
              !containsAny(hint, ["search", "搜索", "filter", "筛选", "command menu", "命令菜单",
                                  "terminal", "终端", "code editor", "monaco", "file editor", "source editor", "codemirror", "xterm"]) else { return false }
        if forceEditing || containsAny(hint, ["composer", "prompt", "message", "describe", "ask", "reply", "do anything", "输入消息", "描述", "提问", "输入框", "回复", "发消息"]) {
            return true
        }
        // Anonymous single-line fields can be rename inputs or settings. Only
        // a multiline text area with actual editability and a valid selection
        // is an automatic fallback. A collapsed selection at either boundary,
        // including (0, 0) in an empty draft, is still an editor.
        guard owner.role == "AXTextArea", owner.editable == true || owner.valueSettable,
              let selection = owner.selection, selection.location >= 0, selection.length >= 0 else { return false }
        return true
    }

    static func isEffortRow(_ title: String) -> Bool {
        ["power", "effort", "reasoning", "reasoning effort", "强度", "推理强度", "思考强度"].contains(title.trimmingCharacters(in: .whitespaces).lowercased())
    }
    static func isModelEntry(_ title: String) -> Bool {
        let text = title.trimmingCharacters(in: .whitespaces).lowercased()
        return text == "select model" || text == "选择模型" || text == "model" || text == "模型"
    }

    /// An empty web composer still has a value: its placeholder, or a line break.
    static func hasDraft(value: String, labels: [String]) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return !labels.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == text }
    }

    static func pickerKind(_ hint: String) -> InteractionMode? {
        let normalized = hint.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        // A control often repeats one label as title and description.
        var words: [Substring] = []
        for word in normalized.split(separator: " ") where !words.contains(word) { words.append(word) }
        let exact = words.joined(separator: " ")
        // Harness uses one combined menu; do not classify its model rows as
        // an effort-only selector just because the label also mentions effort.
        if ["model and reasoning effort", "模型与推理等级"].contains(exact) { return .models }
        if ["reasoning", "effort", "推理强度", "思考强度"].contains(exact) { return .efforts }
        if ["model", "模型"].contains(exact) { return .models }
        if containsAny(normalized, ["reasoning effort", "effort picker", "select effort", "推理强度", "思考强度", "选择强度", "reasoning intensity"]) { return .efforts }
        if containsAny(normalized, ["choose model", "select model", "model picker", "model selection", "model select", "model selector", "model dropdown", "model switcher", "model menu", "search models", "选择模型", "模型选择", "搜索模型"]) { return .models }
        if containsAny(normalized, ["command menu", "command palette", "search chats", "search conversations", "search sessions", "search session names", "搜索聊天", "搜索会话", "命令菜单", "recent chats"]) { return .sessions }
        return nil
    }

    static func acceptRequestedMenu(mode: InteractionMode, age: TimeInterval, role: String,
                                    menuHash: CFHashCode, previousMenus: Set<CFHashCode>,
                                    originWindow: CFHashCode?, currentWindow: CFHashCode?) -> Bool {
        guard mode == .models || mode == .efforts, (0...1.2).contains(age), role == "AXMenu",
              !previousMenus.contains(menuHash), let originWindow, let currentWindow,
              originWindow != 0, originWindow == currentWindow else { return false }
        return true
    }

    static func acceptRequestedSelector(mode: InteractionMode, age: TimeInterval, role: String,
                                        menuHash: CFHashCode, previousMenus: Set<CFHashCode>,
                                        originWindow: CFHashCode?, currentWindow: CFHashCode?, options: Int, slider: Bool) -> Bool {
        guard mode == .models || mode == .efforts, (0...1.2).contains(age),
              ["AXDialog", "AXSheet", "AXGroup", "AXList"].contains(role),
              options >= 2 || slider, !previousMenus.contains(menuHash),
              let originWindow, let currentWindow, originWindow != 0, originWindow == currentWindow else { return false }
        return true
    }

    static func acceptCompatibilitySearch(mode: InteractionMode, age: TimeInterval, originFocus: CFHashCode?,
                                          currentFocus: CFHashCode?, isText: Bool, hint: String, enabled: Bool) -> Bool {
        guard enabled, mode == .sessions, (0...1.2).contains(age), isText,
              let originFocus, let currentFocus, originFocus != currentFocus else { return false }
        return containsAny(hint.lowercased(), ["search", "搜索", "filter", "筛选"])
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
}
