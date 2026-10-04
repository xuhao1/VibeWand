import AppKit
import XCTest
@testable import VibeKeyBridge

final class OverlayLayoutTests: XCTestCase {
    func testEveryTemplateKeepsItsPhotoAndPhysicalControlsInsideThePanel() throws {
        for template in DeviceTemplateID.allCases {
            for expanded in [false, true] {
                let size = OverlayLayout.size(for: template, expanded: expanded)
                let panel = NSRect(origin: .zero, size: size)
                let photo = OverlayLayout.deviceRect(for: template, expanded: expanded)
                let context = "\(template.rawValue), expanded: \(expanded)"
                XCTAssertTrue(panel.contains(photo), context)
                XCTAssertGreaterThanOrEqual(photo.minY, 36, "Photo must clear the header: \(context)")
                XCTAssertLessThanOrEqual(photo.maxY, size.height - 44, "Photo must clear the footer: \(context)")
                for descriptor in template.template.controls {
                    let center = try XCTUnwrap(OverlayLayout.controlCenter(descriptor.control, template: template, expanded: expanded), "Missing \(descriptor.title): \(context)")
                    XCTAssertTrue(photo.contains(center), "\(descriptor.title) falls outside the artwork: \(context)")
                }
            }
        }
    }

    func testControllerUsesLandscapeGeometryAndPortraitDevicesStayCompact() {
        let controller = OverlayLayout.size(for: .dualSense, expanded: false)
        XCTAssertGreaterThan(controller.width, controller.height)
        for template in [DeviceTemplateID.vibeKey, .xiaomiRemote] {
            let size = OverlayLayout.size(for: template, expanded: false)
            XCTAssertLessThan(size.width, size.height)
            XCTAssertLessThan(size.width, controller.width)
        }
        for template in DeviceTemplateID.allCases {
            XCTAssertGreaterThan(OverlayLayout.size(for: template, expanded: true).width,
                                 OverlayLayout.size(for: template, expanded: false).width)
        }
    }

    func testControllerAndRemoteCoordinatesPreserveTheFullPhotoAspectRatio() throws {
        for template in [DeviceTemplateID.dualSense, .xiaomiRemote] {
            let artwork = DeviceArtwork.forTemplate(template)
            for expanded in [false, true] {
                let photo = OverlayLayout.deviceRect(for: template, expanded: expanded)
                XCTAssertEqual(photo.width / photo.height, artwork.aspectRatio, accuracy: 0.00001)
                for (control, normalized) in artwork.hotspots {
                    let center = try XCTUnwrap(OverlayLayout.controlCenter(control, template: template, expanded: expanded))
                    XCTAssertEqual((center.x - photo.minX) / photo.width, normalized.x, accuracy: 0.00001)
                    XCTAssertEqual((center.y - photo.minY) / photo.height, normalized.y, accuracy: 0.00001)
                }
            }
        }
    }

    func testAllStickDirectionsHaveDistinctPointsAroundTheirStick() throws {
        for expanded in [false, true] {
            for controls in [[DeviceControl.leftStickPress, .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight],
                             [.rightStickPress, .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight]] {
                let points = try controls.map { try XCTUnwrap(OverlayLayout.controlCenter($0, template: .dualSense, expanded: expanded)) }
                XCTAssertLessThan(points[1].y, points[0].y)
                XCTAssertGreaterThan(points[2].y, points[0].y)
                XCTAssertLessThan(points[3].x, points[0].x)
                XCTAssertGreaterThan(points[4].x, points[0].x)
            }
        }
    }

    func testSwitchingAnInvisibleOverlayResizesItsPreviewWithoutShowingAWindow() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            // OverlayController persists placement; preserve the user's value around this hidden-window test.
            let positionKey = "VibeKeyBridge.overlayOrigin"
            let originalPosition = UserDefaults.standard.object(forKey: positionKey)
            defer {
                if let originalPosition { UserDefaults.standard.set(originalPosition, forKey: positionKey) }
                else { UserDefaults.standard.removeObject(forKey: positionKey) }
            }
            let overlay = OverlayController { _, _ in XCTFail("Rendering must not simulate device input") }
            XCTAssertFalse(overlay.isVisible)
            var snapshot = HUDSnapshot()
            for expanded in [false, true] {
                overlay.setExpanded(expanded)
                for template in DeviceTemplateID.allCases {
                    snapshot.deviceTemplate = template
                    snapshot.scope = template == .dualSense ? .sessions : .reading
                    snapshot.mode = snapshot.scope.label
                    snapshot.action = L10n.tr("等待操作", "Ready")
                    snapshot.connected = true
                    snapshot.controlHints = HUDGuidance.hints(template: template.template,
                        configuration: template.template.defaultConfiguration, scope: snapshot.scope, profile: .codex)
                    overlay.update(snapshot)
                    XCTAssertFalse(overlay.isVisible, "Changing \(template.rawValue) must retain the hidden state")
                    let preview = try XCTUnwrap(overlay.previewImage())
                    let deviceSize = OverlayLayout.size(for: template, expanded: expanded)
                    XCTAssertEqual(preview.size, NSSize(width: deviceSize.width, height: deviceSize.height + 55))
                    XCTAssertFalse(overlay.isVisible, "Rendering a preview must not order the window front")
                    if let path = ProcessInfo.processInfo.environment["VIBEWAND_OVERLAY_REVIEW"] {
                        let directory = URL(fileURLWithPath: path)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                            let image = try XCTUnwrap(overlay.previewImage(appearance: NSAppearance(named: appearance)))
                            let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
                            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            try png.write(to: directory.appendingPathComponent("\(template.rawValue)-\(expanded ? "expanded" : "compact")-\(name).png"))
                        }
                    }
                }
            }
        }
    }
}
