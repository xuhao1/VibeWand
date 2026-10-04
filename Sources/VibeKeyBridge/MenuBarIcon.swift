import AppKit

/// A resolution-independent template mark, tinted by the system menu bar.
@MainActor
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            func stroke(from start: NSPoint, to end: NSPoint, width: CGFloat) {
                let path = NSBezierPath()
                path.lineWidth = width
                path.lineCapStyle = .round
                path.move(to: start)
                path.line(to: end)
                path.stroke()
            }
            // A single bold wand with a separated tip stays readable at 18 pt.
            stroke(from: NSPoint(x: 3, y: 3), to: NSPoint(x: 10.8, y: 10.8), width: 3.2)
            stroke(from: NSPoint(x: 13.4, y: 13.4), to: NSPoint(x: 15, y: 15), width: 3.2)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "VibeWand"
        return image
    }
}
