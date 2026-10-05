import AppKit
import SwiftUI

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

/// The guide's frame: the list of steps at the side, the step in the middle, and the way on at the bottom.
struct OnboardingView: View {
    static let size = NSSize(width: 980, height: 680)
    @ObservedObject var model: SettingsModel
    @ObservedObject var guide: OnboardingModel
    @ObservedObject private var localization = L10n.shared
    @Namespace private var marker

    var body: some View {
        ZStack {
            OnboardingBackdrop(tint: guide.step.tint)
            HStack(spacing: 0) {
                rail
                VStack(spacing: 0) {
                    page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    footer
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .font(.system(size: 14))
        .environment(\.locale, localization.language.locale)
        .alert(tr("无法保存设置", "Unable to save settings"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(tr("知道了", "OK")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func move(to step: OnboardingStep) { withAnimation(.spring(duration: 0.5, bounce: 0.18)) { guide.go(to: step) } }
    private func advance(_ direction: Int) { withAnimation(.spring(duration: 0.5, bounce: 0.18)) { guide.advance(direction) } }

    // MARK: The steps at the side

    private var rail: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                BrandMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("VibeWand").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(tr("首次设置", "Getting started")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 6)
            VStack(spacing: 4) { ForEach(OnboardingStep.allCases) { row($0) } }
            Spacer(minLength: 0)
            Picker("Language / 语言", selection: $localization.language) {
                ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
        }
        // The window's own buttons sit over the top of the list.
        .padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 14)
        .frame(width: 226).frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.leading, 12).padding(.vertical, 12)
    }

    private func row(_ step: OnboardingStep) -> some View {
        let current = guide.step == step, passed = step.rawValue < guide.step.rawValue && guide.visited.contains(step)
        return Button { move(to: step) } label: {
            HStack(spacing: 10) {
                Image(systemName: passed ? "checkmark" : step.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(current ? Color.white : passed ? step.tint : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .background(current ? AnyShapeStyle(step.tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Circle())
                Text(step.title).font(.system(size: 14, weight: current ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 40)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.09))
                        .matchedGeometryEffect(id: "current", in: marker)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step.title).accessibilityAddTraits(current ? .isSelected : [])
    }

    // MARK: The step in the middle

    private var page: some View {
        Group {
            switch guide.step {
            case .welcome: WelcomeStep()
            case .access: AccessStep(model: model)
            case .device: DeviceStep(model: model, guide: guide)
            case .voice: VoiceStep(model: model, voice: model.runtime.voiceInput)
            case .keys: KeysStep(model: model, settings: model.runtime.command.settings, guide: guide)
            case .command: CommandStep(model: model, settings: model.runtime.command.settings)
            case .done: DoneStep(model: model, settings: model.runtime.command.settings, guide: guide)
            }
        }
        .id("\(guide.step.rawValue).\(localization.language.rawValue)")
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 26)), removal: .opacity.combined(with: .offset(x: -26))))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if guide.step != .welcome { Button(tr("上一步", "Back")) { advance(-1) }.buttonStyle(.glass) }
            Spacer(minLength: 0)
            if guide.step != .done {
                Button(tr("以后再说", "Not now")) { guide.close?() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(tr("关闭引导。之后可以在“设置 → 通用”里重新打开。", "Close the guide. It can be opened again under Settings → General."))
            }
            Button(guide.step == .welcome ? tr("开始设置", "Get started") : guide.step == .done ? tr("完成", "Done") : tr("继续", "Continue")) { advance(1) }
                .buttonStyle(.glassProminent).tint(guide.step.tint).keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 22)
    }
}

/// Slow colour behind everything, in the hue of the step in front. It holds still when the user asks for less motion.
private struct OnboardingBackdrop: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: still)) { moment in
            let time = Float(moment.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
            // The corners stay put; the points between them drift.
            let sway: (Float, Float) -> Float = { speed, phase in 0.5 + 0.16 * sin(time * speed + phase) }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [sway(0.21, 0), 0], [1, 0],
                [0, sway(0.17, 1.3)], [sway(0.13, 2.1), sway(0.19, 0.6)], [1, sway(0.15, 3.0)],
                [0, 1], [sway(0.11, 4.2), 1], [1, 1]
            ], colors: [
                tint.opacity(0.55), .blue.opacity(0.35), .purple.opacity(0.40),
                .teal.opacity(0.30), tint.opacity(0.65), .pink.opacity(0.30),
                .indigo.opacity(0.40), tint.opacity(0.45), .cyan.opacity(0.30)
            ])
        }
        // Calmed down, so that what is written over it stays easy to read.
        .overlay(Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? 0.62 : 0.58))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: tint)
        .accessibilityHidden(true)
    }
}

// MARK: Pieces the steps share

/// A step's heading, with its symbol arriving as the step does, over whatever the step holds.
struct OnboardingPage<Content: View>: View {
    let step: OnboardingStep
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    @State private var arrived = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: step.symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: arrived)
                    .frame(width: 62, height: 62)
                    .background(step.tint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: step.tint.opacity(0.35), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 30).padding(.top, 36)
        .onAppear { arrived += 1 }
    }
}

struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 11) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .settingsGlass(cornerRadius: 16, prominent: true)
    }
}

/// One of a few ways to go, picked by pressing it.
struct OnboardingChoice: View {
    let symbol: String
    let title: String
    let detail: String
    var badge = ""
    let tint: Color
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(selected ? Color.white : tint)
                    .frame(width: 38, height: 38)
                    .background(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        if !badge.isEmpty {
                            Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(tint.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 18))
                    .foregroundStyle(selected ? tint : Color.primary.opacity(0.18)).contentTransition(.symbolEffect(.replace))
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? tint.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .settingsGlass(cornerRadius: 16, prominent: true)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? tint.opacity(0.55) : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Whether something the guide checks is in place, in one line.
struct OnboardingStatus: View {
    let ready: Bool
    let text: String
    var body: some View {
        Label(text, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 14, weight: .medium)).foregroundStyle(ready ? Color.green : Color.orange)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// A device's photograph with its buttons marked: those being pressed light up, those already tried keep a tick,
/// and those given a number carry it.
struct OnboardingDevice: View {
    let template: DeviceTemplate
    var pressed: Set<DeviceControl> = []
    var tested: Set<DeviceControl> = []
    var numbered: [DeviceControl] = []
    private var artwork: DeviceArtwork { DeviceArtwork.forTemplate(template.id) }

    var body: some View {
        Group {
            if template.id == .keyboard { caps } else { photograph }
        }
        .background(LinearGradient(colors: [Color(red: 0.14, green: 0.18, blue: 0.24), Color(red: 0.07, green: 0.095, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var photograph: some View {
        GeometryReader { area in
            let ratio = artwork.aspectRatio
            let width = min(area.size.width - 24, (area.size.height - 24) * ratio), height = width / ratio
            let frame = CGRect(x: (area.size.width - width) / 2, y: (area.size.height - height) / 2, width: width, height: height)
            ZStack(alignment: .topLeading) {
                if let image = artwork.image {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 10)
                }
                ForEach(template.controls, id: \.id) { item in
                    if let point = artwork.hotspots[item.control] {
                        mark(item.control).position(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
                    }
                }
            }
        }
    }

    /// The keyboard has no photograph: its controls are key caps carrying the combinations that stand for them.
    private var caps: some View {
        let layout = KeyboardLayout.current
        return VStack(spacing: 9) {
            ForEach(template.controls, id: \.id) { item in
                let down = pressed.contains(item.control)
                HStack(spacing: 10) {
                    mark(item.control).frame(width: 24)
                    Text(layout.label(item.control).isEmpty ? "—" : layout.label(item.control)).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    // Beside a numbered list the list says what each one is for.
                    if numbered.isEmpty { Text(item.control.label).font(.system(size: 11)).opacity(0.7).lineLimit(1) }
                }
                .foregroundStyle(.white).padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 34)
                .background(down ? Color.green.opacity(0.55) : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.8))
                .animation(.spring(duration: 0.2), value: down)
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func mark(_ control: DeviceControl) -> some View {
        let down = pressed.contains(control), tried = tested.contains(control)
        if let number = numbered.firstIndex(of: control) {
            Text("\(number + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Color.teal.gradient, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5)).shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        } else if down || tried {
            ZStack {
                Circle().fill(Color.green.opacity(down ? 0.85 : 0.55))
                Circle().stroke(.white.opacity(0.9), lineWidth: 1.5)
                Circle().stroke(Color.green.opacity(down ? 0.5 : 0), lineWidth: 8).scaleEffect(down ? 1.5 : 1)
                if tried && !down { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
            }
            .frame(width: down ? 24 : 18, height: down ? 24 : 18)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: down)
        } else if numbered.isEmpty {
            Circle().fill(.black.opacity(0.12)).overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1)).frame(width: 13, height: 13)
        }
    }
}
