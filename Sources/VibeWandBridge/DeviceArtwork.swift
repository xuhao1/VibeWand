import AppKit

/// Product photographs with manually inspected control centers. Coordinates use
/// the full image rectangle, with the origin at its top-left, before aspect-fit.
struct DeviceArtwork {
    let imageName: String
    let aspectRatio: CGFloat
    let hotspots: [DeviceControl: CGPoint]

    /// App bundle assets in releases, source assets when running with SwiftPM.
    @MainActor private static var imageCache: [String: NSImage] = [:]
    @MainActor var image: NSImage? {
        if let image = Self.imageCache[imageName] { return image }
        if let url = Bundle.main.url(forResource: imageName, withExtension: "png"), let image = NSImage(contentsOf: url) { Self.imageCache[imageName] = image; return image }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let image = NSImage(contentsOf: root.appendingPathComponent("assets/device/\(imageName).png"))
        Self.imageCache[imageName] = image
        return image
    }

    @MainActor var overlayImage: NSImage? {
        guard imageName == "gamepad" else { return image }
        return DeviceArtwork(imageName: "gamepad-overlay", aspectRatio: aspectRatio, hotspots: hotspots).image ?? image
    }

    static func forTemplate(_ id: DeviceTemplateID) -> DeviceArtwork {
        switch id {
        // The keyboard has no photograph; its controls are drawn as key caps.
        case .keyboard: return DeviceArtwork(imageName: "", aspectRatio: 1, hotspots: [:])
        case .vibeKey:
            return DeviceArtwork(imageName: "controller", aspectRatio: 1080.0 / 1440.0, hotspots: [
                .dial: CGPoint(x: 0.500, y: 0.324),
                .left: CGPoint(x: 0.393, y: 0.324),
                .right: CGPoint(x: 0.609, y: 0.324),
                .voice: CGPoint(x: 0.500, y: 0.520),
                .ok: CGPoint(x: 0.500, y: 0.668),
                .escape: CGPoint(x: 0.500, y: 0.818)
            ])
        case .dualSense:
            return DeviceArtwork(imageName: "gamepad", aspectRatio: 1536.0 / 1024.0, hotspots: [
                .r1: CGPoint(x: 0.782, y: 0.136),
                .r2: CGPoint(x: 0.783, y: 0.070),
                .dial: CGPoint(x: 0.7305, y: 0.3711),
                .ok: CGPoint(x: 0.7956, y: 0.4697),
                .escape: CGPoint(x: 0.860, y: 0.3711),
                .voice: CGPoint(x: 0.7956, y: 0.2725),
                .l1: CGPoint(x: 0.218, y: 0.136),
                .l2: CGPoint(x: 0.216, y: 0.070),
                .leftStickPress: CGPoint(x: 0.352, y: 0.559),
                .rightStickPress: CGPoint(x: 0.650, y: 0.559),
                .leftStickUp: CGPoint(x: 0.352, y: 0.462),
                .leftStickDown: CGPoint(x: 0.352, y: 0.656),
                .leftStickLeft: CGPoint(x: 0.287, y: 0.559),
                .leftStickRight: CGPoint(x: 0.417, y: 0.559),
                .rightStickUp: CGPoint(x: 0.650, y: 0.462),
                .rightStickDown: CGPoint(x: 0.650, y: 0.656),
                .rightStickLeft: CGPoint(x: 0.585, y: 0.559),
                .rightStickRight: CGPoint(x: 0.715, y: 0.559),
                .dpadUp: CGPoint(x: 0.209, y: 0.303),
                .dpadDown: CGPoint(x: 0.209, y: 0.444),
                .dpadLeft: CGPoint(x: 0.1595, y: 0.3711),
                .dpadRight: CGPoint(x: 0.2526, y: 0.3711),
                .options: CGPoint(x: 0.7031, y: 0.2344),
                .create: CGPoint(x: 0.295, y: 0.2344),
                .home: CGPoint(x: 0.500, y: 0.555),
                .touchpad: CGPoint(x: 0.500, y: 0.277),
                .mute: CGPoint(x: 0.500, y: 0.640)
            ])
        case .xiaomiRemote:
            return DeviceArtwork(imageName: "remote", aspectRatio: 1024.0 / 1536.0, hotspots: [
                .voice: CGPoint(x: 0.500, y: 0.180),
                .dial: CGPoint(x: 0.500, y: 0.333),
                .left: CGPoint(x: 0.391, y: 0.333),
                .right: CGPoint(x: 0.608, y: 0.333),
                .escape: CGPoint(x: 0.391, y: 0.483),
                .ok: CGPoint(x: 0.608, y: 0.483),
                .power: CGPoint(x: 0.500, y: 0.0944),
                .home: CGPoint(x: 0.500, y: 0.483),
                .volumeUp: CGPoint(x: 0.500, y: 0.569),
                .volumeDown: CGPoint(x: 0.500, y: 0.641),
                .dpadUp: CGPoint(x: 0.500, y: 0.262),
                .dpadDown: CGPoint(x: 0.500, y: 0.404)
            ])
        }
    }
}
