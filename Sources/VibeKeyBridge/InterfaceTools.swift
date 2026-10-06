import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import WandAgent

/// The size of a text control's contents and its selection, never the contents themselves.
struct TextCaret: Equatable {
    var characters: Int
    var location: Int
    var selected: Int
}

/// One control from the latest snapshot. Its id is its position in that snapshot.
struct InterfaceControl {
    let element: AXUIElement
    let kind: String
    var label: String
    var state = ""
    var secure = false
    var role = ""
}

/// What the latest picture of a window showed: where the window stood on screen, how large the picture
/// was, and the lines of text read in it, each with its box in the picture in pixels from the top left.
struct WindowPicture {
    struct Line: Equatable { var text: String; var box: CGRect }
    var pid: pid_t
    var frame: CGRect
    var size: CGSize
    var lines: [Line]

    /// A point of the picture as a point of the screen.
    func screen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + point.x * frame.width / size.width, y: frame.minY + point.y * frame.height / size.height)
    }
    /// The words standing at a point of the picture.
    func text(at point: CGPoint) -> String? { lines.first { $0.box.insetBy(dx: -3, dy: -3).contains(point) }?.text }
    /// How many lines hold these words, whatever their case and spacing.
    func count(of words: String) -> Int {
        func plain(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }
        let wanted = plain(words)
        return wanted.isEmpty ? 0 : lines.filter { plain($0.text).contains(wanted) }.count
    }
    /// The lines as the model reads them: an id, the words, and the middle of their box.
    var listing: String {
        guard !lines.isEmpty else { return "(no text could be read in the picture)" }
        var listed = ["text read in the picture, each line with the x,y of its middle:"]
        for (index, line) in lines.prefix(InterfaceTools.shownLimit).enumerated() {
            listed.append("t\(index + 1) \"\(line.text)\" \(Int(line.box.midX)),\(Int(line.box.midY))")
        }
        if lines.count > InterfaceTools.shownLimit { listed.append("(\(lines.count - InterfaceTools.shownLimit) more lines not shown)") }
        return listed.joined(separator: "\n")
    }
}

/// A place in a window that the model named: where it is on screen, and what stands there.
struct WindowPlace: Equatable {
    var point: CGPoint
    var label: String
}

/// Reads and operates the front window of one app through its accessibility
/// tree, the same structure a screen reader is given.
/// Field contents and document text are left out of what is read: a field is
/// reported as empty or not, never by what it holds. The one text read that is
/// not a control's name is what the app itself announces to a screen reader,
/// such as the level a control stands at. A picture of the window is taken
/// only through `picture`, which is offered to the model only when the user
/// has let it see; the text in it is read on this Mac. A place in that
/// picture is all there is to press in a window that publishes no controls:
/// `place` says where it is on screen, and the pointer is the caller's.
final class InterfaceTools: @unchecked Sendable {
    static let shownLimit = 150
    /// A picture is sent no larger than this along its longer side: sharp enough to read, small enough to send.
    static let pictureSide: CGFloat = 1600
    private let worker = DispatchQueue(label: "vibewand.interface", qos: .userInitiated)
    // All are touched on `worker` only.
    private var controls: [InterfaceControl] = []
    /// What the snapshot before this one held, to tell what an action brought or changed.
    private var known: Set<String> = []
    /// The positions the latest snapshot printed, for a picture to mark.
    private var shown: [Int] = []
    /// The latest picture the model was shown.
    private var seen: WindowPicture?
    private var prepared: Set<pid_t> = []

    /// `landmark` names a control the app's adapter knows by more than its label, from its role and label.
    /// `seeing` says whether the model may look at a window that publishes no controls.
    func snapshot(pid: pid_t, filter: String?, seeing: Bool = false,
                  landmark: @escaping (String, String) -> String? = { _, _ in nil }) async -> ToolOutcome {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.4)
            // An Electron app publishes its web content to accessibility only when asked.
            let first = self.prepared.insert(pid).inserted
            if first { AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
            guard let window = Self.window(of: application) else { return .failure("This app has no window to read.") }
            var found = Self.walk(window)
            if first, found.controls.count < 4 {
                // The tree is built after the request; give it a moment once.
                Thread.sleep(forTimeInterval: 0.35)
                found = Self.walk(window)
            }
            var named: [String: [Int]] = [:]
            for index in found.controls.indices {
                if let name = landmark(found.controls[index].role, found.controls[index].label) { named[name, default: []].append(index) }
            }
            // A chat titled after a model looks like the model picker by its label; the one that opens a menu is it.
            for (name, places) in named {
                for index in places where places.count == 1 || ["AXPopUpButton", "AXMenuButton"].contains(found.controls[index].role) {
                    found.controls[index].state = [found.controls[index].state, name].filter { !$0.isEmpty }.joined(separator: ", ")
                }
            }
            let marks = found.controls.map(Self.mark)
            let fresh = Set(marks.indices.filter { !self.known.isEmpty && !self.known.contains(marks[$0]) })
            self.controls = found.controls; self.known = Set(marks)
            let title = Self.attribute(window, kAXTitleAttribute) as? String ?? ""
            let listing = Self.describe(found.controls, window: title, filter: filter, truncated: found.truncated, fresh: fresh, seeing: seeing)
            self.shown = listing.shown
            return .ok(.string(listing.text))
        }
    }

    /// A picture of the app's front window, with the ids of the latest snapshot marked on the controls they
    /// name, and the text read in it. Nothing but that one window is in it.
    func picture(pid: pid_t) async -> ToolOutcome {
        let look = await look(pid: pid)
        guard let layout = look.layout, let image = look.image, let seen = look.seen, let picture = Self.mark(image, layout: layout) else {
            return .failure(look.error.isEmpty ? "The window could not be captured." : look.error)
        }
        await run { self.seen = seen }
        let marked = layout.marks.isEmpty ? "" : ", \(layout.marks.count) controls of the latest snapshot marked with their ids"
        return ToolOutcome(text: "window \"\(layout.title)\", \(Int(seen.size.width))×\(Int(seen.size.height)) px\(marked)\n\(seen.listing)", image: picture)
    }

    /// Whether more lines of the window show these words now than in the latest picture: how text typed into
    /// a field that cannot be read is known to have arrived. The picture taken for it stays on this Mac.
    func shows(_ words: String, pid: pid_t) async -> Bool {
        guard let before = await run({ self.seen }), before.pid == pid, let now = await look(pid: pid).seen else { return false }
        return now.count(of: words) > before.count(of: words)
    }

    /// The window as it stands: where it is, its picture as captured, and what is read in it.
    private func look(pid: pid_t) async -> (layout: Layout?, image: CGImage?, seen: WindowPicture?, error: String) {
        guard CGPreflightScreenCaptureAccess() else {
            return (nil, nil, nil, "VibeWand is not allowed to record the screen. The user can allow it in System Settings, under Privacy & Security, Screen & System Audio Recording.")
        }
        guard let layout = await run({ self.layout(pid: pid) }) else { return (nil, nil, nil, "This app has no window to look at.") }
        func apart(_ frame: CGRect) -> CGFloat {
            abs(frame.minX - layout.frame.minX) + abs(frame.minY - layout.frame.minY) + abs(frame.width - layout.frame.width) + abs(frame.height - layout.frame.height)
        }
        // The window server's record of the window the tree described: same app, same place.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.filter({ $0.owningApplication?.processID == pid && $0.windowLayer == 0 }).min(by: { apart($0.frame) < apart($1.frame) }),
              apart(window.frame) < 40 else { return (layout, nil, nil, "The window could not be found on screen.") }
        // Captured as sharp as the display shows it: small text does not survive a picture made small enough to send.
        let filter = SCContentFilter(desktopIndependentWindow: window), sharpness = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(layout.frame.width * sharpness); configuration.height = Int(layout.frame.height * sharpness)
        configuration.showsCursor = false; configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            return (layout, nil, nil, "The window could not be captured.")
        }
        let size = Self.pictureSize(image)
        let lines = await run { Self.read(image, size: size) }
        return (layout, image, WindowPicture(pid: pid, frame: layout.frame, size: size, lines: lines), "")
    }

    /// Reads the text a picture shows, on this Mac, in Chinese and English. Each line comes with its box in the
    /// picture as it is sent, `size` pixels counted from the top left, in the order a page is read.
    static func read(_ image: CGImage, size: CGSize) -> [WindowPicture.Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        return rows((request.results ?? []).flatMap { found -> [WindowPicture.Line] in
            guard let read = found.topCandidates(1).first else { return [] }
            // Vision's boxes are parts of the picture counted from its bottom left.
            func placed(_ box: CGRect) -> CGRect {
                CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height)
            }
            var words: [WindowPicture.Line] = []
            for word in read.string.split(separator: " ") {
                guard let box = try? read.boundingBox(for: word.startIndex..<word.endIndex)?.boundingBox else { words = []; break }
                words.append(.init(text: String(word), box: placed(box)))
            }
            if words.isEmpty { words = [.init(text: read.string, box: placed(found.boundingBox))] }
            // An icon is often read as a stray mark; a line with no letter or digit says nothing.
            return apart(words).filter { $0.text.contains(where: { $0.isLetter || $0.isNumber }) }.map { .init(text: String($0.text.prefix(80)), box: $0.box) }
        })
    }

    /// Words read as one line are one thing to press only when they stand together. The tabs of a row are read
    /// as a line too, and each is its own: words nearly a line's height apart, or more, are listed apart.
    static func apart(_ words: [WindowPicture.Line]) -> [WindowPicture.Line] {
        words.reduce(into: []) { parts, word in
            if let last = parts.last, word.box.minX - last.box.maxX < last.box.height * 0.8 {
                parts[parts.count - 1] = .init(text: last.text + " " + word.text, box: last.box.union(word.box))
            } else { parts.append(word) }
        }
    }

    /// The recogniser takes a long moment the first time an app uses it, half a minute on some Macs. This
    /// spends that moment before the first picture is asked for.
    static func warm() { _ = warmed }
    private static let warmed: Void = DispatchQueue.global(qos: .utility).async {
        let blank = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        if let blank { _ = read(blank, size: CGSize(width: 64, height: 64)) }
    }

    /// Orders lines as a page is read: row by row from the top, and from the left within a row.
    static func rows(_ lines: [WindowPicture.Line]) -> [WindowPicture.Line] {
        var rows: [[WindowPicture.Line]] = []
        for line in lines.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let head = rows.last?.first, line.box.midY - head.box.midY < head.box.height * 0.6 { rows[rows.count - 1].append(line) }
            else { rows.append([line]) }
        }
        return rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// Where a place the model named is on screen, and what stands there: a line of the latest picture, a control
    /// of the latest snapshot, or a point of the latest picture. On a miss, says what to do instead.
    func place(pid: pid_t, id: String?, x: Int?, y: Int?) async -> (place: WindowPlace?, error: String) {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.4)
            if let id, id.hasPrefix("e") {
                guard let index = Int(id.dropFirst()), self.controls.indices.contains(index - 1) else {
                    return (nil, "No such control in the latest snapshot. Take a new snapshot.")
                }
                let control = self.controls[index - 1]
                guard let frame = Self.frame(control.element), frame.width > 2, frame.height > 2 else {
                    return (nil, "\(control.kind) \"\(control.label)\" has no place on screen.")
                }
                return (WindowPlace(point: CGPoint(x: frame.midX, y: frame.midY), label: control.label), "")
            }
            guard let seen = self.seen, seen.pid == pid else { return (nil, "There is no picture of this window yet. Take ui_screenshot first.") }
            // A picture says where things were. Once the window has moved, its points are somewhere else.
            guard let window = Self.window(of: application), Self.frame(window) == seen.frame else {
                return (nil, "The window has moved or changed size since the picture. Take a new ui_screenshot.")
            }
            var spot: CGPoint, label: String
            if let id {
                guard id.hasPrefix("t"), let index = Int(id.dropFirst()), seen.lines.indices.contains(index - 1) else {
                    return (nil, "No such text in the latest picture. Take a new ui_screenshot.")
                }
                spot = CGPoint(x: seen.lines[index - 1].box.midX, y: seen.lines[index - 1].box.midY); label = seen.lines[index - 1].text
            } else if let x, let y {
                spot = CGPoint(x: x, y: y); label = seen.text(at: spot) ?? ""
                guard CGRect(origin: .zero, size: seen.size).contains(spot) else {
                    return (nil, "That point is outside the picture, which is \(Int(seen.size.width))×\(Int(seen.size.height)) px.")
                }
            } else { return (nil, "Name a place: an id, or both x and y.") }
            let point = seen.screen(spot)
            // A button without words still has a name where the app publishes its controls, and that name says what a click does.
            let named = Self.name(at: point, in: application)
            return (WindowPlace(point: point, label: [label, named].filter { !$0.isEmpty }.joined(separator: " · ")), "")
        }
    }

    /// The app whose window is on top at a point of the screen: the one a click there reaches.
    func owner(at point: CGPoint) async -> pid_t? {
        await run {
            let screen = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(screen, 0.4)
            var hit: AXUIElement?, pid: pid_t = 0
            guard AXUIElementCopyElementAtPosition(screen, Float(point.x), Float(point.y), &hit) == .success, let hit,
                  AXUIElementGetPid(hit, &pid) == .success else { return nil }
            return pid
        }
    }

    /// What accessibility calls the control at a point of the screen, or the one holding it.
    private static func name(at point: CGPoint, in application: AXUIElement) -> String {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit) == .success, var node = hit else { return "" }
        for _ in 0..<2 {
            let values = read(node)
            if let name = [values[2], values[3]].compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) { return String(name.prefix(80)) }
            guard let parent = element(attribute(node, kAXParentAttribute)) else { break }
            node = parent
        }
        return ""
    }

    /// Where a window is and where the controls of the latest snapshot are in it, in screen points from the top left.
    struct Layout {
        var title: String
        var frame: CGRect
        var marks: [(id: String, frame: CGRect)]
    }
    private func layout(pid: pid_t) -> Layout? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.4)
        guard let window = Self.window(of: application), let frame = Self.frame(window), frame.width > 1, frame.height > 1 else { return nil }
        let marks = shown.compactMap { index in
            Self.frame(controls[index].element).flatMap { $0.width > 2 && $0.height > 2 && frame.intersects($0) ? (id: "e\(index + 1)", frame: $0) : nil }
        }
        return Layout(title: Self.attribute(window, kAXTitleAttribute) as? String ?? "", frame: frame, marks: marks)
    }

    /// The size a captured window is sent at.
    static func pictureSize(_ image: CGImage) -> CGSize {
        let shrink = min(1, pictureSide / CGFloat(max(image.width, image.height)))
        return CGSize(width: (CGFloat(image.width) * shrink).rounded(), height: (CGFloat(image.height) * shrink).rounded())
    }

    /// Draws each control's outline and id over the picture and returns it as a JPEG of the size it is sent at.
    static func mark(_ image: CGImage, layout: Layout) -> Data? {
        let size = pictureSize(image), scale = size.width / layout.frame.width
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        // Controls are placed from the window's top left; the picture is drawn from its bottom left.
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let font = NSFont.monospacedSystemFont(ofSize: 10 * max(1, scale), weight: .bold)
        for mark in layout.marks {
            let box = CGRect(x: (mark.frame.minX - layout.frame.minX) * scale, y: (mark.frame.minY - layout.frame.minY) * scale,
                             width: mark.frame.width * scale, height: mark.frame.height * scale)
            NSColor.systemPink.setStroke()
            let outline = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); outline.lineWidth = 1; outline.stroke()
            let text = NSAttributedString(string: mark.id, attributes: [.font: font, .foregroundColor: NSColor.white])
            let extent = text.size()
            let tag = CGRect(x: box.minX, y: box.minY, width: extent.width + 4, height: extent.height)
            NSColor.systemPink.setFill(); tag.fill()
            text.draw(at: CGPoint(x: tag.minX + 2, y: tag.minY))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) }
    }

    /// What the app has announced since the latest snapshot or the last call: the status lines that now say something else.
    func announced() async -> [String] {
        await run {
            guard self.controls.contains(where: { $0.kind == "status" }) else { return [] }
            // An app announces a moment after the key that caused it.
            Thread.sleep(forTimeInterval: 0.25)
            var said: [String] = []
            for index in self.controls.indices where self.controls[index].kind == "status" {
                let now = Self.childText(Self.attribute(self.controls[index].element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
                guard !now.isEmpty, now != self.controls[index].label else { continue }
                self.controls[index].label = now
                said.append(now)
            }
            // The next snapshot compares with what the model has now been told.
            self.known.formUnion(self.controls.map(Self.mark))
            return said
        }
    }

    func control(_ id: String) async -> InterfaceControl? {
        await run {
            guard id.hasPrefix("e"), let index = Int(id.dropFirst()), self.controls.indices.contains(index - 1) else { return nil }
            return self.controls[index - 1]
        }
    }

    func press(_ control: InterfaceControl) async -> ToolOutcome {
        await run {
            AXUIElementSetMessagingTimeout(control.element, 1)
            var result = AXUIElementPerformAction(control.element, kAXPressAction as CFString)
            if result != .success, result != .cannotComplete, Self.settable(control.element, kAXSelectedAttribute) {
                result = AXUIElementSetAttributeValue(control.element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            }
            switch result {
            case .success: return .ok(["pressed": .string(control.label)])
            // A press that opens a sheet may not answer in time although it took effect.
            case .cannotComplete: return .ok(["pressed": .string(control.label), "note": "no reply from the app; take a snapshot to check"], verified: false)
            default: return .failure("\(control.kind) \"\(control.label)\" cannot be pressed. Take a new snapshot or use a shortcut.")
            }
        }
    }

    /// Finds a menu bar item by its path of titles. On a miss, names what that level offers.
    func menuItem(pid: pid_t, path: [String]) async -> (control: InterfaceControl?, error: String) {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.6)
            guard var node = Self.element(Self.attribute(application, kAXMenuBarAttribute)) else { return (nil, "This app has no menu bar.") }
            var title = ""
            for wanted in path {
                var items = Self.attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                // A menu bar item and a submenu item each hold one AXMenu with the entries.
                if items.count == 1, Self.attribute(items[0], kAXRoleAttribute) as? String == "AXMenu" {
                    items = Self.attribute(items[0], kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
                let titles = items.map { Self.attribute($0, kAXTitleAttribute) as? String ?? "" }
                guard let index = Self.match(wanted, in: titles) else {
                    let offered = titles.filter { !$0.isEmpty }.prefix(30).joined(separator: ", ")
                    return (nil, "No menu item \"\(wanted)\". Available here: \(offered)")
                }
                node = items[index]; title = titles[index]
            }
            guard Self.attribute(node, kAXEnabledAttribute) as? Bool != false else { return (nil, "Menu item \"\(title)\" is disabled.") }
            return (InterfaceControl(element: node, kind: "item", label: title), "")
        }
    }

    /// Whether the app has a window on the Space in front. An app sliding in from another Space is
    /// already frontmost while it still has none, and keys sent to it then can be lost.
    func hasWindowHere(pid: pid_t) async -> Bool {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            return !(Self.attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []).isEmpty
        }
    }

    /// Role of the control that has keyboard focus, for deciding what Return would do.
    func focusedRole(pid: pid_t) async -> String {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            guard let focused = Self.element(Self.attribute(application, kAXFocusedUIElementAttribute)) else { return "" }
            return Self.attribute(focused, kAXRoleAttribute) as? String ?? ""
        }
    }

    /// How much the focused text control holds and where its caret is: enough to tell whether typed text
    /// arrived, without reading what the control contains. nil when no readable text control has the keyboard.
    func caret(pid: pid_t) async -> TextCaret? {
        await run {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            guard let focused = Self.element(Self.attribute(application, kAXFocusedUIElementAttribute)),
                  ["AXTextField", "AXTextArea", "AXComboBox"].contains(Self.attribute(focused, kAXRoleAttribute) as? String ?? "") else { return nil }
            let characters = (Self.attribute(focused, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
            var selection: CFRange?
            if let value = Self.attribute(focused, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(value as! AXValue, .cfRange, &range) { selection = range }
            }
            guard characters != nil || selection != nil else { return nil }
            return TextCaret(characters: characters ?? -1, location: selection?.location ?? -1, selected: selection?.length ?? -1)
        }
    }

    /// Gives a control keyboard focus, or reports whether the focused one refuses text. nil when the keyboard may go there.
    func focus(pid: pid_t, control: InterfaceControl?) async -> String? {
        await run {
            if let control {
                guard !control.secure else { return "Password fields are never typed into." }
                AXUIElementSetMessagingTimeout(control.element, 0.6)
                guard AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
                    return "\(control.kind) \"\(control.label)\" does not take keyboard focus."
                }
                return nil
            }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            // An app that publishes no controls names no focus either. In a window the model is working from a
            // picture of, the keyboard is where its last click put it.
            guard let focused = Self.element(Self.attribute(application, kAXFocusedUIElementAttribute)) else {
                return self.seen?.pid == pid ? nil : "Nothing has keyboard focus."
            }
            return Self.attribute(focused, kAXSubroleAttribute) as? String == "AXSecureTextField" ? "Password fields are never typed into." : nil
        }
    }

    private func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in worker.async { continuation.resume(returning: work()) } }
    }

    // MARK: Reading the tree

    private static let kinds: [String: String] = [
        "AXButton": "button", "AXRadioButton": "radio", "AXCheckBox": "checkbox", "AXPopUpButton": "menu", "AXMenuButton": "menu",
        "AXComboBox": "combo", "AXTextField": "field", "AXTextArea": "text", "AXLink": "link", "AXMenuItem": "item", "AXRow": "row",
        "AXCell": "cell", "AXSlider": "slider", "AXDisclosureTriangle": "disclosure", "AXIncrementor": "stepper", "AXSwitch": "switch"
    ]
    /// Nothing inside these is a control worth listing; skipping them keeps large windows fast.
    private static let leaves: Set<String> = ["AXStaticText", "AXImage", "AXScrollBar", "AXValueIndicator", "AXHeading", "AXSplitter", "AXRuler"]
    private static let batch = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute,
                                kAXSelectedAttribute, kAXChildrenAttribute, kAXNumberOfCharactersAttribute, "AXPlaceholderValue",
                                "AXKeyShortcutsValue"] as [String]
    /// What a web app marks as said aloud to a screen reader: a status line or an alert.
    private static let announcements: Set<String> = ["AXApplicationStatus", "AXApplicationAlert"]

    static func walk(_ root: AXUIElement, budget: TimeInterval = 1.5) -> (controls: [InterfaceControl], truncated: Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var found: [InterfaceControl] = [], stack = [root], visited = 0
        while let node = stack.popLast() {
            visited += 1
            if visited > 5000 || ProcessInfo.processInfo.systemUptime > deadline { return (found, true) }
            let values = read(node)
            guard let role = values[0] as? String, !leaves.contains(role) else { continue }
            let children = values[6] as? [AXUIElement] ?? [], subrole = values[1] as? String ?? ""
            guard let kind = kinds[role] else {
                // An announcement is short by nature; one that is not is left unread, like any other text.
                if announcements.contains(subrole) {
                    let said = childText(children)
                    if !said.isEmpty { found.append(InterfaceControl(element: node, kind: "status", label: said, role: role)) }
                } else { stack.append(contentsOf: children.reversed()) }
                continue
            }
            let isText = role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox"
            var label = [values[2], values[3], isText ? values[8] : nil].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            // Web buttons and list rows carry their name in a text child.
            if label.isEmpty, !isText { label = childText(children) }
            label = String(label.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces).prefix(80))
            guard !label.isEmpty || isText else {
                // An unnamed container row may still hold named controls.
                if role == "AXRow" || role == "AXCell" { stack.append(contentsOf: children.reversed()) }
                continue
            }
            var states: [String] = []
            if values[5] as? Bool == true { states.append("selected") }
            else if ["AXRadioButton", "AXCheckBox", "AXSwitch", "AXMenuItem"].contains(role),
                    (attribute(node, kAXValueAttribute) as? NSNumber)?.intValue == 1 {
                states.append(role == "AXRadioButton" ? "selected" : role == "AXMenuItem" ? "checked" : "on")
            }
            if values[4] as? Bool == false { states.append("disabled") }
            if isText { states.append((values[7] as? NSNumber)?.intValue ?? 0 > 0 ? "has text" : "empty") }
            // The keys a web control says it is worked with: a level set with the arrows, for one.
            if let keys = values[9] as? String, !keys.isEmpty { states.append("keys: \(keys.prefix(60))") }
            found.append(InterfaceControl(element: node, kind: subrole == "AXTabButton" ? "tab" : subrole == "AXSearchField" ? "search" : kind,
                                          label: label.isEmpty ? "(unnamed)" : label, state: states.joined(separator: ", "),
                                          secure: subrole == "AXSecureTextField", role: role))
        }
        return (found, false)
    }

    /// What tells one listed control from another, and from itself once its name or state has changed.
    private static func mark(_ control: InterfaceControl) -> String {
        "\(CFHash(control.element))|\(control.kind)|\(control.label)|\(control.state)"
    }

    /// The listing the model reads, and which positions it printed. `fresh` are the positions that are new or
    /// changed since the snapshot before: they lead, so that what a press opened is not lost below a long window.
    /// A window with nothing to list is one to look at instead, when `seeing` says the model may.
    static func describe(_ controls: [InterfaceControl], window: String, filter: String?, truncated: Bool,
                         fresh: Set<Int> = [], seeing: Bool = false) -> (text: String, shown: [Int]) {
        let needle = filter?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let matching = controls.indices.filter {
            needle.isEmpty || controls[$0].label.lowercased().contains(needle) || controls[$0].kind == needle || controls[$0].state.lowercased().contains(needle)
        }
        // With everything new there is nothing to set apart: another window, or a view that was replaced.
        let lead = matching.filter(fresh.contains), apart = !lead.isEmpty && lead.count < matching.count
        let shown = Array(((apart ? lead : []) + matching.filter { !apart || !fresh.contains($0) }).prefix(shownLimit))
        var lines = ["window \"\(window)\""]
        for (place, index) in shown.enumerated() {
            if apart, place == 0 { lines.append("new or changed since the last snapshot:") }
            if apart, place == lead.count { lines.append("as before:") }
            let control = controls[index]
            lines.append("e\(index + 1) \(control.kind) \"\(control.label)\"" + (control.state.isEmpty ? "" : " \(control.state)"))
        }
        if controls.isEmpty {
            // Some apps draw their whole window themselves and tell accessibility nothing of it.
            lines.append(seeing ? "(this window publishes no controls. Take ui_screenshot and operate it from its picture with ui_click)"
                : "(this window publishes no controls. It can only be operated from its picture, which the user has to allow: \"\(CommandSettings.sightTitle)\" under Command mode in VibeWand's settings. Call need_user and say so)")
        } else if matching.isEmpty { lines.append("(no control matches \"\(needle)\")") }
        if matching.count > shownLimit { lines.append("(\(matching.count - shownLimit) more not shown; pass filter to narrow)") }
        if truncated { lines.append("(the window was too large to read completely; pass filter or use a shortcut)") }
        return (lines.joined(separator: "\n"), shown)
    }

    /// Picks the menu title that the model most plausibly meant.
    static func match(_ wanted: String, in titles: [String]) -> Int? {
        func plain(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces)
        }
        let target = plain(wanted), candidates = titles.map(plain)
        guard !target.isEmpty else { return nil }
        return candidates.firstIndex(of: target) ?? candidates.firstIndex { !$0.isEmpty && $0.hasPrefix(target) }
            ?? candidates.firstIndex { $0.contains(target) }
    }

    private static func childText(_ children: [AXUIElement]) -> String {
        var texts: [String] = [], queue = Array(children.prefix(6)), seen = 0
        while !queue.isEmpty, texts.count < 2, seen < 12 {
            let node = queue.removeFirst(); seen += 1
            let values = read(node)
            if values[0] as? String == "AXStaticText" {
                let text = (attribute(node, kAXValueAttribute) as? String ?? values[2] as? String ?? "")
                if !text.isEmpty, text.count <= 80 { texts.append(text) }
            } else { queue.append(contentsOf: (values[6] as? [AXUIElement] ?? []).prefix(4)) }
        }
        return texts.joined(separator: " · ")
    }

    private static func read(_ node: AXUIElement) -> [Any?] {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, batch as CFArray, [], &values) == .success,
              let array = values as? [Any], array.count == batch.count else { return Array(repeating: nil, count: batch.count) }
        // A missing attribute comes back as an AXValue holding the error.
        return array.map { CFGetTypeID($0 as CFTypeRef) == AXValueGetTypeID() ? nil : $0 }
    }
    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
    /// The window of an app that has the keyboard, or its main one.
    private static func window(of application: AXUIElement) -> AXUIElement? {
        element(attribute(application, kAXFocusedWindowAttribute)) ?? element(attribute(application, kAXMainWindowAttribute))
    }
    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func frame(_ node: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let position = attribute(node, kAXPositionAttribute), let extent = attribute(node, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
    private static func settable(_ node: AXUIElement, _ name: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(node, name as CFString, &result) == .success && result.boolValue
    }
}

extension KeyStroke {
    private static let named: [String: ApplicationKey] = [
        "return": .returnKey, "enter": .returnKey, "esc": .escape, "escape": .escape, "tab": .tab, "space": .space,
        "delete": .backspace, "backspace": .backspace, "forwarddelete": .forwardDelete, "up": .up, "down": .down, "left": .left,
        "right": .right, "arrowup": .up, "arrowdown": .down, "arrowleft": .left, "arrowright": .right,
        "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four, "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
        "-": .minus, "=": .equals, "[": .leftBracket, "]": .rightBracket, "\\": .backslash, ";": .semicolon, "'": .quote,
        ",": .comma, ".": .period, "/": .slash, "`": .grave
    ]
    var isReturn: Bool { code == 36 || code == 76 }

    /// Reads one chord such as "cmd+shift+p", "ctrl+tab" or "escape".
    static func parse(_ text: String) -> KeyStroke? {
        var flags: CGEventFlags = [], key: ApplicationKey?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default:
                guard key == nil, let parsed = named[part] ?? ApplicationKey(rawValue: part) else { return nil }
                key = parsed
            }
        }
        return key.map { KeyStroke(code: $0.keyCode, flags: flags) }
    }

    /// Delivered to one process, and marked so VibeWand's own keyboard listener ignores it.
    func post(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: AccessibilityAdapter.syntheticMarker)
            event.postToPid(pid)
        }
    }
}
