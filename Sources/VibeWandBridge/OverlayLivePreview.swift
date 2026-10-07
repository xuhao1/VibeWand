import SwiftUI
import AppKit

/// Uses the same native view tree as the floating panel, including its glass
/// layers. Preview interactions never emit device or mouse actions.
struct OverlayLivePreview: NSViewRepresentable {
    var snapshot: HUDSnapshot
    var expanded: Bool
    var opacity: Double
    var mode: OverlayDisplayMode = .full

    func makeNSView(context: Context) -> NSView { OverlayController.makeLivePreview() }
    func updateNSView(_ view: NSView, context: Context) {
        OverlayController.updateLivePreview(view, snapshot: snapshot, expanded: expanded, mode: mode)
        view.alphaValue = opacity
    }
}

struct OverlayPreviewBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [.blue.opacity(scheme == .dark ? 0.21 : 0.15), .indigo.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(.orange.opacity(scheme == .dark ? 0.17 : 0.22))
                    .frame(width: geometry.size.width * 0.6, height: 150).blur(radius: 48)
                    .offset(x: -geometry.size.width * 0.3, y: -geometry.size.height * 0.3)
                Ellipse().fill(.blue.opacity(0.28)).frame(width: geometry.size.width * 0.8, height: 210)
                    .blur(radius: 55).offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.3)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
