import AppKit
import SwiftUI
import AU05Device

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

enum SettingsStyle {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.5" }
}

/// A system material that follows the window appearance without intercepting controls above it.
struct SettingsBackdrop: View {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                NativeSettingsBackdrop(material: material, blendingMode: blendingMode)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NativeSettingsBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> PassthroughVisualEffectView {
        let view = PassthroughVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: PassthroughVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct SettingsGlass: ViewModifier {
    let cornerRadius: CGFloat
    let prominent: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else if prominent {
                    shape.fill(.regularMaterial)
                } else {
                    shape.fill(.thinMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.24 : (colorScheme == .dark ? 0.11 : 0.07)),
                    lineWidth: 0.75
                ).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.025), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func settingsGlass(cornerRadius: CGFloat = 12, prominent: Bool = false) -> some View {
        modifier(SettingsGlass(cornerRadius: cornerRadius, prominent: prominent))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StandardPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider().opacity(0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .frame(maxWidth: 1100, alignment: .leading).padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .settingsGlass()
    }
}
