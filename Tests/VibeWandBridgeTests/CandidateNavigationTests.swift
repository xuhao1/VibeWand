import XCTest
@testable import VibeWandBridge

final class CandidateNavigationTests: XCTestCase {
    func testCandidateNavigationUsesSelectionAndClampsAtBoundaries() {
        var navigation = CandidateNavigation()
        XCTAssertEqual(navigation.move(root: 1, count: 4, selected: 1, direction: 1), 2)
        XCTAssertEqual(navigation.move(root: 1, count: 4, selected: 1, direction: -1), 1)
        XCTAssertEqual(navigation.move(root: 1, count: 4, selected: nil, direction: -1), 0)
        XCTAssertEqual(navigation.move(root: 1, count: 4, selected: nil, direction: -1), 0)
    }
    func testNewMenuDoesNotReusePreviousSelection() {
        var navigation = CandidateNavigation()
        XCTAssertEqual(navigation.move(root: 1, count: 4, selected: 2, direction: 1), 3)
        XCTAssertEqual(navigation.move(root: 2, count: 3, selected: nil, direction: 1), 0)
        navigation.reset()
        XCTAssertEqual(navigation.move(root: 2, count: 3, selected: nil, direction: -1), 2)
        XCTAssertNil(navigation.move(root: 3, count: 0, selected: nil, direction: 1))
    }
}
