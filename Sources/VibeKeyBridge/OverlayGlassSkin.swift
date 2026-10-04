import AppKit

/// Optical highlights are shared by the live HUD and its exported review image.
/// Native glass underneath supplies the actual backdrop blur and refraction.
@MainActor
enum OverlayGlassSkin {
    static func panel(in rect: NSRect, dark: Bool, exporting: Bool, optics: Bool = true) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            NSColor.windowBackgroundColor.setFill(); path.fill()
        } else {
            let colors: [NSColor]
            if exporting {
                colors = dark ? [NSColor(srgbRed: 0.20, green: 0.25, blue: 0.34, alpha: 1), NSColor(srgbRed: 0.10, green: 0.13, blue: 0.20, alpha: 1)]
                    : [NSColor(srgbRed: 0.91, green: 0.94, blue: 0.99, alpha: 1), NSColor(srgbRed: 0.77, green: 0.83, blue: 0.92, alpha: 1)]
            } else {
                colors = dark ? [NSColor(srgbRed: 0.21, green: 0.27, blue: 0.37, alpha: 0.21), NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.30)]
                    : [NSColor.white.withAlphaComponent(0.29), NSColor(srgbRed: 0.83, green: 0.90, blue: 1, alpha: 0.13)]
            }
            NSGradient(colors: colors)?.draw(in: rect, angle: 90)
            if optics {
                let glow = NSBezierPath(ovalIn: NSRect(x: -rect.width * 0.16, y: -rect.height * 0.15, width: rect.width * 1.15, height: rect.height * 0.72))
                NSGradient(starting: .white.withAlphaComponent(dark ? 0.12 : 0.39), ending: .white.withAlphaComponent(0))?
                    .draw(in: glow, relativeCenterPosition: NSPoint(x: -0.35, y: -0.4))
            }
        }
        NSColor.white.withAlphaComponent(dark ? 0.065 : 0.22).setFill()
        NSRect(x: 0, y: 0, width: rect.width, height: 48).fill()
        NSColor.white.withAlphaComponent(dark ? 0.10 : 0.30).setStroke()
        let divider = NSBezierPath(); divider.move(to: NSPoint(x: 0, y: 48)); divider.line(to: NSPoint(x: rect.width, y: 48)); divider.lineWidth = 0.6; divider.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func rim(in rect: NSRect, dark: Bool, optics: Bool = true) {
        let outer = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: 25.4, yRadius: 25.4)
        NSColor.white.withAlphaComponent(dark ? 0.36 : 0.75).setStroke(); outer.lineWidth = 1.1; outer.stroke()
        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 24, yRadius: 24)
        NSColor.white.withAlphaComponent(dark ? 0.05 : 0.16).setStroke(); inner.lineWidth = 0.6; inner.stroke()
    }

    static func pill(in rect: NSRect, dark: Bool, emphasized: Bool = false, optics: Bool = true) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.24 : 0.12)
        shadow.shadowBlurRadius = optics ? (emphasized ? 9 : 5) : 0; shadow.shadowOffset = NSSize(width: 0, height: optics ? 2 : 0); shadow.set()
        let base = emphasized ? NSColor.systemBlue.withAlphaComponent(dark ? 0.17 : 0.16) : NSColor.white.withAlphaComponent(dark ? 0.045 : 0.30)
        base.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        NSGradient(starting: .white.withAlphaComponent(dark ? 0.14 : 0.47), ending: .white.withAlphaComponent(dark ? 0.025 : 0.06))?
            .draw(in: rect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        let stroke = emphasized ? NSColor.systemBlue.withAlphaComponent(0.82) : NSColor.white.withAlphaComponent(dark ? 0.28 : 0.71)
        stroke.setStroke(); path.lineWidth = emphasized ? 1.25 : 0.8; path.stroke()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: max(0, rect.height / 2 - 1.5), yRadius: max(0, rect.height / 2 - 1.5))
        NSColor.white.withAlphaComponent(emphasized ? 0.25 : dark ? 0.025 : 0.16).setStroke(); edge.lineWidth = 0.5; edge.stroke()
    }

    static func focus(at point: NSPoint, dark: Bool, optics: Bool = true) {
        let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 11.5, y: point.y - 11.5, width: 23, height: 23))
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.65); glow.shadowBlurRadius = optics ? 10 : 0; glow.set()
        NSColor.systemBlue.setStroke(); ring.lineWidth = 2; ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let inner = NSBezierPath(ovalIn: NSRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        NSColor.white.withAlphaComponent(0.7).setStroke(); inner.lineWidth = 0.65; inner.stroke()
    }

}
