import CoreGraphics

/// Routes a wheel event over the content column, rather than the text box,
/// sidebar or wherever the physical mouse was left. Coordinates use Quartz AX
/// geometry; generating a wheel event does not move the physical cursor.
enum ScrollTarget {
    static func point(window: CGRect?, composer: CGRect?, scrollArea: CGRect?, popup: CGRect?, viewport: CGRect? = nil) -> CGPoint? {
        if let popup, valid(popup) { return CGPoint(x: popup.midX, y: popup.midY) }
        if let viewport, valid(viewport) {
            let visible = window.map { viewport.intersection($0) } ?? viewport
            if valid(visible) { return CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.4) }
        }
        if let window, valid(window), let composer, valid(composer) {
            return CGPoint(x: min(window.maxX - 20, max(window.minX + 20, composer.midX)),
                           y: max(window.minY + 20, min(window.maxY - 20, min(composer.minY - 30, window.minY + window.height * 0.4))))
        }
        if let scrollArea, valid(scrollArea) { return CGPoint(x: scrollArea.midX, y: scrollArea.midY) }
        guard let window, valid(window) else { return nil }
        return CGPoint(x: window.minX + window.width * 0.6, y: window.minY + window.height * 0.4)
    }
    private static func valid(_ frame: CGRect) -> Bool {
        frame.width > 40 && frame.height > 20 && frame.minX.isFinite && frame.minY.isFinite &&
        frame.width.isFinite && frame.height.isFinite
    }
}

enum SliderTarget {
    static func point(frame: CGRect, value: Double?, minimum: Double?, maximum: Double?, vertical: Bool) -> CGPoint {
        let ratio: Double
        if let value, let minimum, let maximum, value.isFinite, minimum.isFinite, maximum.isFinite, maximum > minimum {
            ratio = min(1, max(0, (value - minimum) / (maximum - minimum)))
        } else { ratio = 0.5 }
        if vertical { return CGPoint(x: frame.midX, y: frame.maxY - frame.height * ratio) }
        return CGPoint(x: frame.minX + frame.width * ratio, y: frame.midY)
    }
}
