import CoreGraphics

/// System wheel routing follows the pointer's hit-test window. Move, wheel and
/// restore are queued in order so the physical mouse position is preserved.
enum SystemPointer {
    private static let marker: Int64 = 0x564942454B4559
    static func move(to point: CGPoint) {
        let source = CGEventSource(stateID: .privateState)
        let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
        event?.post(tap: .cghidEventTap)
    }
    static func relativeTarget(from origin: CGPoint, motion: ControllerPointerMotion, displays: [CGRect]) -> CGPoint {
        guard motion.dx.isFinite, motion.dy.isFinite else { return origin }
        let target = CGPoint(x: origin.x + motion.dx, y: origin.y + motion.dy)
        let candidates = displays.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }.map { rect in
            CGPoint(x: min(rect.maxX - 1, max(rect.minX, target.x)),
                    y: min(rect.maxY - 1, max(rect.minY, target.y)))
        }
        return candidates.min { a, b in
            hypot(a.x - target.x, a.y - target.y) < hypot(b.x - target.x, b.y - target.y)
        } ?? origin
    }
    static func move(relative motion: ControllerPointerMotion) {
        guard let origin = CGEvent(source: nil)?.location else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: 32), count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return }
        let bounds = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        let target = relativeTarget(from: origin, motion: motion, displays: bounds)
        if target != origin { move(to: target) }
    }
    static func clickAtCursor() {
        if let point = CGEvent(source: nil)?.location { click(at: point) }
    }
    static func scroll(delta: Int32, at point: CGPoint) {
        let original = CGEvent(source: nil)?.location
        move(to: point)
        let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .privateState), units: .pixel,
                            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        event?.location = point; event?.flags = []
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
        event?.post(tap: .cghidEventTap)
        if let original { move(to: original) }
    }
    static func click(at point: CGPoint) {
        move(to: point)
        let source = CGEventSource(stateID: .privateState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.setIntegerValueField(.eventSourceUserData, value: marker)
            event?.post(tap: .cghidEventTap)
        }
    }
}

struct CandidateNavigation {
    private(set) var root: UInt?
    private(set) var index: Int?
    mutating func move(root: UInt, count: Int, selected: Int?, direction: Int) -> Int? {
        guard count > 0 else { return nil }
        if self.root != root { self.root = root; index = selected }
        if let index { self.index = min(count - 1, max(0, index + direction)) }
        else { index = direction < 0 ? count - 1 : 0 }
        return index
    }
    mutating func reset() { root = nil; index = nil }
}
