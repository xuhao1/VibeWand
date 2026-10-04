import AppKit
import ApplicationServices
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runtime = BridgeRuntime()
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var settings: SettingsController?
    private var showItem: NSMenuItem!
    private var connectionItem: NSMenuItem!
    private var signalSources: [DispatchSourceSignal] = []
    private var diagnosticsURL: URL?
    private var settingsCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Self.dockIcon()
        overlay = OverlayController(onOpenSettings: { [weak self] in self?.openSettings() }, onHide: { [weak self] in self?.hideOverlay() }) { [weak self] control, phase in
            guard let self, self.runtime.demo else { return }
            self.runtime.handle(control, phase: phase)
        }
        overlay.setScale(UserDefaults.standard.object(forKey: "hudScale") as? Double ?? 1)
        overlay.setOpacity(UserDefaults.standard.object(forKey: "hudOpacity") as? Double ?? 0.95)
        overlay.setExpanded(UserDefaults.standard.bool(forKey: "hudExpanded"))
        runtime.adapter.compatibilityPicker = UserDefaults.standard.bool(forKey: "compatibilityPicker")
        runtime.adapter.forceEditing = UserDefaults.standard.bool(forKey: "forceEditing")
        diagnosticsURL = argumentURL("--diagnostics-path")
        runtime.onSnapshot = { [weak self] state in
            guard let self else { return }
            self.overlay.update(state)
            self.settings?.update(state)
            self.connectionItem?.title = state.captureOnly ? L10n.tr("仅采集物理事件", "Input capture only") : state.demo ? L10n.tr("演示模式", "Demo mode") : state.connected ? L10n.tr("设备已连接", "Device connected") : L10n.tr("等待设备连接", "Waiting for device")
            if let url = self.diagnosticsURL { try? self.runtime.exportSnapshot(url) }
        }
        runtime.onSettingsChanged = { [weak self] in self?.updateMenu(); self?.settings?.refresh() }
        runtime.onInternalAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleOverlay: self.toggleOverlay()
            case .openSettings: self.openSettings()
            case .toggleGuide:
                let expanded = !UserDefaults.standard.bool(forKey: "hudExpanded")
                UserDefaults.standard.set(expanded, forKey: "hudExpanded")
                self.overlay.setExpanded(expanded); self.settings?.refresh()
            default: break
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.toolTip = "VibeWand"
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: L10n.languageDidChange, object: nil)
        overlay.setVisible(UserDefaults.standard.object(forKey: "hudVisible") as? Bool ?? true)
        runtime.captureOnly = CommandLine.arguments.contains("--capture-only")
        runtime.start(demo: CommandLine.arguments.contains("--demo") || (!runtime.adapter.trusted && !runtime.captureOnly))
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }; source.resume(); signalSources.append(source)
        }
        updateMenu()
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if CommandLine.arguments.contains("--render-dark") {
            presentSettings()
            settings?.window?.appearance = NSAppearance(named: .darkAqua)
        }
        if let url = argumentURL("--render-overlay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in _ = self?.overlay.renderPNG(to: url) }
        }
        if let url = argumentURL("--render-settings") {
            let index = CommandLine.arguments.firstIndex(of: "--render-section")
            let section = index.flatMap { CommandLine.arguments.indices.contains($0 + 1) ? Int(CommandLine.arguments[$0 + 1]) : nil } ?? 1
            presentSettings(tab: section)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in _ = self?.settings?.renderPNG(to: url) }
        }
        if let url = argumentURL("--render-audit") {
            presentSettings()
            Task { [weak self] in
                do { try await self?.settings?.renderAudit(to: url) }
                catch { NSLog("Settings audit export failed: %@", error.localizedDescription) }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let settingsCloseObserver { NotificationCenter.default.removeObserver(settingsCloseObserver) }
        runtime.stop()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentSettings()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func argumentURL(_ name: String) -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.count > index + 1 else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
    private func buildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "VibeWand", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        connectionItem = NSMenuItem(title: L10n.tr("等待设备连接", "Waiting for device"), action: nil, keyEquivalent: ""); connectionItem.isEnabled = false; menu.addItem(connectionItem)
        menu.addItem(.separator())
        showItem = item(L10n.tr("显示悬浮面板", "Show overlay"), #selector(toggleOverlay), in: menu)
        item(L10n.tr("设置…", "Settings…"), #selector(openSettings), key: ",", in: menu)
        item(L10n.tr("关于 VibeWand", "About VibeWand"), #selector(openAbout), in: menu)
        item(L10n.tr("重新连接设备", "Reconnect device"), #selector(reconnectDevice), in: menu)
        menu.addItem(.separator())
        item(L10n.tr("退出 VibeWand", "Quit VibeWand"), #selector(quit), key: "q", in: menu)
        statusItem.menu = menu

        let mainMenu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu(title: "VibeWand")
        item(L10n.tr("关于 VibeWand", "About VibeWand"), #selector(openAbout), in: appMenu)
        item(L10n.tr("设置…", "Settings…"), #selector(openSettings), key: ",", in: appMenu)
        appMenu.addItem(.separator()); item(L10n.tr("退出 VibeWand", "Quit VibeWand"), #selector(quit), key: "q", in: appMenu)
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: L10n.tr("编辑", "Edit"))
        for (title, action, key) in [(L10n.tr("撤销", "Undo"), Selector(("undo:")), "z"), (L10n.tr("剪切", "Cut"), #selector(NSText.cut(_:)), "x"), (L10n.tr("复制", "Copy"), #selector(NSText.copy(_:)), "c"), (L10n.tr("粘贴", "Paste"), #selector(NSText.paste(_:)), "v"), (L10n.tr("全选", "Select All"), #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
    }
    @discardableResult private func item(_ title: String, _ action: Selector, key: String = "", in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    private func updateMenu() { showItem?.state = overlay.isVisible ? .on : .off }
    @objc private func toggleOverlay() {
        overlay.setVisible(!overlay.isVisible); UserDefaults.standard.set(overlay.isVisible, forKey: "hudVisible")
        updateMenu(); settings?.refresh()
    }
    private func hideOverlay() {
        overlay.setVisible(false)
        UserDefaults.standard.set(false, forKey: "hudVisible")
        updateMenu(); settings?.refresh()
    }
    @objc private func reconnectDevice() { runtime.reconnectDevice() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func languageChanged() { buildMenu(); updateMenu(); settings?.refresh() }
    @objc private func openAbout() { presentSettings(tab: 5) }
    @objc private func openSettings() { presentSettings() }
    private func presentSettings(tab: Int? = nil) {
        if settings == nil {
            settings = SettingsController(runtime: runtime, overlay: overlay)
            settingsCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: settings?.window, queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
        }
        // Keep an open (including minimized) settings window easy to find in the Dock.
        NSApp.setActivationPolicy(.regular)
        settings?.window?.deminiaturize(nil)
        settings?.present(tab: tab)
    }
    private static func dockIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        // Support direct SwiftPM runs as well as the packaged application.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: root.appendingPathComponent("assets/app-icon/AppIcon.png"))
    }
}

@main
struct VibeWandMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
