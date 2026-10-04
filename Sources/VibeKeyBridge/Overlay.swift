import AppKit
import ImageIO

/// Design-space geometry is shared by artwork, highlights, and demo hit testing.
enum OverlayLayout {
    static func size(for template: DeviceTemplateID, expanded: Bool) -> NSSize {
        switch template {
        case .vibeKey: return NSSize(width: expanded ? 326 : 200, height: 290)
        case .dualSense: return NSSize(width: expanded ? 500 : 300, height: expanded ? 324 : 272)
        case .xiaomiRemote: return NSSize(width: expanded ? 360 : 200, height: 310)
        }
    }

    static func deviceRect(for template: DeviceTemplateID, expanded: Bool) -> NSRect {
        switch template {
        case .vibeKey:
            // This asset alone is cropped to its opaque body, preserving its dial animation.
            return NSRect(x: (expanded ? 91 : 100) - 26.1, y: 37, width: 52.2, height: 198)
        case .dualSense:
            return NSRect(x: 12, y: expanded ? 68 : 41, width: 276, height: 184)
        case .xiaomiRemote:
            return NSRect(x: expanded ? 5 : 24, y: 36, width: 152, height: 228)
        }
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
        guard let point = DeviceArtwork.forTemplate(template).hotspots[control] else { return nil }
        return NSPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}

/// An accessory window that stays out of the target application's focus chain.
@MainActor
final class OverlayController {
    private let panel: CompanionPanel
    private let view: CompanionView
    private var scale = 1.0
    private var expanded = false
    private let positionKey = "VibeKeyBridge.overlayOrigin"
    var isVisible: Bool { panel.isVisible }

    init(onOpenSettings: @escaping () -> Void = {}, onHide: @escaping () -> Void = {}, onControl: @escaping (DeviceControl, InputPhase) -> Void) {
        view = CompanionView(onOpenSettings: onOpenSettings, onHide: onHide, onControl: onControl)
        panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: CompanionView.compactSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = L10n.tr("VibeWand 悬浮面板", "VibeWand Overlay")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        view.autoresizingMask = [.width, .height]
        view.onDragCompleted = { [weak self] in self?.savePosition() }
        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            panel.setFrameOrigin(NSPointFromString(saved))
            keepOnScreen()
        } else { resetPosition() }
    }

    func update(_ state: HUDSnapshot) {
        panel.title = L10n.tr("VibeWand 悬浮面板", "VibeWand Overlay")
        let changedTemplate = view.deviceTemplate != state.deviceTemplate
        view.update(state)
        // Resizing never orders the panel front, so switching a template keeps a hidden HUD hidden.
        if changedTemplate { resize() }
    }
    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() }
        else { view.cancelMousePress(); panel.orderOut(nil) }
    }
    func setScale(_ value: Double) { scale = min(1.8, max(0.65, value)); resize() }
    func setOpacity(_ value: Double) { panel.alphaValue = min(1, max(0.35, value)) }
    func setExpanded(_ value: Bool) { expanded = value; view.expanded = value; resize() }

    func resetPosition() {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 28, y: screen.minY + 34))
        savePosition()
    }

    /// Render our own accessory for documentation without capturing other windows.
    func previewImage(appearance: NSAppearance? = nil) -> NSImage? {
        guard let bitmap = bitmap(appearance: appearance) else { return nil }
        let image = NSImage(size: view.bounds.size)
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
        if let appearance { view.appearance = appearance }
        view.exporting = true
        defer {
            view.exporting = false
            view.appearance = previousAppearance
        }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        // Offscreen rendering has no WindowServer backdrop. Resolve semantic colors
        // against the HUD (or requesting settings window), never an ambient context.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        return bitmap
    }

    private func resize() {
        let size = OverlayLayout.size(for: view.deviceTemplate, expanded: expanded)
        let top = panel.frame.maxY
        let right = panel.frame.maxX
        panel.setFrame(NSRect(x: right - size.width * scale, y: top - size.height * scale, width: size.width * scale, height: size.height * scale), display: true)
        keepOnScreen()
        savePosition()
    }
    private func savePosition() { UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: positionKey) }
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
            material.isHidden = exporting
            redraw()
        }
    }
    private let onControl: (DeviceControl, InputPhase) -> Void
    private let onOpenSettings: () -> Void
    private let onHide: () -> Void
    private let material = CompanionMaterial()
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

    init(onOpenSettings: @escaping () -> Void, onHide: @escaping () -> Void, onControl: @escaping (DeviceControl, InputPhase) -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onHide = onHide
        self.onControl = onControl
        super.init(frame: NSRect(origin: .zero, size: Self.compactSize))
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.masksToBounds = true
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.frame = bounds
        material.autoresizingMask = [.width, .height]
        material.wantsLayer = true
        material.layer?.cornerRadius = 17
        material.layer?.masksToBounds = true
        addSubview(material)
        // The drawing lives above the native material without replacing its appearance.
        let drawing = CompanionDrawing(owner: self)
        self.drawing = drawing
        drawing.frame = bounds
        drawing.autoresizingMask = [.width, .height]
        addSubview(drawing)
        for button in [settingsButton, hideButton] {
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.bezelStyle = .recessed
            button.contentTintColor = .secondaryLabelColor
            button.target = self
            addSubview(button)
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

    override func layout() {
        super.layout()
        // Keep both controls easy to hit even when the user shrinks the HUD.
        let side = max(24, 24 * factor), gap = max(2, 2 * factor)
        let inset = max(6, 10 * factor), y = max(3, 8 * factor)
        hideButton.frame = NSRect(x: bounds.width - inset - side, y: y, width: side, height: side)
        settingsButton.frame = NSRect(x: hideButton.frame.minX - gap - side, y: y, width: side, height: side)
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: max(11, 12 * factor), weight: .medium)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration)
        hideButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration)
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

    fileprivate func drawContents() {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scaleX(by: factor, yBy: factor)
        transform.concat()
        if exporting {
            // Material is composited by WindowServer. Export uses the matching system surface.
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: designSize), xRadius: 17, yRadius: 17).fill()
        }
        let outline = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: designSize.width - 1, height: designSize.height - 1), xRadius: 16.5, yRadius: 16.5)
        NSColor.separatorColor.withAlphaComponent(0.30).setStroke()
        outline.lineWidth = 0.7
        outline.stroke()
        drawHeader()
        drawDevice()
        drawFooter()
        if expanded { drawExpandedLabels() }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHeader() {
        let buttonsX = settingsButton.frame.minX / max(factor, 0.01)
        text("VibeWand", rect: NSRect(x: 15, y: 12, width: min(88, max(0, buttonsX - 18)), height: 17), size: 11, weight: .medium, color: .labelColor)
        if designSize.width >= 300 {
            text(deviceTemplate.template.title, rect: NSRect(x: 86, y: 13, width: max(0, buttonsX - 143), height: 15), size: 10, weight: .regular, color: .secondaryLabelColor)
        }
        let showStatusLabel = buttonsX >= 132
        let liveX = buttonsX - (showStatusLabel ? 43 : 10)
        NSColor.secondaryLabelColor.withAlphaComponent(snapshot.connected || snapshot.demo ? 0.75 : 0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: liveX, y: 19, width: 3.5, height: 3.5)).fill()
        if showStatusLabel {
            text(snapshot.captureOnly ? L10n.tr("采集", "INPUT") : snapshot.demo ? L10n.tr("演示", "DEMO") : snapshot.connected ? L10n.tr("实时", "LIVE") : L10n.tr("离线", "OFF"), rect: NSRect(x: liveX + 7, y: 14, width: 29, height: 12), size: 7.5, weight: .medium, color: .secondaryLabelColor)
        }
    }

    private func drawDevice() {
        if let image = deviceImage {
            image.draw(in: deviceRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
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

    private func drawFooter() {
        let width: CGFloat = expanded && deviceTemplate == .dualSense ? 274 : designSize.width - 26
        text(snapshot.mode, rect: NSRect(x: 13, y: designSize.height - 44, width: width, height: 17), size: 11, weight: .medium, color: .labelColor, alignment: .center)
        text(snapshot.action, rect: NSRect(x: 13, y: designSize.height - 26, width: width, height: 15), size: 9, weight: .regular, color: .secondaryLabelColor, alignment: .center)
    }

    private func actionCaption(_ control: DeviceControl) -> String {
        snapshot.controlActions[control] ?? L10n.tr("未分配", "Unassigned")
    }

    private func drawExpandedLabels() {
        let x: CGFloat = deviceTemplate == .dualSense ? 308 : deviceTemplate == .xiaomiRemote ? 152 : 149
        let width = designSize.width - x - 15
        text(snapshot.target, rect: NSRect(x: x, y: 39, width: width, height: 15), size: 10, weight: .medium, color: .secondaryLabelColor)
        var controls: [DeviceControl]
        switch deviceTemplate {
        case .vibeKey: controls = [.dial, .left, .right, .voice, .ok, .escape]
        case .dualSense: controls = [.left, .right, .dial, .ok, .escape, .voice, .rightStickUp, .rightStickDown]
        case .xiaomiRemote: controls = [.voice, .dial, .left, .right, .escape, .ok]
        }
        // Keep an uncommon pressed control visible without turning the compact guide into a full editor.
        if let active = deviceTemplate.template.controls.first(where: { isActive($0.control) && !controls.contains($0.control) }) {
            controls[controls.count - 1] = active.control
        }
        let rowHeight: CGFloat = deviceTemplate == .dualSense ? 31 : deviceTemplate == .xiaomiRemote ? 34 : 30
        for (index, control) in controls.enumerated() {
            guard let descriptor = deviceTemplate.template.controls.first(where: { $0.control == control }) else { continue }
            let y = 60 + CGFloat(index) * rowHeight
            text(descriptor.title, rect: NSRect(x: x, y: y, width: width, height: 14), size: 10, weight: isActive(control) ? .semibold : .medium, color: isActive(control) ? .controlAccentColor : .labelColor)
            text(actionCaption(control), rect: NSRect(x: x, y: y + 14, width: width, height: 13), size: 8.5, weight: .regular, color: .secondaryLabelColor)
        }
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
    private func redraw() { drawing?.needsDisplay = true }
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
        guard snapshot.demo, let control = hitControl(event) else { window?.performDrag(with: event); onDragCompleted?(); return }
        flash(control)
        if control == .left || control == .right || control.isStickDirection { onControl(control, .pulse) }
        else { mouseControl = control; onControl(control, .down) }
        redraw()
    }
    override func mouseUp(with event: NSEvent) { if let control = mouseControl { mouseControl = nil; onControl(control, .up) } }
    override func scrollWheel(with event: NSEvent) {
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
    init(owner: CompanionView) { self.owner = owner; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { owner?.drawContents() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class CompanionMaterial: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Settings remains clickable while the nonactivating HUD is monitoring another app.
@MainActor
private final class CompanionSettingsButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
