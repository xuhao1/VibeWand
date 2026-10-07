import AppKit
import ImageIO

/// Design-space geometry is shared by artwork, highlights, and demo hit testing.
enum OverlayLayout {
    static func size(for template: DeviceTemplateID, expanded: Bool) -> NSSize {
        switch template {
        case .vibeKey: return NSSize(width: expanded ? 380 : 320, height: expanded ? 402 : 378)
        case .dualSense: return NSSize(width: expanded ? 520 : 460, height: expanded ? 480 : 448)
        case .xiaomiRemote: return NSSize(width: expanded ? 410 : 350, height: expanded ? 442 : 412)
        case .keyboard: return NSSize(width: expanded ? 410 : 350, height: expanded ? 402 : 378)
        }
    }
    /// The controls the keyboard layout lists, one key cap to a row, with the two directions sharing one.
    static let keyboardRows: [[DeviceControl]] = [[.voice], [.dial], [.left, .right], [.ok], [.escape]]

    static func deviceRect(for template: DeviceTemplateID, expanded: Bool) -> NSRect {
        switch template {
        case .vibeKey:
            // This asset alone is cropped to its opaque body, preserving its dial animation.
            return NSRect(x: 24, y: 58, width: 62, height: 235.2)
        case .dualSense:
            return NSRect(x: expanded ? 26 : 24, y: 112, width: expanded ? 370 : 330, height: expanded ? 370 / 1.5 : 220)
        case .xiaomiRemote:
            return NSRect(x: 14, y: 68, width: 145.333333, height: 218)
        case .keyboard:
            // A column of key caps, one beside each caption.
            return NSRect(x: 16, y: 67, width: 150, height: 208)
        }
    }
    /// Where a control's key cap is drawn on the keyboard layout.
    static func keyCap(_ control: DeviceControl, expanded: Bool) -> NSRect? {
        guard let row = keyboardRows.firstIndex(where: { $0.contains(control) }) else { return nil }
        // The caps stop short of the column's edge, where each one's leader ends.
        let column = deviceRect(for: .keyboard, expanded: expanded), pair = keyboardRows[row]
        let width = pair.count == 1 ? column.width - 8 : (column.width - 14) / 2
        return NSRect(x: column.minX + CGFloat(pair.firstIndex(of: control) ?? 0) * (width + 6), y: column.minY + CGFloat(row) * 44, width: width, height: 32)
    }

    static func controlCenter(_ control: DeviceControl, template: DeviceTemplateID, expanded: Bool) -> NSPoint? {
        let rect = deviceRect(for: template, expanded: expanded)
        if template == .vibeKey {
            let y: CGFloat
            switch control {
            case .dial, .left, .right, .settings: y = 0.293
            case .voice: y = 0.512
            case .ok: y = 0.675
            case .escape, .forceEscape: y = 0.843
            default: return nil
            }
            return NSPoint(x: rect.midX - rect.width * 0.015, y: rect.minY + rect.height * y)
        }
        // A row's leader ends beside its last cap, so that the two directions share one and none crosses a cap.
        if template == .keyboard {
            let row = keyboardRows.first { $0.contains(control) }?.last
            return row.flatMap { keyCap($0, expanded: expanded) }.map { NSPoint(x: $0.maxX + 3, y: $0.midY) }
        }
        guard let point = DeviceArtwork.forTemplate(template).hotspots[control] else { return nil }
        return NSPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}

/// An accessory window that stays out of the target application's focus chain.
@MainActor
final class OverlayController {
    private let panel: CompanionPanel
    private let view: CompanionView
    private let host: SpeechOverlayHost
    private(set) var displayMode: OverlayDisplayMode = .full
    private var scale = 1.0
    private var expanded = false
    private let positionKey = "VibeWandBridge.overlayOrigin"
    private let anchorKey = "VibeWandBridge.overlayAnchor"
    private let belowKey = "VibeWandBridge.overlayDeviceBelow"
    /// Top-right corner of the speech bar, in screen coordinates. Every size
    /// change is laid out from this point, so the bar and its buttons stay
    /// under the pointer when the panel expands, collapses or changes device.
    private var anchor = NSPoint.zero
    private var deviceBelow = false
    /// The user keeps the overlay hidden; a command brings it out until it has ended.
    private var raisedForCommand = false
    var isVisible: Bool { panel.isVisible && !raisedForCommand }

    static func makeLivePreview() -> NSView {
        let view = CompanionView(isPreview: true, onOpenSettings: {}, onHide: {}, onControl: { _, _ in })
        return SpeechOverlayHost(fullView: view, isPreview: true, onOpenSettings: {}, onHide: {}, onToggleStyle: {})
    }
    static func updateLivePreview(_ preview: NSView, snapshot: HUDSnapshot, expanded: Bool, mode: OverlayDisplayMode = .full) {
        guard let host = preview as? SpeechOverlayHost, let view = host.fullView as? CompanionView else { return }
        if view.expanded != expanded { view.expanded = expanded }
        view.update(snapshot)
        host.update(snapshot, mode: mode, expanded: expanded)
    }

    /// Writes the last dictation into the text field in front again.
    var onReinsert: (() -> Void)?
    init(onOpenSettings: @escaping () -> Void = {}, onHide: @escaping () -> Void = {}, onToggleStyle: @escaping () -> Void = {}, onControl: @escaping (DeviceControl, InputPhase) -> Void) {
        view = CompanionView(onOpenSettings: onOpenSettings, onHide: onHide, onControl: onControl)
        host = SpeechOverlayHost(fullView: view, onOpenSettings: onOpenSettings, onHide: onHide, onToggleStyle: onToggleStyle)
        panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: CompanionView.compactSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = L10n.tr("VibeWand 悬浮面板", "VibeWand Overlay")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = host
        host.autoresizingMask = [.width, .height]
        host.onToggleMode = { [weak self] in
            guard let self else { return }; self.setDisplayMode(self.displayMode == .full ? .compact : .full)
        }
        view.onDragCompleted = { [weak self] in self?.captureAnchor() }
        host.onDragCompleted = { [weak self] in self?.captureAnchor() }
        host.onReinsert = { [weak self] in self?.onReinsert?() }
        host.update(host.snapshot, mode: displayMode, expanded: expanded)
        let defaults = UserDefaults.standard
        deviceBelow = defaults.bool(forKey: belowKey)
        if let saved = defaults.string(forKey: anchorKey) {
            anchor = NSPointFromString(saved); resize()
        } else if let saved = defaults.string(forKey: positionKey) {
            // Earlier versions stored the panel origin with the bar at the bottom.
            let size = currentSize, origin = NSPointFromString(saved)
            anchor = NSPoint(x: origin.x + size.width, y: origin.y + barHeight); resize()
        } else { resetPosition() }
    }

    func update(_ state: HUDSnapshot) {
        panel.title = L10n.tr("VibeWand 悬浮面板", "VibeWand Overlay")
        let changedTemplate = view.deviceTemplate != state.deviceTemplate
            || SpeechOverlayLayout.barHeight(voice: host.snapshot.voice, command: host.snapshot.command)
                != SpeechOverlayLayout.barHeight(voice: state.voice, command: state.command)
        view.update(state)
        host.update(state, mode: displayMode, expanded: expanded)
        // Resizing never orders the panel front, so switching a template keeps a hidden HUD hidden.
        if changedTemplate { resize() }
    }
    /// What a command is doing, and how to stop it, must be on screen while it runs,
    /// even when the user keeps the overlay hidden. It goes away again with the command.
    func showForCommand(_ active: Bool) {
        if active, !panel.isVisible { raisedForCommand = true; panel.orderFrontRegardless() }
        else if !active, raisedForCommand { raisedForCommand = false; panel.orderOut(nil) }
    }
    func setVisible(_ visible: Bool) {
        raisedForCommand = false
        if visible { panel.orderFrontRegardless() }
        else { view.cancelMousePress(); panel.orderOut(nil) }
    }
    func setScale(_ value: Double) { scale = min(1.8, max(0.65, value)); resize() }
    func setOpacity(_ value: Double) { panel.alphaValue = min(1, max(0.35, value)) }
    func setExpanded(_ value: Bool) { expanded = value; view.expanded = value; host.update(host.snapshot, mode: displayMode, expanded: value); resize() }
    func setDisplayMode(_ mode: OverlayDisplayMode) {
        let changed = displayMode != mode
        displayMode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "hudDisplayMode")
        view.cancelMousePress(); host.update(host.snapshot, mode: mode, expanded: expanded); resize(reorient: changed && mode == .full)
    }

    func resetPosition() {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        deviceBelow = false
        anchor = NSPoint(x: screen.maxX - 28, y: screen.minY + 34 + barHeight)
        resize()
    }

    /// Render our own accessory for documentation without capturing other windows.
    func previewImage(appearance: NSAppearance? = nil) -> NSImage? {
        guard let bitmap = bitmap(appearance: appearance) else { return nil }
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    @discardableResult
    func renderPNG(to url: URL) -> Bool {
        guard let bitmap = bitmap() else { return false }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); return true } catch { return false }
    }

    private func bitmap(appearance: NSAppearance? = nil) -> NSBitmapImageRep? {
        let previousAppearance = view.appearance
        let previousHostAppearance = host.appearance
        if let appearance { view.appearance = appearance }
        if let appearance { host.appearance = appearance }
        view.exporting = true
        host.exporting = true
        defer {
            view.exporting = false
            host.exporting = false
            view.appearance = previousAppearance
            host.appearance = previousHostAppearance
        }
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        // Offscreen rendering has no WindowServer backdrop. Resolve semantic colors
        // against the HUD (or requesting settings window), never an ambient context.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return bitmap
    }

    private var currentSize: NSSize {
        let size = SpeechOverlayLayout.size(template: view.deviceTemplate, expanded: expanded, mode: displayMode, voice: host.snapshot.voice,
                                            command: host.snapshot.command)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }
    private var barHeight: CGFloat { SpeechOverlayLayout.barHeight(voice: host.snapshot.voice, command: host.snapshot.command) * scale }

    /// `reorient` re-decides, when expanding, whether the device view has room above the bar.
    private func resize(reorient: Bool = false) {
        let size = currentSize, bar = barHeight
        var frame = NSRect(x: anchor.x - size.width, y: anchor.y - bar, width: size.width, height: size.height)
        if displayMode == .full {
            let device = size.height - bar
            if reorient {
                let visible = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.x - 1, y: anchor.y - 1)) } ?? NSScreen.main)?.visibleFrame
                if let visible {
                    let fitsAbove = anchor.y + device <= visible.maxY, fitsBelow = anchor.y - bar - device >= visible.minY
                    deviceBelow = !fitsAbove && fitsBelow
                }
            }
            if deviceBelow { frame.origin.y = anchor.y - bar - device }
        }
        host.deviceBelow = deviceBelow && displayMode == .full
        panel.setFrame(frame, display: true)
        keepOnScreen()
        captureAnchor()
    }
    /// Reads the anchor back from the window, after a drag or a screen clamp.
    private func captureAnchor() {
        let frame = panel.frame
        let below = deviceBelow && displayMode == .full
        anchor = NSPoint(x: frame.maxX, y: displayMode == .compact || below ? frame.maxY : frame.minY + barHeight)
        let defaults = UserDefaults.standard
        defaults.set(NSStringFromPoint(anchor), forKey: anchorKey)
        defaults.set(deviceBelow, forKey: belowKey)
        defaults.set(NSStringFromPoint(frame.origin), forKey: positionKey)
    }
    private func keepOnScreen() {
        let screen = NSScreen.screens.max { first, second in
            let a = first.visibleFrame.intersection(panel.frame)
            let b = second.visibleFrame.intersection(panel.frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? NSScreen.main
        guard let screen else { return }
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - panel.frame.width)), y: min(max(panel.frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - panel.frame.height))))
    }
}

@MainActor
private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CompanionView: NSView {
    static let compactSize = OverlayLayout.size(for: .vibeKey, expanded: false)
    var deviceTemplate: DeviceTemplateID { snapshot.deviceTemplate }
    var onDragCompleted: (() -> Void)?
    var expanded = false { didSet { needsLayout = true; redraw() } }
    var exporting = false {
        didSet {
            material.exporting = exporting
            redraw()
        }
    }
    private let onControl: (DeviceControl, InputPhase) -> Void
    private let onOpenSettings: () -> Void
    private let onHide: () -> Void
    private let material: CompanionBackdrop
    private let content = GlassControlContent()
    private let isPreview: Bool
    private var deviceDrawing: CompanionDrawing?
    private let settingsButton = CompanionSettingsButton()
    private let hideButton = CompanionSettingsButton()
    private var drawing: CompanionDrawing?
    private var snapshot = HUDSnapshot()
    private var deviceImage: NSImage?
    private var angle: CGFloat = 0
    private var targetAngle: CGFloat = 0
    private var direction = 1
    private var rotationUntil: TimeInterval = 0
    private var pulses: [DeviceControl: TimeInterval] = [:]
    private var animationTimer: Timer?
    private var mouseControl: DeviceControl?
    private var scrollAccumulator: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var designSize: NSSize { OverlayLayout.size(for: deviceTemplate, expanded: expanded) }
    private var factor: CGFloat { bounds.width / designSize.width }
    private var deviceRect: NSRect { OverlayLayout.deviceRect(for: deviceTemplate, expanded: expanded) }
    private var dialCenter: NSPoint { center(.dial) }
    private var dialRadius: CGFloat { deviceRect.width * 0.435 }
    private var keyRadius: CGFloat { deviceRect.width * 0.26 }

    init(isPreview: Bool = false, onOpenSettings: @escaping () -> Void, onHide: @escaping () -> Void, onControl: @escaping (DeviceControl, InputPhase) -> Void) {
        self.isPreview = isPreview
        material = CompanionBackdrop()
        self.onOpenSettings = onOpenSettings
        self.onHide = onHide
        self.onControl = onControl
        super.init(frame: NSRect(origin: .zero, size: Self.compactSize))
        wantsLayer = true
        layer?.cornerRadius = 26
        // Native glass owns its rounded silhouette; clipping its superview cuts
        // off the optical halo at the rim and makes the lens look like a flat card.
        layer?.masksToBounds = false
        material.frame = bounds
        material.autoresizingMask = [.width, .height]
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        material.setContent(content)
        addSubview(material)
        let deviceDrawing = CompanionDrawing(owner: self, deviceLayer: true)
        self.deviceDrawing = deviceDrawing
        deviceDrawing.frame = bounds; deviceDrawing.autoresizingMask = [.width, .height]
        content.addSubview(deviceDrawing)
        let drawing = CompanionDrawing(owner: self, deviceLayer: false)
        self.drawing = drawing
        drawing.frame = bounds
        drawing.autoresizingMask = [.width, .height]
        content.addSubview(drawing)
        for button in [settingsButton, hideButton] {
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.bezelStyle = .recessed
            button.contentTintColor = .secondaryLabelColor
            button.target = self
            content.addSubview(button)
            // The speech bar carries these controls in both modes.
            button.isHidden = true
        }
        settingsButton.action = #selector(openSettings)
        hideButton.action = #selector(hideOverlay)
        updateSettingsButton()
        deviceImage = Self.loadDeviceImage()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        toolTip = L10n.tr("拖动移动。演示模式：点击按键、滚动旋钮、按住旋钮打开模型设置。", "Drag to move. In demo mode, press buttons, scroll the dial, or hold the dial for models.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { animationTimer?.invalidate() }

    override func layout() {
        super.layout()
        material.frame = bounds; content.frame = bounds
        deviceDrawing?.frame = bounds; drawing?.frame = bounds
        // Keep both controls easy to hit even when the user shrinks the HUD.
        let side = max(24, 24 * factor), gap = max(2, 2 * factor)
        let inset = max(6, 10 * factor), y = max(3, 8 * factor)
        hideButton.frame = NSRect(x: bounds.width - inset - side, y: y, width: side, height: side)
        settingsButton.frame = NSRect(x: hideButton.frame.minX - gap - side, y: y, width: side, height: side)
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: max(11, 12 * factor), weight: .medium)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration)
        hideButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration)
        updateGlassShape()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        material.needsDisplay = true
        for button in [settingsButton, hideButton] {
            button.contentTintColor = .secondaryLabelColor
            button.needsDisplay = true
        }
        needsLayout = true
        redraw()
    }

    private func updateSettingsButton() {
        let title = L10n.tr("打开 VibeWand 设置", "Open VibeWand settings")
        settingsButton.toolTip = title
        settingsButton.setAccessibilityLabel(title)
        let hideTitle = L10n.tr("隐藏悬浮面板", "Hide overlay")
        hideButton.toolTip = hideTitle
        hideButton.setAccessibilityLabel(hideTitle)
        needsLayout = true
    }

    @objc private func openSettings() {
        cancelMousePress()
        onOpenSettings()
    }

    @objc private func hideOverlay() {
        cancelMousePress()
        onHide()
    }

    func update(_ state: HUDSnapshot) {
        let changedTemplate = snapshot.deviceTemplate != state.deviceTemplate
        if changedTemplate || (snapshot.demo && !state.demo) { cancelMousePress() }
        if changedTemplate {
            animationTimer?.invalidate()
            animationTimer = nil
            angle = 0
            targetAngle = 0
            rotationUntil = 0
            pulses.removeAll()
            scrollAccumulator = 0
            deviceImage = state.deviceTemplate == .vibeKey ? Self.loadDeviceImage() : DeviceArtwork.forTemplate(state.deviceTemplate).image
            needsLayout = true
        }
        let delta = changedTemplate ? 0 : state.rotation - snapshot.rotation
        if delta != 0 && state.deviceTemplate == .vibeKey {
            direction = delta > 0 ? 1 : -1
            targetAngle += CGFloat(max(-8, min(8, delta))) * .pi / 9
            rotationUntil = Date.timeIntervalSinceReferenceDate + 0.32
            startAnimation()
        }
        for control in state.pressed.subtracting(changedTemplate ? [] : snapshot.pressed) { flash(control) }
        snapshot = state
        updateSettingsButton()
        if deviceImage == nil { deviceImage = deviceTemplate == .vibeKey ? Self.loadDeviceImage() : DeviceArtwork.forTemplate(deviceTemplate).image }
        let demoHint = deviceTemplate == .vibeKey
            ? L10n.tr("拖动移动。演示模式可点击、长按按键或滚动旋钮。", "Drag to move. In demo mode, press or hold buttons and scroll the dial.")
            : L10n.tr("拖动移动。演示模式可点击或长按实际按键。", "Drag to move. In demo mode, click or hold the physical controls.")
        let mapping = deviceTemplate.template.controls.map { "\($0.title): \(actionCaption($0.control))" }.joined(separator: "\n")
        toolTip = snapshot.status + "\n" + demoHint + "\n\n" + mapping
        setAccessibilityLabel("VibeWand，\(deviceTemplate.template.title)，\(state.captureOnly ? L10n.tr("采集", "Capture") : state.demo ? L10n.tr("演示", "Demo") : state.connected ? L10n.tr("实时", "Live") : L10n.tr("离线", "Offline"))，\(state.mode)，\(state.action)")
        redraw()
    }

    fileprivate func drawContents(deviceLayer: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scaleX(by: factor, yBy: factor)
        transform.concat()
        if deviceLayer {
            if exporting || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                OverlayGlassSkin.panel(in: NSRect(origin: .zero, size: designSize), dark: darkAppearance, exporting: exporting, optics: false)
            }
            drawDevice()
        } else {
            if exporting { OverlayGlassSkin.rim(in: NSRect(origin: .zero, size: designSize), dark: darkAppearance, optics: false) }
            drawHeader(); drawGraphicalGuide(); drawFooter()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHeader() {
        let buttonsX = designSize.width - 12
        text("VibeWand", rect: NSRect(x: 17, y: 15, width: 89, height: 18), size: 12, weight: .semibold, color: .labelColor)
        if designSize.width >= 300 {
            text(deviceTemplate.template.title, rect: NSRect(x: 112, y: 16, width: max(0, buttonsX - 180), height: 17), size: 11.5, weight: .medium, color: .labelColor, alignment: .center)
        }
        let showStatusLabel = buttonsX >= 132
        let liveX = buttonsX - (showStatusLabel ? 59 : 10)
        let liveColor: NSColor = snapshot.captureOnly ? .systemOrange : snapshot.demo ? .systemBlue : snapshot.connected ? .systemGreen : .secondaryLabelColor
        liveColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: liveX, y: 22, width: 5, height: 5)).fill()
        if showStatusLabel {
            text(snapshot.captureOnly ? L10n.tr("采集", "INPUT") : snapshot.demo ? L10n.tr("演示", "DEMO") : snapshot.connected ? L10n.tr("已连接", "LIVE") : L10n.tr("离线", "OFF"), rect: NSRect(x: liveX + 10, y: 17, width: 44, height: 15), size: 10, weight: .medium, color: .secondaryLabelColor)
        }
    }

    /// The keyboard layout has no photograph: each control is a key cap carrying the combination that stands for it.
    private func drawKeyCaps() {
        let layout = KeyboardLayout.current
        for control in KeyboardLayout.controls {
            guard let rect = OverlayLayout.keyCap(control, expanded: expanded) else { continue }
            let cap = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            (isActive(control) ? NSColor.systemGreen.withAlphaComponent(0.5) : NSColor.white.withAlphaComponent(darkAppearance ? 0.10 : 0.55)).setFill()
            cap.fill()
            NSColor.labelColor.withAlphaComponent(0.22).setStroke(); cap.lineWidth = 0.8; cap.stroke()
            let label = layout.label(control)
            text(label.isEmpty ? "—" : label, rect: NSRect(x: rect.minX + 4, y: rect.midY - 8, width: rect.width - 8, height: 17),
                 size: label.count > 9 ? 10.5 : 12, weight: .semibold, color: .labelColor, alignment: .center)
        }
    }

    private func drawDevice() {
        if deviceTemplate == .keyboard { drawKeyCaps(); return }
        if let image = deviceImage {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(darkAppearance ? 0.28 : 0.17)
            shadow.shadowBlurRadius = 12; shadow.shadowOffset = NSSize(width: 0, height: 5); shadow.set()
            image.draw(in: deviceRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
            NSImage(systemSymbolName: deviceTemplate == .dualSense ? "gamecontroller" : deviceTemplate == .vibeKey ? "dial.medium" : "appletvremote.gen4", accessibilityDescription: L10n.tr("正在加载设备图片", "Device artwork loading"))?.withSymbolConfiguration(config)?.draw(in: NSRect(x: deviceRect.midX - 22, y: 104, width: 44, height: 44), from: .zero, operation: .sourceOver, fraction: 0.35, respectFlipped: true, hints: nil)
        }
        if deviceTemplate != .vibeKey {
            drawPhysicalHighlights()
            return
        }
        for control in [DeviceControl.dial, .voice, .ok, .escape] {
            let active = isActive(control) || (control == .dial && isActive(.settings)) || (control == .escape && isActive(.forceEscape))
            guard active else { continue }
            let point = center(control)
            let radius = control == .dial ? dialRadius : keyRadius
            let path = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            NSColor.black.withAlphaComponent(0.10).setFill()
            path.fill()
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor.white.withAlphaComponent(0.65)
            glow.shadowBlurRadius = 3
            glow.set()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.3
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let inner = NSBezierPath(ovalIn: NSRect(x: point.x - radius + 1, y: point.y - radius + 1.7, width: radius * 2 - 2, height: radius * 2 - 2))
            NSColor.black.withAlphaComponent(0.12).setStroke()
            inner.lineWidth = 0.6
            inner.stroke()
        }
        let turning = Date.timeIntervalSinceReferenceDate < rotationUntil || isActive(.left) || isActive(.right)
        if turning { drawRotation() }
    }

    private func drawPhysicalHighlights() {
        for descriptor in deviceTemplate.template.controls where isActive(descriptor.control) {
            let control = descriptor.control
            let point = center(control)
            let radius: CGFloat = control.isStickDirection ? 6 : deviceTemplate == .dualSense ? 8.5 : 7
            let path = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 1.4
            path.stroke()
            if control.isStickDirection {
                let image = NSImage(systemSymbolName: descriptor.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold).applying(NSImage.SymbolConfiguration(paletteColors: [.white])))
                image?.draw(in: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }

    private func drawRotation() {
        let radius = dialRadius + 1.8
        let point = dialCenter
        let arc = NSBezierPath()
        let start = angle - .pi / 2
        for segment in 0...24 {
            let a = start + CGFloat(segment) / 24 * .pi * 0.48
            let p = NSPoint(x: point.x + cos(a) * radius, y: point.y + sin(a) * radius)
            if segment == 0 { arc.move(to: p) } else { arc.line(to: p) }
        }
        NSColor(white: 1, alpha: 0.92).setStroke()
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        arc.stroke()
        let clockwise = isActive(.right) || (!isActive(.left) && direction > 0)
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        let symbol = NSImage(systemSymbolName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration)
        let badge = NSBezierPath(ovalIn: NSRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22))
        NSColor.controlBackgroundColor.withAlphaComponent(0.94).setFill()
        badge.fill()
        symbol?.draw(in: NSRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13), from: .zero, operation: .sourceOver, fraction: 0.72, respectFlipped: true, hints: nil)
    }

    private var darkAppearance: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    private var footerRect: NSRect { NSRect(x: 16, y: designSize.height - 80, width: designSize.width - 32, height: 42) }
    private var gestureRect: NSRect { NSRect(x: 38, y: designSize.height - 30, width: designSize.width - 76, height: 22) }

    private struct Callout {
        var id: String
        var rect: NSRect
        var control: DeviceControl
        var symbol: String
        var caption: String
        var emphasized = false
        var fromBottom = false
        var secondary: DeviceControl? = nil
    }

    private func capsuleCaption(_ control: DeviceControl) -> String {
        guard let hint = HUDGuidance.primary(control, snapshot: snapshot) else { return L10n.tr("未分配", "Unassigned") }
        return hint.kind == .hold || hint.kind == .long || hint.kind == .double ? hint.title : hint.caption
    }

    private func callouts() -> [Callout] {
        func item(_ id: String, _ control: DeviceControl, _ rect: NSRect, _ symbol: String, fromBottom: Bool = false) -> Callout {
            let hint = HUDGuidance.primary(control, snapshot: snapshot)
            return Callout(id: id, rect: rect, control: control, symbol: symbol, caption: capsuleCaption(control),
                emphasized: hint?.action == .confirmCandidate || hint?.action == .confirmApplication,
                fromBottom: fromBottom)
        }
        if deviceTemplate == .dualSense {
            let right: CGFloat = expanded ? 380 : 334
            let width = designSize.width - right - 16
            let y: CGFloat = expanded ? 153 : 143
            let step: CGFloat = expanded ? 48 : 45
            var result = [.voice, .dial, .escape, .ok].enumerated().map { index, control in
                item(control.rawValue, control, NSRect(x: right - (index == 3 ? 8 : 0), y: y + step * CGFloat(index), width: width + (index == 3 ? 8 : 0), height: 31),
                     HUDGuidance.primary(control, snapshot: snapshot)?.action.symbol ?? "minus")
            }
            // Across the top, each shoulder pair shares a caption: the left one switches, the right one talks.
            func shoulders(_ first: DeviceControl, _ second: DeviceControl) -> String {
                [first, second].map { "\(HUDGuidance.shortName($0, template: .dualSense)) \(HUDGuidance.primary($0, snapshot: snapshot)?.caption ?? "—")" }.joined(separator: " · ")
            }
            let side: CGFloat = expanded ? 176 : 152
            let switching = NSRect(x: 16, y: 65, width: side, height: 31), talking = NSRect(x: designSize.width - 16 - side, y: 65, width: side, height: 31)
            result.append(Callout(id: "top.left", rect: switching, control: .l2, symbol: "", caption: shoulders(.l1, .l2), fromBottom: true, secondary: .l1))
            result.append(Callout(id: "top.right", rect: talking, control: .r2, symbol: "", caption: shoulders(.r1, .r2), fromBottom: true, secondary: .r1))
            result.append(Callout(id: "top.touch", rect: NSRect(x: switching.maxX + 4, y: 65, width: talking.minX - switching.maxX - 8, height: 31),
                control: .touchpad, symbol: "", caption: L10n.tr("触摸板 · 指针", "Touchpad · pointer"), fromBottom: true))
            for index in result.indices where !result[index].id.hasPrefix("top.") {
                let measured = (result[index].caption as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
                let desired = min(expanded ? 154 : 132, max(result[index].rect.width, ceil(measured) + 42))
                result[index].rect.origin.x = designSize.width - 16 - desired
                result[index].rect.size.width = desired
            }
            return result
        }
        let controls: [DeviceControl] = deviceTemplate == .vibeKey ? [.dial, .left, .voice, .ok, .escape]
            : deviceTemplate == .keyboard ? OverlayLayout.keyboardRows.map { $0[0] } : [.voice, .dial, .left, .escape, .ok]
        let x: CGFloat = deviceTemplate == .vibeKey ? 117 : 181
        return controls.enumerated().map { index, control in
            let descriptor = deviceTemplate.template.controls.first { $0.control == control }!
            var callout = item(control.rawValue, control, NSRect(x: x, y: 67 + CGFloat(index) * 44, width: designSize.width - x - 16, height: 32), descriptor.symbol)
            if control == .left {
                callout.caption = "\(HUDGuidance.primary(.left, snapshot: snapshot)?.caption ?? "—")/\(HUDGuidance.primary(.right, snapshot: snapshot)?.caption ?? "—")"
                callout.symbol = "arrow.left.arrow.right"; callout.secondary = .right
            }
            return callout
        }
    }

    private func updateGlassShape() {
        layer?.cornerRadius = 26 * factor; material.setCornerRadius(26 * factor)
    }

    private func drawFooter() {
        let rect = footerRect
        OverlayGlassSkin.pill(in: rect, dark: darkAppearance)
        symbol(snapshot.scope == .sessions ? "list.bullet" : snapshot.scope == .editing ? "text.cursor" : "rectangle.stack", rect: NSRect(x: rect.minX + 13, y: rect.minY + 13, width: 15, height: 15), color: .labelColor)
        text(snapshot.mode, rect: NSRect(x: rect.minX + 37, y: rect.minY + 13, width: rect.width * 0.43 - 36, height: 17), size: 11.5, weight: .semibold, color: .labelColor)
        let footerHint = footerControls()
        text(footerHint, rect: NSRect(x: rect.minX + rect.width * 0.43, y: rect.minY + 13, width: rect.width * 0.57 - 13, height: 17), size: 11, weight: .medium, color: .labelColor, alignment: .right)
        if !extraGestureText().isEmpty {
            OverlayGlassSkin.pill(in: gestureRect, dark: darkAppearance)
            text(extraGestureText(), rect: gestureRect.insetBy(dx: 12, dy: 4), size: 10, weight: .medium, color: .secondaryLabelColor, alignment: .center)
        }
    }

    private func footerControls() -> String {
        if snapshot.captureOnly || (!snapshot.connected && !snapshot.demo) { return HUDGuidance.nextStep(snapshot) }
        var confirm: String?, cancel: String?
        for item in deviceTemplate.template.controls {
            guard let hint = HUDGuidance.primary(item.control, snapshot: snapshot) else { continue }
            if [.confirmCandidate, .confirmApplication].contains(hint.action) { confirm = HUDGuidance.shortName(item.control, template: deviceTemplate) }
            if [.cancelPicker, .cancelApplication].contains(hint.action) { cancel = HUDGuidance.shortName(item.control, template: deviceTemplate) }
        }
        if let confirm, let cancel { return L10n.tr("\(confirm) 确认 · \(cancel) 返回", "\(confirm) Confirm · \(cancel) Back") }
        return HUDGuidance.nextStep(snapshot)
    }

    private func actionCaption(_ control: DeviceControl) -> String {
        snapshot.controlActions[control] ?? L10n.tr("未分配", "Unassigned")
    }

    private func drawGraphicalGuide() {
        for callout in callouts() {
            let start = callout.fromBottom ? NSPoint(x: callout.rect.midX, y: callout.rect.maxY + 2) : NSPoint(x: callout.rect.minX - 3, y: callout.rect.midY)
            drawLeader(from: start, to: center(callout.control), control: callout.control, emphasized: callout.emphasized)
            if let secondary = callout.secondary { drawLeader(from: start, to: center(secondary), control: secondary, emphasized: false) }
            OverlayGlassSkin.pill(in: callout.rect, dark: darkAppearance, emphasized: callout.emphasized || isActive(callout.control))
            let color: NSColor = callout.emphasized ? darkAppearance ? .init(srgbRed: 0.67, green: 0.84, blue: 1, alpha: 1) : .systemBlue : .labelColor
            let inset: CGFloat = callout.symbol.isEmpty ? 10 : 33
            if !callout.symbol.isEmpty { symbol(callout.symbol, rect: NSRect(x: callout.rect.minX + 11, y: callout.rect.midY - 7, width: 15, height: 15), color: color) }
            text(callout.caption, rect: NSRect(x: callout.rect.minX + inset, y: callout.rect.midY - 7, width: callout.rect.width - inset - 9, height: 17), size: callout.fromBottom ? 10 : 11, weight: .medium, color: color,
                 alignment: callout.fromBottom ? .center : .left)
        }
        if deviceTemplate == .dualSense {
            let rect = NSRect(x: 40, y: deviceRect.maxY + 4, width: deviceRect.width - 46, height: 25)
            OverlayGlassSkin.pill(in: rect, dark: darkAppearance)
            let moves = HUDGuidance.directions(snapshot.controlHints, up: .rightStickUp, down: .rightStickDown, left: .rightStickLeft, right: .rightStickRight)
            let caption = moves.isEmpty ? "—" : moves.joined(separator: " · ")
            symbol("r.joystick", rect: NSRect(x: rect.minX + 11, y: rect.minY + 6, width: 13, height: 13), color: .secondaryLabelColor)
            text(caption, rect: NSRect(x: rect.minX + 32, y: rect.minY + 5, width: rect.width - 42, height: 16), size: 10.5, weight: .medium, color: .secondaryLabelColor, alignment: .center)
        }
    }

    private func drawLeader(from start: NSPoint, to target: NSPoint, control: DeviceControl, emphasized: Bool) {
        let color = emphasized ? NSColor.systemBlue : darkAppearance ? NSColor.white.withAlphaComponent(0.64) : NSColor(srgbRed: 0.32, green: 0.38, blue: 0.48, alpha: 0.52)
        let path = NSBezierPath(); path.move(to: start)
        if start.y < deviceRect.minY {
            path.line(to: NSPoint(x: target.x, y: start.y)); path.line(to: target)
        } else if deviceTemplate == .keyboard {
            // A key cap sits right beside its caption.
            path.line(to: target)
        } else if deviceTemplate == .dualSense && control == .dial {
            path.line(to: NSPoint(x: target.x + 14, y: target.y + 8)); path.line(to: target)
        } else {
            path.curve(to: target, controlPoint1: NSPoint(x: start.x - 19, y: start.y), controlPoint2: NSPoint(x: target.x + 24, y: target.y))
        }
        color.setStroke(); path.lineWidth = emphasized ? 1.45 : 0.9; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        let radius: CGFloat = emphasized ? 2.3 : 1.7
        color.setFill(); NSBezierPath(ovalIn: NSRect(x: target.x - radius, y: target.y - radius, width: radius * 2, height: radius * 2)).fill()
        if emphasized { OverlayGlassSkin.focus(at: target, dark: darkAppearance) }
    }

    private func extraGestureText() -> String {
        let controls: [DeviceControl] = deviceTemplate == .dualSense ? [.r1, .options] : (expanded ? [.dial, .ok] : [.dial])
        let kinds: [GestureKind] = [.long, .double]
        let result = controls.flatMap { control in
            (snapshot.controlHints[control] ?? []).filter { kinds.contains($0.kind) || $0.action == .showControls }
                .map { "\(HUDGuidance.shortName(control, template: deviceTemplate)) \($0.action == .showControls ? $0.caption : $0.title)" }
        }
        return result.isEmpty ? snapshot.action : result.joined(separator: " · ")
    }

    private func symbol(_ name: String, rect: NSRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)?
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func center(_ control: DeviceControl) -> NSPoint {
        OverlayLayout.controlCenter(control, template: deviceTemplate, expanded: expanded)
            ?? NSPoint(x: deviceRect.midX, y: deviceRect.midY)
    }

    private func text(_ string: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func isActive(_ control: DeviceControl) -> Bool { snapshot.pressed.contains(control) || (pulses[control] ?? 0) > Date.timeIntervalSinceReferenceDate }
    private func flash(_ control: DeviceControl) { pulses[control] = Date.timeIntervalSinceReferenceDate + 0.18; startAnimation() }
    private func redraw() { drawing?.needsDisplay = true; deviceDrawing?.needsDisplay = true }
    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.animationStep() } }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func animationStep() {
        let now = Date.timeIntervalSinceReferenceDate
        angle += (targetAngle - angle) * 0.22
        pulses = pulses.filter { $0.value > now }
        redraw()
        if abs(angle - targetAngle) < 0.001 && pulses.isEmpty && now >= rotationUntil { angle = targetAngle; animationTimer?.invalidate(); animationTimer = nil }
    }

    func cancelMousePress() {
        if let control = mouseControl { mouseControl = nil; onControl(control, .cancel) }
    }
    override func mouseDown(with event: NSEvent) {
        guard !isPreview else { return }
        guard snapshot.demo, let control = hitControl(event) else { window?.performDrag(with: event); onDragCompleted?(); return }
        flash(control)
        if control == .left || control == .right || control.isStickDirection { onControl(control, .pulse) }
        else { mouseControl = control; onControl(control, .down) }
        redraw()
    }
    override func mouseUp(with event: NSEvent) { if let control = mouseControl { mouseControl = nil; onControl(control, .up) } }
    override func scrollWheel(with event: NSEvent) {
        guard !isPreview else { return }
        // Only VibeKey has a physical rotary control; scrolling must not emulate R1/R2 or a remote D-pad.
        guard snapshot.demo, deviceTemplate == .vibeKey else { return }
        let delta = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? -event.scrollingDeltaY : event.scrollingDeltaX
        scrollAccumulator += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 0.5
        guard abs(scrollAccumulator) >= threshold else { return }
        let control: DeviceControl = scrollAccumulator > 0 ? .right : .left
        scrollAccumulator = 0
        flash(control)
        onControl(control, .pulse)
    }
    private func hitControl(_ event: NSEvent) -> DeviceControl? {
        let raw = convert(event.locationInWindow, from: nil)
        let point = NSPoint(x: raw.x / factor, y: raw.y / factor)
        if deviceTemplate != .vibeKey {
            // Resolve overlapping hit areas by distance to the physical button center.
            let nearest = deviceTemplate.template.controls.compactMap { descriptor -> (DeviceControl, CGFloat)? in
                guard let center = OverlayLayout.controlCenter(descriptor.control, template: deviceTemplate, expanded: expanded) else { return nil }
                return (descriptor.control, hypot(point.x - center.x, point.y - center.y))
            }.min { $0.1 < $1.1 }
            guard let nearest, nearest.1 <= (nearest.0.isStickDirection ? 8 : 11) else { return nil }
            return nearest.0
        }
        let distance = hypot(point.x - dialCenter.x, point.y - dialCenter.y)
        if distance <= dialRadius + 3 {
            if event.modifierFlags.contains(.option) { return .settings }
            if distance < dialRadius * 0.67 { return .dial }
            return point.x < dialCenter.x ? .left : .right
        }
        for control in [DeviceControl.voice, .ok, .escape] {
            let c = center(control)
            if hypot(point.x - c.x, point.y - c.y) <= keyRadius + 3 { return control }
        }
        return nil
    }

    private static func loadDeviceImage() -> NSImage? {
        var urls: [URL] = []
        if let bundled = Bundle.main.url(forResource: "controller", withExtension: "png") { urls.append(bundled) }
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets/device/controller.png"))
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        urls.append(sourceRoot.appendingPathComponent("assets/device/controller.png"))
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            // Crop transparent margins on load; the source asset is never changed.
            let rep = NSBitmapImageRep(cgImage: original)
            var crop = CGRect(x: 0, y: 0, width: original.width, height: original.height)
            if rep.hasAlpha, rep.bitsPerSample == 8, let bytes = rep.bitmapData {
                var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
                let alpha = rep.bitmapFormat.contains(.alphaFirst) ? 0 : rep.samplesPerPixel - 1
                for y in 0..<rep.pixelsHigh {
                    for x in 0..<rep.pixelsWide where bytes[y * rep.bytesPerRow + x * rep.samplesPerPixel + alpha] > 40 {
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
                if maxX >= minX && maxY >= minY { crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1) }
            }
            guard let cropped = original.cropping(to: crop) else { continue }
            let image = NSImage(size: NSSize(width: cropped.width, height: cropped.height))
            image.addRepresentation(NSBitmapImageRep(cgImage: cropped))
            return image
        }
        return nil
    }
}

/// Keep AppKit's material in its own compositing layer below the original artwork.
@MainActor
private final class CompanionDrawing: NSView {
    private weak var owner: CompanionView?
    private let deviceLayer: Bool
    init(owner: CompanionView, deviceLayer: Bool) { self.owner = owner; self.deviceLayer = deviceLayer; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { owner?.drawContents(deviceLayer: deviceLayer) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The system's Liquid Glass.
/// It has no hit target: the HUD's drag handling and gear/hide buttons own input.
@MainActor
final class CompanionBackdrop: NSView {
    private var surface: NSGlassEffectView?
    private var observer: NSObjectProtocol?
    private var radius: CGFloat = 26
    private var embeddedContent: NSView?
    var exporting = false { didSet { if oldValue != exporting { updateMaterial() } } }
    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = radius; layer?.masksToBounds = false
        updateMaterial()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.updateMaterial() } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point), result is NSControl else { return nil }
        return result
    }
    func setContent(_ value: NSView) { embeddedContent = value; updateMaterial() }
    func setCornerRadius(_ value: CGFloat) {
        guard radius != value else { return }
        radius = value; layer?.cornerRadius = value
        surface?.cornerRadius = value
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
    }
    private func updateMaterial() {
        surface?.contentView = nil
        embeddedContent?.removeFromSuperview()
        embeddedContent?.isHidden = false
        embeddedContent?.translatesAutoresizingMaskIntoConstraints = true
        surface?.removeFromSuperview(); surface = nil
        if exporting || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            layer?.backgroundColor = exporting ? NSColor.clear.cgColor : NSColor.windowBackgroundColor.cgColor
            if let embeddedContent { embeddedContent.frame = bounds; embeddedContent.autoresizingMask = [.width, .height]; addSubview(embeddedContent) }
            return
        }
        layer?.backgroundColor = NSColor.clear.cgColor
        let glass = NSGlassEffectView(frame: bounds)
        glass.style = .regular; glass.cornerRadius = radius
        glass.contentView = embeddedContent
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        glass.autoresizingMask = [.width, .height]
        addSubview(glass); surface = glass
        embeddedContent?.frame = bounds
        embeddedContent?.needsLayout = true
    }
}

@MainActor
final class GlassControlContent: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

/// Settings remains clickable while the nonactivating HUD is monitoring another app.
@MainActor
private final class CompanionSettingsButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
