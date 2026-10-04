import AppKit

/// A resolution-independent template mark, tinted by the system menu bar.
@MainActor
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            func stroke(_ points: [NSPoint], width: CGFloat) {
                let path = NSBezierPath()
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: points[0])
                for point in points.dropFirst() { path.line(to: point) }
                path.stroke()
            }

            // The diagonal wand and separated code brackets carry the app identity.
            stroke([NSPoint(x: 2.5, y: 2.5), NSPoint(x: 11.3, y: 11.3)], width: 2.6)
            stroke([NSPoint(x: 15.1, y: 15.4), NSPoint(x: 12.9, y: 13.2), NSPoint(x: 15.1, y: 11)], width: 1.6)
            stroke([NSPoint(x: 17.5, y: 15.4), NSPoint(x: 19.7, y: 13.2), NSPoint(x: 17.5, y: 11)], width: 1.6)

            // Five short voice bars remain secondary at menu-bar scale.
            for (x, height) in [(13.2, 1.3), (14.6, 2.6), (16.0, 4.0), (17.4, 2.6), (18.8, 1.3)] {
                stroke([NSPoint(x: x, y: 5 - height / 2), NSPoint(x: x, y: 5 + height / 2)], width: 1.1)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "VibeWand"
        return image
    }
}
