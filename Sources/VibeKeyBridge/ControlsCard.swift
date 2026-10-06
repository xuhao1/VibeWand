import AppKit
import SwiftUI

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

/// One label on the controls card. A stick or the direction pad shares one label among its directions.
struct ControlsCardSlot: Identifiable {
    enum Side { case left, right, top }
    let id: String
    let symbol: String
    /// One control is a button, two are an opposite pair, four are up, down, left and right; a fifth is the stick's press.
    let controls: [DeviceControl]
    let side: Side
    /// Left off the card while nothing is bound to it.
    var optional = false

    static func slots(for template: DeviceTemplate) -> [ControlsCardSlot] {
        func symbol(_ control: DeviceControl) -> String { template.controls.first { $0.control == control }?.symbol ?? "circle" }
        func button(_ control: DeviceControl, _ side: Side, optional: Bool = false) -> ControlsCardSlot {
            ControlsCardSlot(id: control.rawValue, symbol: symbol(control), controls: [control], side: side, optional: optional)
        }
        guard template.id == .dualSense else {
            // Any other layout: its controls down one side, the two turns of a dial or the two ends of a rocker as a pair.
            let pairs: [DeviceControl: DeviceControl] = [.left: .right, .dpadUp: .dpadDown, .volumeUp: .volumeDown]
            let hotspots = DeviceArtwork.forTemplate(template.id).hotspots
            return template.controls.compactMap { item -> ControlsCardSlot? in
                if pairs.values.contains(item.control) { return nil }
                guard let other = pairs[item.control] else { return button(item.control, .right, optional: true) }
                return ControlsCardSlot(id: item.control.rawValue, symbol: item.control == .left ? "arrow.left.arrow.right" : "arrow.up.arrow.down",
                                        controls: [item.control, other], side: .right, optional: true)
            }.sorted { (hotspots[$0.controls[0]]?.y ?? 0) < (hotspots[$1.controls[0]]?.y ?? 0) }
        }
        return [
            button(.l2, .left), button(.l1, .left), button(.create, .left, optional: true),
            ControlsCardSlot(id: "dpad", symbol: "dpad", controls: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight], side: .left),
            ControlsCardSlot(id: "leftStick", symbol: "l.joystick", controls: [.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight, .leftStickPress], side: .left),
            button(.home, .left, optional: true), button(.mute, .left, optional: true),
            ControlsCardSlot(id: "touchpad", symbol: "hand.draw", controls: [.touchpad], side: .top),
            // Clockwise round the face buttons, so that no leader crosses a button or another leader.
            button(.r2, .right), button(.r1, .right), button(.options, .right), button(.voice, .right),
            button(.escape, .right), button(.ok, .right), button(.dial, .right),
            ControlsCardSlot(id: "rightStick", symbol: "r.joystick", controls: [.rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight, .rightStickPress], side: .right)
        ]
    }

    /// What the label says: the main thing first, the rest under it.
    func lines(_ hints: [DeviceControl: [HUDGestureHint]]) -> [String] {
        switch controls.count {
        case 1 where controls[0] == .touchpad:
            // Sliding a finger is not a binding; the press is.
            return [tr("滑动 · 移动指针", "Slide · move the pointer")] + (hints[.touchpad]?.first.map { [tr("按下 · ", "Press · ") + $0.caption] } ?? [])
        case 1:
            let all = hints[controls[0]] ?? []
            guard let main = all.first(where: { $0.kind == .hold }) ?? all.first else { return [] }
            let rest = all.filter { $0 != main }.map(\.title)
            return [main.kind == .single ? main.caption : main.title] + (rest.isEmpty ? [] : [rest.joined(separator: " · ")])
        case 2:
            let vertical = controls[0] != .left
            return HUDGuidance.pair(hints[controls[0]]?.first, hints[controls[1]]?.first, vertical ? ("↑", "↓") : ("←", "→")).map { [$0] } ?? []
        default:
            var lines = HUDGuidance.directions(hints, up: controls[0], down: controls[1], left: controls[2], right: controls[3])
            if controls.count > 4, let press = hints[controls[4]]?.first { lines.append(tr("按下 · ", "Press · ") + press.caption) }
            return Array(lines.prefix(2))
        }
    }
}

/// The controls card: the device in the middle and what every control does around it, the way a game shows its
/// button layout. It reads the layout as the user has set it, for the scene it is asked to show.
struct ControlsCard: View {
    static let size = CGSize(width: 1080, height: 680)
    let snapshot: HUDSnapshot
    /// A picture for the documentation has no window behind it to blur.
    var exporting = false
    var onScene: (GestureScope?) -> Void = { _ in }

    private var template: DeviceTemplate { snapshot.deviceTemplate.template }
    private var card: ControlsCardSnapshot { snapshot.card ?? ControlsCardSnapshot(scene: .reading, hints: [:]) }
    private struct Label: Identifiable {
        let slot: ControlsCardSlot
        var frame: CGRect
        let target: CGPoint?
        let lines: [String]
        var id: String { slot.id }
    }
    private static let stage = CGRect(x: 28, y: 142, width: 1024, height: 448)
    private static let rowHeight: CGFloat = 50

    var body: some View {
        let placed = layout()
        ZStack(alignment: .topLeading) {
            backdrop
            if let image = DeviceArtwork.forTemplate(template.id).image {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: placed.image.width, height: placed.image.height)
                    .shadow(color: .black.opacity(0.55), radius: 26, y: 18)
                    .position(x: placed.image.midX, y: placed.image.midY)
            } else {
                Image(systemName: "keyboard").font(.system(size: 120, weight: .ultraLight)).foregroundStyle(.white.opacity(0.22))
                    .position(x: placed.image.midX, y: placed.image.midY)
            }
            Canvas { context, _ in
                for label in placed.labels { leader(label, in: &context) }
            }.allowsHitTesting(false)
            ForEach(placed.labels) { label in
                row(label).frame(width: label.frame.width, height: label.frame.height)
                    .position(x: label.frame.midX, y: label.frame.midY)
            }
            header
            motto
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // A picture keeps its corners: there is nothing behind it to show through.
        .clipShape(RoundedRectangle(cornerRadius: exporting ? 0 : 30, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("按键一览", "Controls"))
    }

    // MARK: Pieces

    private var backdrop: some View {
        ZStack {
            if exporting { Color(red: 0.07, green: 0.08, blue: 0.11) } else { CardGlass() }
            LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.20).opacity(exporting ? 1 : 0.80), Color(red: 0.03, green: 0.04, blue: 0.07).opacity(exporting ? 1 : 0.88)],
                           startPoint: .top, endPoint: .bottom)
            // A pool of light under the device, as on a game's controller screen.
            RadialGradient(colors: [Color.accentColor.opacity(0.26), .clear], center: UnitPoint(x: 0.5, y: 0.56), startRadius: 10, endRadius: 420)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                HStack(spacing: 10) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 18, weight: .semibold))
                    Text(tr("按键一览", "Controls")).font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    Circle().fill(snapshot.connected ? Color.green : snapshot.demo ? Color.blue : Color.gray).frame(width: 7, height: 7)
                    Text(template.title + " · " + (snapshot.connected ? tr("已连接", "connected") : snapshot.demo ? tr("演示", "demo") : tr("未连接", "not connected")))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                    Button { onScene(nil) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                            .background(.white.opacity(0.12), in: Circle())
                    }.buttonStyle(.plain).help(tr("关闭", "Close")).accessibilityLabel(tr("关闭按键一览", "Close the controls card"))
                }
                HStack(spacing: 6) {
                    ForEach(ControlsCardSnapshot.scenes, id: \.self) { scene in
                        let selected = scene == card.scene
                        Button { onScene(scene) } label: {
                            Text(Self.title(scene)).font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.82))
                                .padding(.horizontal, 16).frame(height: 30)
                                .background(selected ? Color.white.opacity(0.94) : Color.white.opacity(0.09), in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            Text(Self.note(card.scene)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28).padding(.top, 22)
        .frame(width: Self.size.width, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: card.tried.isEmpty ? "hand.tap" : "dot.radiowaves.left.and.right").foregroundStyle(card.tried.isEmpty ? Color.white.opacity(0.6) : Color.accentColor)
            Text(card.tried.isEmpty ? tr("随便按：按到的键会在这里亮起来，不会发给应用", "Press anything: it lights up here and reaches no app") : card.tried)
                .font(.system(size: 13.5, weight: card.tried.isEmpty ? .regular : .semibold))
                .foregroundStyle(card.tried.isEmpty ? Color.white.opacity(0.66) : Color.white)
            Spacer()
            Text(Self.keys(template.id)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 28).frame(width: Self.size.width, height: 52)
        .background(.black.opacity(0.28))
        .position(x: Self.size.width / 2, y: Self.size.height - 26)
    }

    /// The layout in one line, under the device.
    private var motto: some View {
        Text(template.subtitle).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
            .lineLimit(1).frame(width: Self.size.width - 56)
            .position(x: Self.size.width / 2, y: Self.stage.maxY + 19)
    }

    private func row(_ label: Label) -> some View {
        let active = label.slot.controls.contains(where: snapshot.pressed.contains)
        let empty = label.lines.isEmpty, left = label.slot.side == .left
        let badge = Image(systemName: label.slot.symbol).font(.system(size: 19, weight: .medium))
            .foregroundStyle(active ? Color.white : Color.white.opacity(empty ? 0.5 : 0.95)).frame(width: 40)
        let text = VStack(alignment: left ? .trailing : .leading, spacing: 2) {
            Text(empty ? tr("未分配", "Unassigned") : label.lines[0]).font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white.opacity(empty ? 0.42 : 1))
            if label.lines.count > 1 {
                Text(label.lines[1]).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            }
        }.lineLimit(1).minimumScaleFactor(0.75)
        return HStack(spacing: 6) {
            switch label.slot.side {
            case .left: Spacer(minLength: 0); text; badge
            case .right:
                badge; text; Spacer(minLength: 0)
                // The keyboard has no picture to point at: each label carries its key combination.
                if template.id == .keyboard {
                    Text(label.slot.controls.map(KeyboardLayout.current.label).joined(separator: "  "))
                        .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7)).padding(.trailing, 8)
                }
            case .top: badge; text
            }
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? Color.accentColor.opacity(0.42) : Color.white.opacity(empty ? 0.035 : 0.075), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(active ? Color.accentColor : Color.white.opacity(0.13), lineWidth: active ? 1.5 : 0.8))
        .animation(.easeOut(duration: 0.12), value: active)
    }

    private func leader(_ label: Label, in context: inout GraphicsContext) {
        guard let target = label.target else { return }
        let active = label.slot.controls.contains(where: snapshot.pressed.contains)
        let frame = label.frame
        var path = Path()
        if label.slot.side == .top { path.move(to: CGPoint(x: frame.midX, y: frame.maxY)) } else {
            let inward: CGFloat = label.slot.side == .left ? 1 : -1
            let start = CGPoint(x: label.slot.side == .left ? frame.maxX : frame.minX, y: frame.midY)
            path.move(to: start)
            // A label far above or below its control runs level first and then turns to it, clear of the controls between.
            let steep = abs(target.y - start.y) > 0.6 * abs(target.x - start.x)
            path.addLine(to: CGPoint(x: steep ? target.x - inward * 18 : start.x + inward * 14, y: start.y))
        }
        path.addLine(to: target)
        let color = active ? Color.accentColor : Color.white.opacity(label.lines.isEmpty ? 0.22 : 0.5)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: active ? 1.8 : 1, lineCap: .round, lineJoin: .round))
        let radius: CGFloat = active ? 7 : 3.2
        let dot = Path(ellipseIn: CGRect(x: target.x - radius, y: target.y - radius, width: radius * 2, height: radius * 2))
        context.fill(dot, with: .color(active ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.9)))
        if active { context.stroke(dot, with: .color(.white), lineWidth: 1.5) }
    }

    // MARK: Layout

    /// Each label sits as near its control as the others on its side allow.
    private func layout() -> (image: CGRect, labels: [Label]) {
        let artwork = DeviceArtwork.forTemplate(template.id)
        let slots = ControlsCardSlot.slots(for: template).filter { slot in
            !slot.optional || !slot.lines(card.hints).isEmpty
        }
        let sided = slots.contains { $0.side == .left }
        let ratio = artwork.aspectRatio
        let size = ratio > 1 ? CGSize(width: 440, height: 440 / ratio) : CGSize(width: 400 * ratio, height: 400)
        let image = CGRect(x: (sided ? Self.size.width / 2 : 300) - size.width / 2, y: Self.stage.midY - size.height / 2 + (sided ? 14 : 0),
                           width: size.width, height: size.height)
        func target(_ slot: ControlsCardSlot) -> CGPoint? {
            let points = slot.controls.prefix(4).compactMap { artwork.hotspots[$0] }
            guard !points.isEmpty else { return nil }
            let x = points.map(\.x).reduce(0, +) / CGFloat(points.count), y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
            return CGPoint(x: image.minX + x * image.width, y: image.minY + y * image.height)
        }
        var labels: [Label] = []
        for side in [ControlsCardSlot.Side.left, .right] {
            let column = slots.filter { $0.side == side }.map { (slot: $0, target: target($0)) }
            let width: CGFloat = sided ? 262 : 470
            let x = side == .left ? Self.stage.minX : sided ? Self.stage.maxX - width : 560
            let pitch = Self.rowHeight + 7
            var centers: [CGFloat] = []
            for (offset, item) in column.enumerated() {
                let wanted = item.target?.y ?? Self.stage.minY + Self.rowHeight / 2 + CGFloat(offset) * pitch
                centers.append(max(wanted, (centers.last.map { $0 + pitch } ?? Self.stage.minY + Self.rowHeight / 2)))
            }
            // Whatever ran off the bottom pushes the ones above it up.
            var limit = Self.stage.maxY - Self.rowHeight / 2
            for index in centers.indices.reversed() { centers[index] = min(centers[index], limit); limit = centers[index] - pitch }
            for (item, center) in zip(column, centers) {
                labels.append(Label(slot: item.slot, frame: CGRect(x: x, y: center - Self.rowHeight / 2, width: width, height: Self.rowHeight),
                                    target: item.target, lines: item.slot.lines(card.hints)))
            }
        }
        for slot in slots where slot.side == .top {
            labels.append(Label(slot: slot, frame: CGRect(x: image.midX - 120, y: image.minY - 62, width: 240, height: 42),
                                target: target(slot), lines: slot.lines(card.hints)))
        }
        return (image, labels)
    }

    // MARK: Words

    static func title(_ scene: GestureScope) -> String {
        switch scene {
        case .reading: return tr("阅读", "Reading")
        case .editing: return tr("编辑", "Editing")
        case .applications: return tr("切应用", "Switching apps")
        default: return tr("列表", "Lists")
        }
    }
    private static func note(_ scene: GestureScope) -> String {
        switch scene {
        case .reading: return tr("输入框是空的，在看回复的时候", "While the input field is empty and you are reading")
        case .editing: return tr("输入框里有文字的时候", "While there is text in the input field")
        case .applications: return tr("切换应用的那一排图标出现的时候", "While the row of app icons is on screen")
        default: return tr("会话、模型、强度这些列表打开的时候", "While a list of chats, models or effort levels is open")
        }
    }
    /// How the card itself is worked, in the words of each device.
    private static func keys(_ template: DeviceTemplateID) -> String {
        let back = HUDGuidance.shortName(template == .dualSense ? .ok : .escape, template: template)
        switch template {
        case .vibeKey: return tr("转动旋钮换场景 · \(back)关闭", "Turn the dial for another scene · \(back) closes")
        case .dualSense: return tr("方向键或摇杆换场景 · \(back) 关闭", "D-pad or a stick for another scene · \(back) closes")
        case .xiaomiRemote, .keyboard: return tr("左右换场景 · \(back)关闭", "Left / right for another scene · \(back) closes")
        }
    }
}

/// The system's Liquid Glass behind the card.
private struct CardGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> CompanionBackdrop {
        let view = CompanionBackdrop(); view.setCornerRadius(30); return view
    }
    func updateNSView(_ view: CompanionBackdrop, context: Context) {}
}

/// A panel in the middle of the screen that takes no keyboard focus from the app in front.
@MainActor
final class ControlsCardController {
    private final class Model: ObservableObject { @Published var snapshot = HUDSnapshot() }
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private final class Host: NSHostingView<Root> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    private struct Root: View {
        @ObservedObject var model: Model
        let scale: CGFloat
        let onScene: (GestureScope?) -> Void
        var body: some View {
            ControlsCard(snapshot: model.snapshot, onScene: onScene).scaleEffect(scale)
                .frame(width: ControlsCard.size.width * scale, height: ControlsCard.size.height * scale)
        }
    }
    private let model = Model()
    private var panel: NSPanel?
    private let onScene: (GestureScope?) -> Void
    init(onScene: @escaping (GestureScope?) -> Void) { self.onScene = onScene }

    func update(_ snapshot: HUDSnapshot) {
        model.snapshot = snapshot
        if snapshot.card == nil { panel?.orderOut(nil); panel = nil } else if panel == nil {
            let panel = makePanel()
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.animator().alphaValue = 1
            self.panel = panel
        }
    }

    /// The panel on the screen the pointer is on, shrunk only where that screen is too small for it. Making it shows nothing.
    func makePanel() -> NSPanel {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = min(1, (visible.width - 48) / ControlsCard.size.width, (visible.height - 48) / ControlsCard.size.height)
        let size = NSSize(width: ControlsCard.size.width * scale, height: ControlsCard.size.height * scale)
        let panel = Panel(contentRect: NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.title = L10n.tr("VibeWand 按键一览", "VibeWand Controls")
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = Host(rootView: Root(model: model, scale: scale, onScene: onScene))
        return panel
    }

    /// The card as a picture, for the documentation and for looking it over without a window.
    static func image(_ snapshot: HUDSnapshot) -> NSImage? {
        let renderer = ImageRenderer(content: ControlsCard(snapshot: snapshot, exporting: true))
        renderer.scale = 2
        return renderer.nsImage
    }
}
