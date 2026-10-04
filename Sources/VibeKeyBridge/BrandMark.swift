import AppKit
import SwiftUI

/// The in-app brand artwork follows the surrounding system appearance.
struct BrandMark: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private static let lightImage = load("BrandMarkLight", extension: "png")
    private static let darkImage = load("AppIcon", extension: "icns")
        ?? load("AppIcon", extension: "png")

    var body: some View {
        Group {
            if let image = colorScheme == .dark ? Self.darkImage : (Self.lightImage ?? Self.darkImage) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func load(_ name: String, extension suffix: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: suffix),
           let image = NSImage(contentsOf: url) { return image }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: root.appendingPathComponent("assets/app-icon/\(name).\(suffix)"))
    }
}
