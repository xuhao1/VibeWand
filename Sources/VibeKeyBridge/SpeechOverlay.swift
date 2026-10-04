import AppKit
import SpeechInput

enum OverlayDisplayMode: String, CaseIterable {
    case full, compact
    var title: String { self == .full ? L10n.tr("完整面板", "Full panel") : L10n.tr("输入法小条", "Compact bar") }
}

enum SpeechOverlayLayout {
    static let gap: CGFloat = 7
    static func barHeight(voice: VoiceHUDSnapshot) -> CGFloat { voice.showsText ? 118 : 48 }
    static func size(template: DeviceTemplateID, expanded: Bool, mode: OverlayDisplayMode, voice: VoiceHUDSnapshot) -> NSSize {
        let height = barHeight(voice: voice)
        if mode == .compact { return NSSize(width: 390, height: height) }
        let device = OverlayLayout.size(for: template, expanded: expanded)
        return NSSize(width: device.width, height: device.height + 7 + height)
    }
}

/// Composes the existing device view and a shared speech strip. Recognition,
/// text transformation and insertion stay outside this view tree.
@MainActor
final class SpeechOverlayHost: NSView {
    let fullView: NSView
    private let bar: SpeechOverlayBar
    var onToggleMode: (() -> Void)?
    var onDragCompleted: (() -> Void)? { didSet { bar.onDragCompleted = onDragCompleted } }
    private(set) var snapshot = HUDSnapshot()
    private var mode = OverlayDisplayMode.full
    private var expanded = false
    private let content = GlassControlContent()
    /// The bar is the fixed part; the device view opens above it, or below
    /// when there is no room above.
    var deviceBelow = false { didSet { if oldValue != deviceBelow { needsLayout = true } } }
    override var isFlipped: Bool { true }
    var exporting = false { didSet { bar.exporting = exporting } }
    init(fullView: NSView, isPreview: Bool = false, onOpenSettings: @escaping () -> Void,
         onHide: @escaping () -> Void, onToggleStyle: @escaping () -> Void) {
        self.fullView = fullView
        bar = SpeechOverlayBar(isPreview: isPreview, onOpenSettings: onOpenSettings, onHide: onHide, onToggleStyle: onToggleStyle)
        super.init(frame: .zero)
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let group = NSGlassEffectContainerView(frame: bounds)
            group.contentView = content; group.spacing = 0; group.autoresizingMask = [.width, .height]
            addSubview(group)
        } else { addSubview(content) }
        content.addSubview(fullView); content.addSubview(bar)
        bar.onToggleMode = { [weak self] in self?.onToggleMode?() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    /// Screen rectangle of the compact/full switch, for layout checks.
    var toggleButtonScreenFrame: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(bar.convert(bar.toggleFrame, to: nil))
    }
    func update(_ snapshot: HUDSnapshot, mode: OverlayDisplayMode, expanded: Bool) {
        self.snapshot = snapshot; self.mode = mode; self.expanded = expanded
        fullView.isHidden = mode == .compact; bar.update(snapshot, mode: mode); needsLayout = true
    }
    override func layout() {
        super.layout()
        let size = SpeechOverlayLayout.size(template: snapshot.deviceTemplate, expanded: expanded, mode: mode, voice: snapshot.voice)
        let factor = bounds.width / max(1, size.width)
        if mode == .full {
            let device = OverlayLayout.size(for: snapshot.deviceTemplate, expanded: expanded)
            let deviceHeight = device.height * factor, barHeight = bounds.height - (device.height + SpeechOverlayLayout.gap) * factor
            if deviceBelow {
                bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
                fullView.frame = NSRect(x: 0, y: bounds.height - deviceHeight, width: bounds.width, height: deviceHeight)
            } else {
                fullView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: deviceHeight)
                bar.frame = NSRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
            }
        } else { bar.frame = bounds }
    }
}

@MainActor
private final class SpeechOverlayBar: NSView {
    var onToggleMode: (() -> Void)?
    var onDragCompleted: (() -> Void)?
    var toggleFrame: NSRect { resizeButton.frame }
    var exporting = false { didSet { glass.exporting = exporting; needsDisplay = true } }
    private var mode = OverlayDisplayMode.full
    private let glass: CompanionBackdrop
    private let content = GlassControlContent()
    private let status = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let style = NSButton(), resizeButton = NSButton(), settings = NSButton(), hide = NSButton()
    private let scroll = NSScrollView(), transcript = NSTextView()
    private let onOpenSettings: () -> Void, onHide: () -> Void, onToggleStyle: () -> Void
    private let isPreview: Bool
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(isPreview: Bool, onOpenSettings: @escaping () -> Void, onHide: @escaping () -> Void, onToggleStyle: @escaping () -> Void) {
        self.isPreview = isPreview; self.onOpenSettings = onOpenSettings; self.onHide = onHide; self.onToggleStyle = onToggleStyle
        glass = CompanionBackdrop(inWindow: isPreview)
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 18; layer?.masksToBounds = false
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        glass.setCornerRadius(18); glass.setContent(content)
        addSubview(glass); content.addSubview(icon); content.addSubview(status)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingTail
        for button in [style, resizeButton, settings, hide] {
            button.isBordered = false; button.bezelStyle = .recessed; button.target = self
            button.refusesFirstResponder = true
            button.font = .systemFont(ofSize: 12, weight: .medium); content.addSubview(button)
        }
        style.action = #selector(toggleStyle); resizeButton.action = #selector(toggleMode)
        settings.action = #selector(openSettings); hide.action = #selector(hideOverlay)
        style.wantsLayer = true; style.layer?.cornerRadius = 9
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        hide.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        transcript.isEditable = false; transcript.isSelectable = false; transcript.drawsBackground = false
        transcript.font = .systemFont(ofSize: 14); transcript.textColor = .labelColor
        transcript.textContainerInset = NSSize(width: 0, height: 3)
        transcript.isVerticallyResizable = true; transcript.isHorizontallyResizable = false
        transcript.textContainer?.widthTracksTextView = true
        scroll.documentView = transcript; content.addSubview(scroll); setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func update(_ snapshot: HUDSnapshot, mode: OverlayDisplayMode) {
        self.mode = mode
        let voice = snapshot.voice
        status.stringValue = voice.enabled ? voice.status : L10n.tr("外置语音输入法", "External dictation")
        status.toolTip = status.stringValue
        icon.image = NSImage(systemSymbolName: voice.state == .recording ? "waveform" : "mic", accessibilityDescription: status.stringValue)
        icon.contentTintColor = voice.state == .recording ? .systemRed : voice.state == .polishing ? .systemPurple : .secondaryLabelColor
        style.title = voice.style.title
        style.image = NSImage(systemSymbolName: voice.style == .polished ? "wand.and.stars" : "text.quote", accessibilityDescription: nil)
        style.imagePosition = .imageLeading
        style.isEnabled = voice.enabled && voice.state != .transcribing && voice.state != .polishing && !isPreview
        style.contentTintColor = voice.style == .polished ? .controlAccentColor : .labelColor
        style.layer?.backgroundColor = (voice.style == .polished ? NSColor.controlAccentColor.withAlphaComponent(0.13) : NSColor.labelColor.withAlphaComponent(0.06)).cgColor
        style.toolTip = L10n.tr("切换原词转写／自动整理", "Switch verbatim / polished dictation")
        style.setAccessibilityLabel(style.toolTip! + " · " + style.title)
        resizeButton.image = NSImage(systemSymbolName: mode == .full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        resizeButton.toolTip = mode == .full ? L10n.tr("切换到输入法小条", "Switch to compact bar") : L10n.tr("展开完整面板", "Expand full panel")
        resizeButton.setAccessibilityLabel(resizeButton.toolTip!)
        settings.toolTip = L10n.tr("打开设置", "Open settings"); settings.setAccessibilityLabel(settings.toolTip!)
        hide.toolTip = L10n.tr("隐藏悬浮窗", "Hide overlay"); hide.setAccessibilityLabel(hide.toolTip!)
        resizeButton.isEnabled = !isPreview; settings.isEnabled = !isPreview; hide.isEnabled = !isPreview
        scroll.isHidden = !voice.showsText
        let text = voice.text.isEmpty ? voice.state.title : voice.text
        if transcript.string != text {
            transcript.string = text
            transcript.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
        }
        setAccessibilityLabel(L10n.tr("语音输入", "Voice input") + " · " + status.stringValue)
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout(); glass.frame = bounds
        let header: CGFloat = min(48, bounds.height), button: CGFloat = 25, inset: CGFloat = 10
        hide.frame = NSRect(x: bounds.width - inset - button, y: (header - button) / 2, width: button, height: button)
        settings.frame = hide.frame.offsetBy(dx: -button - 2, dy: 0); resizeButton.frame = settings.frame.offsetBy(dx: -button - 2, dy: 0)
        let styleWidth: CGFloat = L10n.shared.language == .english ? 100 : 87
        style.frame = NSRect(x: resizeButton.frame.minX - styleWidth - 6, y: (header - 28) / 2, width: styleWidth, height: 28)
        icon.frame = NSRect(x: 12, y: (header - 19) / 2, width: 19, height: 19)
        status.frame = NSRect(x: 39, y: (header - 17) / 2, width: max(0, style.frame.minX - 45), height: 17)
        scroll.frame = NSRect(x: 14, y: header - 1, width: max(1, bounds.width - 28), height: max(1, bounds.height - header - 10))
        transcript.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, transcript.frame.height))
        transcript.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        layer?.cornerRadius = min(18, bounds.height / 2)
        glass.setCornerRadius(min(18, bounds.height / 2))
    }
    override func draw(_ dirtyRect: NSRect) {
        if exporting {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? NSColor(calibratedWhite: 0.12, alpha: 0.98) : NSColor(calibratedWhite: 0.97, alpha: 0.98)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        }
        if exporting {
            NSColor.labelColor.withAlphaComponent(0.12).setStroke()
            let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18); rim.lineWidth = 1; rim.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event); onDragCompleted?() }
    @objc private func toggleStyle() { guard !isPreview else { return }; onToggleStyle() }
    @objc private func toggleMode() { guard !isPreview else { return }; onToggleMode?() }
    @objc private func openSettings() { guard !isPreview else { return }; onOpenSettings() }
    @objc private func hideOverlay() { guard !isPreview else { return }; onHide() }
}
