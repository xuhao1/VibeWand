import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AU05Device

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

enum SettingsSection: Int, CaseIterable {
    case general, devices, applications, overlay, developer, about, speech, command
    static let allCases: [SettingsSection] = [.general, .devices, .speech, .command, .applications, .overlay, .developer, .about]
    var title: String {
        switch self {
        case .general: return tr("通用", "General")
        case .devices: return tr("设备与按键", "Devices & inputs")
        case .applications: return tr("应用适配", "Applications")
        case .overlay: return tr("悬浮面板", "Overlay")
        case .developer: return tr("开发者", "Developer")
        case .about: return tr("关于", "About")
        case .speech: return tr("语音输入", "Voice input")
        case .command: return tr("命令模式", "Command mode")
        }
    }
    var tint: Color {
        switch self {
        case .general: return .gray
        case .devices: return .blue
        case .applications: return .indigo
        case .overlay: return .teal
        case .developer: return .orange
        case .about: return Color(nsColor: .systemGray)
        case .speech: return .pink
        case .command: return .purple
        }
    }
    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .devices: return "gamecontroller"
        case .applications: return "square.grid.2x2"
        case .overlay: return "macwindow"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .about: return "info.circle"
        case .speech: return "waveform"
        case .command: return "wand.and.stars"
        }
    }
}

@MainActor
final class SettingsController: NSWindowController {
    private let model: SettingsModel
    private var languageObserver: NSObjectProtocol?
    private var keyObservers: [NSObjectProtocol] = []
    private var renderingAudit = false
    private func updateDevicePin() {
        model.runtime.autoSwitchSuspended = window?.isKeyWindow == true && window?.isVisible == true && model.section == .devices
    }
    init(runtime: BridgeRuntime, overlay: OverlayController) {
        model = SettingsModel(runtime: runtime, overlay: overlay)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = tr("VibeWand 设置", "VibeWand Settings")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1100, height: 750)
        super.init(window: window)
        let host = NSHostingController(rootView: SettingsShell(model: model))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1220, height: 790))
        window.setFrameAutosaveName("VibeWand.settings.studio")
        window.center()
        // While the layout editor is in front, pressing another device must
        // not swap the layout being edited.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateDevicePin() }
            })
        }
        model.onSectionChange = { [weak self] in self?.updateDevicePin() }
        languageObserver = NotificationCenter.default.addObserver(forName: L10n.languageDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window?.title = tr("VibeWand 设置", "VibeWand Settings")
                self?.model.refresh()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    deinit {
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }
    func present(tab: Int? = nil) {
        if let tab, let section = SettingsSection(rawValue: tab) { model.section = section }
        model.refresh(); showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func refresh() { model.refresh() }
    /// Opens the first-run guide, from the pages that offer it.
    var onGuide: (() -> Void)? {
        get { model.onGuide }
        set { model.onGuide = newValue }
    }
    func update(_ snapshot: HUDSnapshot) { if !renderingAudit { model.snapshot = snapshot } }
    @discardableResult func renderPNG(to url: URL) -> Bool {
        guard let view = window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); return true } catch { return false }
    }

    /// Export our own UI for repeatable visual review. Preferences and the
    /// active page are restored after rendering; no target app is controlled.
    func renderAudit(to directory: URL) async throws {
        guard let window else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldLanguage = L10n.shared.language, oldSection = model.section
        let oldFrame = window.frame, oldAppearance = window.appearance
        renderingAudit = true
        defer {
            renderingAudit = false
            L10n.shared.language = oldLanguage; model.section = oldSection
            window.appearance = oldAppearance; window.setFrame(oldFrame, display: true)
        }
        let names = ["general", "devices", "applications", "overlay", "developer", "about", "speech", "command"]
        let variants: [(String, AppLanguage, NSAppearance.Name, NSSize)] = [
            ("zh", .zhHans, .aqua, NSSize(width: 1220, height: 790)),
            ("en-compact", .english, .aqua, NSSize(width: 1100, height: 750)),
            ("dark-compact", .zhHans, .darkAqua, NSSize(width: 1100, height: 750))
        ]
        var rendered: [String] = []
        for (variant, language, appearance, size) in variants {
            window.appearance = NSAppearance(named: appearance)
            L10n.shared.language = language
            window.setContentSize(size)
            for section in SettingsSection.allCases {
                model.section = section; model.refresh()
                try await Task.sleep(nanoseconds: 450_000_000)
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
                let name = "\(variant)-\(names[section.rawValue]).png"
                guard renderPNG(to: directory.appendingPathComponent(name)) else { throw CocoaError(.fileWriteUnknown) }
                rendered.append(name)
            }
        }
        try JSONEncoder().encode(rendered).write(to: directory.appendingPathComponent("complete.json"), options: .atomic)
    }
}

struct GestureEditRequest: Identifiable {
    let control: DeviceControl
    let kind: GestureKind
    var id: String { "\(control.rawValue).\(kind.rawValue)" }
}

@MainActor
final class SettingsModel: ObservableObject {
    let runtime: BridgeRuntime
    let overlay: OverlayController
    @Published var snapshot: HUDSnapshot
    @Published var section = SettingsSection.devices { didSet { onSectionChange?() } }
    var onSectionChange: (() -> Void)?
    var onGuide: (() -> Void)?
    @Published var selectedControl = "dial"
    @Published var scope = GestureScope.global
    @Published var error: String?
    @Published var editRequest: GestureEditRequest?
    init(runtime: BridgeRuntime, overlay: OverlayController) {
        self.runtime = runtime; self.overlay = overlay; snapshot = runtime.snapshot
    }
    var template: DeviceTemplate { runtime.templates.selectedTemplate }
    var config: GestureConfiguration { runtime.configuration }
    var selected: DeviceTemplateControl { template.controls.first { $0.id == selectedControl } ?? template.controls[0] }
    func refresh() { objectWillChange.send(); snapshot = runtime.snapshot }
    func perform(_ work: () throws -> Void) {
        do { try work(); refresh() } catch { self.error = error.localizedDescription }
    }
    func chooseTemplate(_ id: DeviceTemplateID) {
        perform { try runtime.selectTemplate(id) }
        selectedControl = DeviceControl.dial.rawValue
    }
    func inherited(_ control: DeviceControl, _ kind: GestureKind) -> GestureAction {
        var inherited = config
        inherited.set(scope, control, kind, template.defaultConfiguration.explicit(scope, control, kind))
        return inherited.action(scope, control, kind)
    }
    func isInherited(_ control: DeviceControl, _ kind: GestureKind) -> Bool {
        config.explicit(scope, control, kind) == template.defaultConfiguration.explicit(scope, control, kind)
    }
    func setAction(_ action: GestureAction?, control: DeviceControl, kind: GestureKind) {
        var config = config
        config.set(scope, control, kind, action ?? template.defaultConfiguration.explicit(scope, control, kind))
        perform { try runtime.updateConfiguration(config) }
    }
    func resetControl() {
        var config = config
        for kind in selected.gestures { config.set(scope, selected.control, kind, template.defaultConfiguration.explicit(scope, selected.control, kind)) }
        perform { try runtime.updateConfiguration(config) }
    }
    func primaryAction(_ item: DeviceTemplateControl) -> GestureAction {
        if item.gestures.contains(.hold), config.action(scope, item.control, .hold) != .none {
            return config.action(scope, item.control, .hold)
        }
        for kind in item.gestures {
            let action = config.action(scope, item.control, kind)
            if action != .none { return action }
        }
        return .none
    }
    func gestureTitle(_ kind: GestureKind) -> String {
        if kind == .rotate && selected.control.rawValue.contains("Stick") {
            return tr("拨动 / 持续拨住", "Tilt / keep tilted")
        }
        // On a button a step is the press itself: at once on the way down, again while it stays down.
        if kind == .rotate && selected.control != .left && selected.control != .right {
            return tr("按下即触发 · 按住连发", "Press at once · repeats while held")
        }
        return kind == .rotate && template.id != .vibeKey ? tr("按下", "Press") : kind.label
    }
    func setTiming(double: Double? = nil, long: Double? = nil) {
        var config = config
        if let double { config.doubleClickInterval = double; config.longPressInterval = max(config.longPressInterval, double + 0.05) }
        if let long { config.longPressInterval = max(long, config.doubleClickInterval + 0.05) }
        perform { try runtime.updateConfiguration(config) }
    }
    func importGestures() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.title = tr("导入当前模板配置", "Import layout")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let data = try Data(contentsOf: url)
            guard data.count <= 65536 else { throw GestureConfiguration.ConfigurationError.invalid }
            try runtime.updateConfiguration(JSONDecoder().decode(GestureConfiguration.self, from: data))
        }
    }
    func exportGestures() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.title = tr("导出当前模板配置", "Export layout")
        panel.nameFieldStringValue = "VibeWand-\(template.title).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        }
    }
    func importDevice() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.title = tr("连接设备配置", "Connect a device profile")
        panel.message = tr("将实测 HID 配置绑定到当前模板。配置需要明确的 VID、PID 和接口。", "Link a measured HID profile to this layout. The profile must identify a specific vendor, product and interface.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let data = try Data(contentsOf: url)
            guard data.count <= 65536 else { throw GestureConfiguration.ConfigurationError.invalid }
            try runtime.configureDevice(profile: JSONDecoder().decode(HIDDeviceProfile.self, from: data))
        }
    }
    func accessibility() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    func exportImage() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "VibeWand-Overlay.png"
        if panel.runModal() == .OK, let url = panel.url, !overlay.renderPNG(to: url) { error = tr("面板图片导出失败。", "The overlay image could not be exported.") }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "VibeWand-Diagnostics.json"
        if panel.runModal() == .OK, let url = panel.url { perform { try runtime.exportSnapshot(url) } }
    }
    func preference(_ key: String, fallback: Double, apply: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: { UserDefaults.standard.object(forKey: key) as? Double ?? fallback }, set: { value in
            UserDefaults.standard.set(value, forKey: key); apply(value); self.refresh()
        })
    }
}

private struct SettingsShell: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var localization = L10n.shared
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 10) {
                    BrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("VibeWand").font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1)
                        Text(tr("把操作握在手中", "Your controls. Your flow."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 5)
                VStack(spacing: 3) {
                    ForEach(SettingsSection.allCases, id: \.rawValue) { section in
                        SettingsNavigationButton(section: section, selected: model.section == section) { model.section = section }
                    }
                }
                Spacer()
                Text("VibeWand \(SettingsStyle.version)").font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
            }.padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 14)
                .frame(width: 208).background { SettingsBackdrop(material: .sidebar).ignoresSafeArea() }
            Divider().opacity(0.45)
            Group {
                switch model.section {
                case .devices: DeviceSettings(model: model)
                case .general: GeneralSettings(model: model)
                case .applications: ApplicationSettings(model: model)
                case .overlay: OverlaySettings(model: model)
                case .developer: DeveloperSettings(model: model)
                case .about: AboutSettings()
                case .speech: SpeechSettings(model: model, voice: model.runtime.voiceInput)
                case .command: CommandSettingsPage(model: model, settings: model.runtime.command.settings)
                }
            }.id(localization.language).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { SettingsBackdrop().ignoresSafeArea() }
        .font(.system(size: 14))
        .environment(\.locale, localization.language.locale)
        .alert(tr("无法保存设置", "Unable to save settings"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(tr("知道了", "OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(item: $model.editRequest) { request in ActionLibrary(model: model, request: request) }
    }
}

private struct SettingsNavigationButton: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(section.tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(section.title).font(.system(size: 14, weight: selected ? .semibold : .regular)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 40)
            .background(selected ? Color.primary.opacity(0.11) : hovered ? Color.primary.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
            .onHover { hovered = $0 }
            .accessibilityLabel(section.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private enum InputGroup: String, CaseIterable {
    case all, buttons, shoulders, sticks, dpad, more
    var title: String {
        switch self {
        case .all: return tr("全部", "All")
        case .buttons: return tr("面键", "Buttons")
        case .shoulders: return tr("肩键", "Shoulders")
        case .sticks: return tr("摇杆", "Sticks")
        case .dpad: return tr("方向键", "D-pad")
        case .more: return tr("其他", "More")
        }
    }
    func contains(_ control: DeviceControl) -> Bool {
        switch self {
        case .all: return true
        case .buttons: return [.dial,.ok,.escape,.voice].contains(control)
        case .shoulders: return [.l1,.l2,.r1,.r2].contains(control)
        case .sticks: return control.rawValue.contains("Stick")
        case .dpad: return [.dpadUp,.dpadDown,.dpadLeft,.dpadRight].contains(control)
        case .more: return !InputGroup.buttons.contains(control) && !InputGroup.shoulders.contains(control) && !InputGroup.sticks.contains(control) && !InputGroup.dpad.contains(control)
        }
    }
}

struct DeviceSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var group = InputGroup.all
    @State private var showTiming = false
    @State private var showConnection = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(tr("设备布局", "Layout")).font(.system(size: 20, weight: .semibold)).fixedSize()
                Picker(tr("模板", "Layout"), selection: Binding(get: { model.runtime.templates.selectedID }, set: model.chooseTemplate)) {
                    ForEach(DeviceTemplateID.allCases, id: \.self) { id in
                        Text((model.snapshot.connectedTemplates.contains(id) ? "● " : "") + id.template.title).tag(id)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 420)
                    .help(tr("● 表示该设备已连接。按下任意已连接设备上的按键即可切换到它。", "● marks a connected device. Press any button on a connected device to switch to it."))
                Toggle(tr("跟随正在使用的设备", "Follow the device in use"), isOn: Binding(get: { model.runtime.followsActiveDevice },
                    set: { model.runtime.setFollowsActiveDevice($0); model.refresh() })).toggleStyle(.switch).controlSize(.small)
                Spacer(minLength: 0)
                Button { model.runtime.toggleCard() } label: { Label(tr("按键一览", "Controls"), systemImage: "gamecontroller") }
                    .help(tr("把当前布局画成一张图：每个键在每个场景里做什么。", "The layout as one picture: what every control does in every scene."))
                Button(action: model.importGestures) { Label(tr("导入", "Import"), systemImage: "square.and.arrow.down") }
                Button(action: model.exportGestures) { Label(tr("导出", "Export"), systemImage: "square.and.arrow.up") }
                Button { model.runtime.resetConfiguration(); model.refresh() } label: { Label(tr("恢复默认", "Reset"), systemImage: "arrow.counterclockwise") }
            }
            if model.template.id == .dualSense {
                HStack(spacing: 12) {
                    Toggle(tr("启用手柄蓝牙语音", "Enable controller Bluetooth microphone"), isOn: Binding(
                        get: { model.runtime.dualSenseVoiceEnabled },
                        set: { enabled in model.perform { try model.runtime.setDualSenseVoiceEnabled(enabled) }; model.refresh() }
                    )).toggleStyle(.switch).disabled(!DualSenseMicrophoneSource.supported || model.runtime.templates.profile(for: .dualSense) != nil)
                    Spacer()
                    Text(model.runtime.connectionSummary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                SettingsNote(text: tr("实验版 · 开启后内置语音输入使用 DualSense 麦克风，按键由 VibeWand 接收。连接时会暂时开启游戏模式；USB 或其他手柄继续使用常规输入。外置输入法需自行选择 VibeWand DualSense Mic。", "Experimental · Built-in dictation uses the DualSense microphone while enabled; VibeWand receives its buttons. Game Mode is temporarily enabled while connected. USB and other controllers use normal input. Select VibeWand DualSense Mic in an external input method."))
            }
            GeometryReader { area in
                HStack(alignment: .top, spacing: 14) {
                    if model.template.id == .dualSense {
                        VStack(spacing: 10) {
                            DevicePhoto(model: model)
                                .frame(height: min(300, max(230, area.size.height * 0.42)))
                            Picker(tr("按键分组", "Input group"), selection: $group) {
                                ForEach(InputGroup.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 7) {
                                    ForEach(model.template.controls.filter { group.contains($0.control) }, id: \.id) { item in
                                        InputBindingRow(model: model, item: item)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity)
                    } else {
                        Group {
                            if model.template.id == .keyboard { KeyboardCaps(model: model) } else { DevicePhoto(model: model) }
                        }.frame(width: max(184, min(240, area.size.width * 0.25)))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(tr("实体按键", "Physical inputs")).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(model.template.controls.count)").font(.system(size: 13)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 3)
                            ScrollView {
                                LazyVStack(spacing: 7) {
                                    ForEach(model.template.controls, id: \.id) { item in InputBindingRow(model: model, item: item) }
                                }
                            }
                        }.frame(maxWidth: .infinity)
                    }
                    InputInspector(model: model).id(model.selected.id).frame(width: 300)
                }.id(model.template.id)
            }
            HStack(spacing: 14) {
                Button { showConnection = true } label: {
                    Label(model.snapshot.connected ? tr("设备已连接", "Device connected") : tr("连接设备…", "Connect device…"), systemImage: model.snapshot.connected ? "checkmark.circle" : "cable.connector")
                }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(model.snapshot.connected ? Color.green : Color.secondary)
                Spacer()
                Button { showTiming = true } label: { Label(tr("手势时序", "Gesture timing"), systemImage: "timer") }.font(.system(size: 13))
                Label(tr("已自动保存", "Auto-saved"), systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 14)
            .onChange(of: model.runtime.templates.selectedID) { group = .all }
            .sheet(isPresented: $showTiming) { TimingSettings(model: model) }
            .sheet(isPresented: $showConnection) { ConnectionSettings(model: model) }
    }
}

private struct InputBindingRow: View {
    @ObservedObject var model: SettingsModel
    let item: DeviceTemplateControl
    var body: some View {
        Button { model.selectedControl = item.id } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol).frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text(model.primaryAction(item).label).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 11).padding(.vertical, 9)
                .settingsGlass(cornerRadius: 8)
                .background(model.selectedControl == item.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selectedControl == item.id ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.07), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(item.title): \(model.primaryAction(item).label)")
            .accessibilityAddTraits(model.selectedControl == item.id ? .isSelected : [])
    }
}

private struct DevicePhoto: View {
    @ObservedObject var model: SettingsModel
    @State private var hovered: String?
    private var artwork: DeviceArtwork { DeviceArtwork.forTemplate(model.template.id) }
    var body: some View {
        GeometryReader { geometry in
            let rect = photoRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.14, green: 0.18, blue: 0.24), Color(red: 0.07, green: 0.095, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = artwork.image {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 12)
                }
                ForEach(model.template.controls, id: \.id) { item in
                    if let point = artwork.hotspots[item.control] {
                        let selected = model.selectedControl == item.id
                        let active = model.snapshot.pressed.contains(item.control)
                        let direction = item.control.rawValue.contains("Stick") && !item.control.rawValue.hasSuffix("Press")
                        Button { model.selectedControl = item.id } label: {
                            Circle().fill(selected ? Color.accentColor.opacity(0.60) : active ? Color.green.opacity(0.7) : Color.black.opacity(0.1))
                                .overlay(Circle().stroke(selected ? Color.white : active ? .green : Color.white.opacity(0.55), lineWidth: selected ? 2 : 1))
                                .overlay(Circle().stroke(Color.accentColor.opacity(selected ? 0.65 : 0), lineWidth: 6).padding(-2))
                                .frame(width: direction || selected || hovered == item.id ? 24 : 15, height: direction || selected || hovered == item.id ? 24 : 15)
                                .overlay {
                                    if direction { Image(systemName: item.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                                }
                                .frame(width: direction ? 24 : 28, height: direction ? 24 : 28).contentShape(Circle())
                        }.buttonStyle(.plain).help(item.title)
                            .accessibilityLabel(tr("配置 ", "Configure ") + item.title)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .onHover { hovered = $0 ? item.id : nil }
                            .position(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                    }
                }
                HStack(spacing: 7) {
                    Image(systemName: model.selected.symbol)
                    Text(model.selected.title).fontWeight(.medium)
                    if model.template.id == .dualSense {
                        Text("·").foregroundStyle(.white.opacity(0.3))
                        Text(model.primaryAction(model.selected).label).lineLimit(1)
                    }
                }.font(.system(size: 13)).foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.black.opacity(0.32), in: Capsule()).padding(14)
                VStack {
                    Spacer()
                    Text(model.template.id == .dualSense ? tr("点击按键或摇杆方向进行配置", "Click a button or stick direction to configure") : tr("点击设备上的按键以编辑", "Click a button on the device to edit"))
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.bottom, 13).frame(maxWidth: .infinity)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    private func photoRect(in size: CGSize) -> CGRect {
        let portrait = model.template.id != .dualSense
        let area = CGSize(width: size.width - 20, height: size.height - (portrait ? 100 : 50))
        let ratio = artwork.aspectRatio
        let width = min(area.width / (portrait ? 0.5 : 1), area.height * ratio)
        let height = width / ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2 + 6, width: width, height: height)
    }
}

/// The keyboard layout in place of a photograph: one key cap for each control, carrying its combination.
private struct KeyboardCaps: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        let layout = KeyboardLayout.current, clashes = layout.clashes
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ForEach(model.template.controls, id: \.id) { item in
                let selected = model.selectedControl == item.id, down = model.snapshot.pressed.contains(item.control)
                Button { model.selectedControl = item.id } label: {
                    VStack(spacing: 3) {
                        Text(layout.label(item.control).isEmpty ? "—" : layout.label(item.control)).font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(item.control.label).font(.system(size: 11)).opacity(0.7).lineLimit(1)
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(down ? Color.green.opacity(0.6) : selected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(clashes.contains(item.control) ? Color.orange : selected ? Color.white : Color.white.opacity(0.3), lineWidth: selected ? 1.5 : 0.8))
                }.buttonStyle(.plain).accessibilityLabel(tr("配置 ", "Configure ") + item.title).accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Text(tr("点一个键帽修改它的组合键和动作", "Click a key cap to change its combination and actions"))
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.14, green: 0.18, blue: 0.24), Color(red: 0.07, green: 0.095, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Changes the key combination that stands for one control of the keyboard layout. The combination is recorded
/// by pressing it, so that a key need not have a name: the extra keys of a custom keyboard are chosen the same way.
private struct KeyboardChordEditor: View {
    @ObservedObject var model: SettingsModel
    let control: DeviceControl
    @State private var recording = false
    var body: some View {
        let layout = KeyboardLayout.current, chord = layout.chord(control), listening = model.snapshot.connected
        VStack(alignment: .leading, spacing: 7) {
            Text(tr("组合键", "Key combination")).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Text(recording ? tr("按下要用的键…", "Press the key…") : chord?.label ?? tr("未设置", "Not set"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(recording ? Color.accentColor : chord == nil ? Color.secondary : Color.primary)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 30)
                    .background(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(recording ? Color.accentColor : Color.clear, lineWidth: 1.5))
                    .animation(.easeInOut(duration: 0.15), value: recording)
                    .accessibilityLabel(tr("当前组合键", "Current combination"))
                Button { recording ? stop() : record() } label: {
                    Label(recording ? tr("取消", "Cancel") : tr("录制", "Record"), systemImage: recording ? "xmark.circle" : "record.circle")
                }.disabled(!listening).fixedSize()
            }
            if recording {
                note(tr("直接按下那个键，可以同时按住 ⌃ ⌥ ⇧ ⌘。键盘上任何会发出按键的键都行，不用知道它叫什么。单按 Esc 取消。按了没有反应，说明这个键发的不是普通按键（比如音量、播放键）：在键盘自己的配置工具里把它改成 F13–F20 就能用。",
                        "Press the key itself, with ⌃ ⌥ ⇧ ⌘ held if you like. Any key that sends a key press will do; you need not know what it is called. Escape alone cancels. A key that gets no answer does not send an ordinary key press (volume and playback keys are such): set it to F13–F20 in the keyboard's own configuration tool and it will."), .secondary)
            } else if !listening {
                note(tr("键盘还没有接上（需要辅助功能权限），接上后才能录制。", "The keyboard is not being listened to yet (Accessibility access is needed); recording works once it is."), .orange)
            }
            HStack(spacing: 4) {
                modifier("⌃", "Control", \.control, chord); modifier("⌥", "Option", \.option, chord)
                modifier("⇧", "Shift", \.shift, chord); modifier("⌘", "Command", \.command, chord)
                Spacer(minLength: 0)
                Button(tr("不使用", "None")) { stop(); set(nil) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).disabled(chord == nil)
            }
            if let chord, !KeyboardLayout.usable(chord) {
                note(tr("这个键平时要用来打字或编辑，单独用会让它再也打不出来：请同时按住 ⌃、⌥、⌘ 中的一个。F 键、数字小键盘和扩展键可以单独用。现在这个组合不会生效。",
                        "This key is one text is typed or edited with, and alone it could no longer be typed: hold one of ⌃, ⌥ or ⌘ with it. Function keys, the number pad and extra keys may stand alone. As it stands this combination does nothing."), .orange)
            } else if layout.clashes.contains(control) {
                note(tr("和前面一个键位的组合相同，只有排在前面的那个会生效。", "Another control above uses the same combination; only the first of them fires."), .orange)
            }
            Button(tr("恢复默认组合键", "Restore the default combination")) { stop(); set(KeyboardLayout.standard.chord(control)) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .onChange(of: control) { stop() }
        .onDisappear { stop() }
    }
    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
    private func modifier(_ symbol: String, _ name: String, _ keyPath: WritableKeyPath<KeyChord, Bool>, _ chord: KeyChord?) -> some View {
        let selected = chord?[keyPath: keyPath] ?? false
        return Button {
            guard var value = chord else { return }
            value[keyPath: keyPath].toggle(); set(value)
        } label: {
            Text(symbol).font(.system(size: 16, weight: .medium)).frame(width: 29, height: 26)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).disabled(chord == nil).help(name)
            .accessibilityLabel(name).accessibilityValue(selected ? tr("已选", "Selected") : tr("未选", "Not selected"))
    }
    /// The next key the keyboard sends becomes this control's combination. A lone Escape is the way out, never a combination.
    private func record() {
        recording = true
        KeyboardInputSource.capture = { pressed in
            stop()
            if pressed != KeyChord(code: 53) { set(pressed) }
        }
    }
    private func stop() {
        guard recording else { return }
        recording = false; KeyboardInputSource.capture = nil
    }
    private func set(_ chord: KeyChord?) {
        var layout = KeyboardLayout.current
        layout.chords[control.rawValue] = chord
        layout.save(); model.refresh()
    }
}

private struct InputInspector: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.selected.symbol).font(.system(size: 23, weight: .medium))
                    .frame(width: 42, height: 42).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selected.title).font(.system(size: 18, weight: .semibold))
                    Text(tr("按键设置", "Input settings")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Text(tr("默认布局：", "Preset: ") + model.selected.detail).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.template.id == .keyboard { KeyboardChordEditor(model: model, control: model.selected.control) }
            VStack(alignment: .leading, spacing: 7) {
                Text(tr("作用场景", "Context")).font(.system(size: 13, weight: .semibold))
                Picker(tr("作用场景", "Context"), selection: $model.scope) {
                    ForEach(GestureScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden()
            }
            Divider()
            HStack { Text(tr("触发方式", "Gestures")).font(.system(size: 13, weight: .semibold)); Spacer(); Text(tr("点击更改动作", "Click to assign")).font(.system(size: 12)).foregroundStyle(.tertiary) }
            if model.config.action(model.scope, model.selected.control, .hold) != .none {
                Text(tr("按住动作优先生效；单击、双击和长按配置会保留，暂不触发。", "Hold takes priority. Tap and long-press bindings are kept but inactive while Hold is assigned."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if model.config.live(model.scope, model.selected.control, model.selected.gestures) != model.selected.gestures {
                Text(tr("「按下即触发」生效时，这个键像方向键一样立刻动作并连发；单击、双击和长按配置会保留，暂不触发。", "While “Press at once” is assigned the button acts like an arrow key. Tap and long-press bindings are kept but inactive."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.selected.gestures, id: \.self) { kind in
                        let action = model.config.action(model.scope, model.selected.control, kind)
                        Button { model.editRequest = GestureEditRequest(control: model.selected.control, kind: kind) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: gestureSymbol(kind)).font(.system(size: 16)).frame(width: 24)
                                    .foregroundStyle(action == .none ? Color.secondary : Color.accentColor)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.gestureTitle(kind)).font(.system(size: 13, weight: .semibold))
                                    Text(action.label).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "ellipsis").foregroundStyle(.tertiary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(action == .none ? Color.primary.opacity(0.025) : Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.055)))
                        }.buttonStyle(.plain).accessibilityLabel("\(model.gestureTitle(kind)): \(action.label)")
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: model.resetControl) { Label(tr("恢复此按键默认配置", "Reset this input"), systemImage: "arrow.counterclockwise") }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight: .infinity, alignment: .topLeading)
            .settingsGlass(cornerRadius: 12, prominent: true)
    }
    private func gestureSymbol(_ kind: GestureKind) -> String {
        switch kind {
        case .single: return "circle.fill"
        case .double: return "ellipsis"
        case .long: return "clock"
        case .hold: return "hand.point.up.left"
        case .rotate: return "arrow.left.arrow.right"
        case .heldLeft: return "arrow.uturn.backward"
        case .heldRight: return "arrow.uturn.forward"
        }
    }
}
