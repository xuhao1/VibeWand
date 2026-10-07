import XCTest
@testable import VibeWandBridge

final class ScrollTargetTests: XCTestCase {
    func testBrowserViewportOverridesFocusedTopBarOrTextFieldAndClipsLongDocument() {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 800)
        let address = CGRect(x: 200, y: 115, width: 650, height: 30)
        let document = CGRect(x: 100, y: 180, width: 1000, height: 20000)
        let point = ScrollTarget.point(window: window, composer: address, scrollArea: nil, popup: nil, viewport: document)!
        XCTAssertTrue(window.contains(point))
        XCTAssertGreaterThan(point.y, 180)
        XCTAssertEqual(point.x, document.midX)
    }
    func testEmptyComposerScrollsOverConversationColumnInsteadOfInputBox() {
        let window = CGRect(x: 100, y: 100, width: 1400, height: 900)
        let composer = CGRect(x: 400, y: 820, width: 650, height: 140)
        let point = ScrollTarget.point(window: window, composer: composer, scrollArea: nil, popup: nil)!
        XCTAssertEqual(point.x, composer.midX)
        XCTAssertTrue(window.contains(point))
        XCTAssertLessThan(point.y, composer.minY)
    }
    func testPickerFrameTakesPriorityOverUnderlyingChat() {
        let menu = CGRect(x: 700, y: 400, width: 280, height: 300)
        let point = ScrollTarget.point(window: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            composer: CGRect(x: 400, y: 850, width: 700, height: 100), scrollArea: nil, popup: menu)!
        XCTAssertEqual(point, CGPoint(x: menu.midX, y: menu.midY))
    }
    func testFocusedScrollAreaAndWindowFallbackDoNotRequireText() {
        let area = CGRect(x: 400, y: 150, width: 700, height: 600)
        XCTAssertEqual(ScrollTarget.point(window: nil, composer: nil, scrollArea: area, popup: nil), CGPoint(x: 750, y: 450))
        XCTAssertNil(ScrollTarget.point(window: nil, composer: nil, scrollArea: nil, popup: nil))
        XCTAssertNil(ScrollTarget.point(window: CGRect.zero, composer: nil, scrollArea: nil, popup: nil))
    }
}

extension ScrollTargetTests {
    func testSliderFocusClicksCurrentThumbInsteadOfChangingValueByClickingTrackCenter() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 20)
        XCTAssertEqual(SliderTarget.point(frame: frame, value: 1, minimum: 0, maximum: 3, vertical: false), CGPoint(x: 200, y: 210))
        XCTAssertEqual(SliderTarget.point(frame: frame, value: 100, minimum: 0, maximum: 3, vertical: false), CGPoint(x: 400, y: 210))
        XCTAssertEqual(SliderTarget.point(frame: frame, value: nil, minimum: nil, maximum: nil, vertical: false), CGPoint(x: 250, y: 210))
    }
}
