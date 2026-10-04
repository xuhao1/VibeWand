import AppKit

// Export the approved raster artwork; only normalize its outer alpha boundary.
// The path follows the tile in the 1254 px reference, preserving its inner rim.
guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let input = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Usage: swift scripts/export-app-icon.swift <reference.png> <AppIcon.png>")
}
let scale = 1024.0 / 1254.0
context.scaleBy(x: scale, y: scale)
// Convert the traced top-left coordinates to Quartz coordinates.
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 1254 - y) }
let outline = CGMutablePath()
outline.move(to: point(342, 62))
outline.addLine(to: point(912, 62))
outline.addCurve(to: point(1123, 126), control1: point(1013, 62), control2: point(1074, 77))
outline.addCurve(to: point(1190, 340), control1: point(1174, 177), control2: point(1190, 240))
outline.addLine(to: point(1190, 902))
outline.addCurve(to: point(1123, 1119), control1: point(1190, 1003), control2: point(1174, 1068))
outline.addCurve(to: point(912, 1182), control1: point(1074, 1168), control2: point(1013, 1182))
outline.addLine(to: point(342, 1182))
outline.addCurve(to: point(128, 1119), control1: point(241, 1182), control2: point(177, 1168))
outline.addCurve(to: point(64, 902), control1: point(79, 1070), control2: point(64, 1003))
outline.addLine(to: point(64, 340))
outline.addCurve(to: point(128, 126), control1: point(64, 240), control2: point(79, 177))
outline.addCurve(to: point(342, 62), control1: point(177, 77), control2: point(241, 62))
outline.closeSubpath()
context.addPath(outline)
context.clip()
context.interpolationQuality = .high
context.draw(input, in: CGRect(x: 0, y: 0, width: 1254, height: 1254))
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
