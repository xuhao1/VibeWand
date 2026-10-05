import XCTest
@testable import WandAgent

final class JSONValueTests: XCTestCase {
    func testTextIsOneLineWithStableKeyOrder() {
        let value: JSONValue = ["b": [1, 2.5, nil], "a": ["x": true, "path": "a/b"]]
        XCTAssertEqual(value.text, #"{"a":{"path":"a/b","x":true},"b":[1,2.5,null]}"#)
    }
    func testDecodingKeepsBooleansNumbersAndStringsApart() {
        let value = JSONValue(data: Data(#"{"id":7,"ok":false,"name":"1","none":null}"#.utf8))
        XCTAssertEqual(value?["id"]?.int, 7)
        XCTAssertEqual(value?["ok"], .bool(false))
        XCTAssertEqual(value?["name"]?.string, "1")
        XCTAssertEqual(value?["none"], .null)
        XCTAssertNil(value?["missing"])
        XCTAssertNil(JSONValue(data: Data("not json".utf8)))
    }
}
