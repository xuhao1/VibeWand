import XCTest
import AppKit
@testable import VibeWandBridge

final class ClipboardTextDeliveryTests: XCTestCase {
    func testRestoresAllOriginalClipboardTypes() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("org.vibewand.test-data")
        let item = NSPasteboardItem()
        item.setString("原来的剪贴板", forType: .string)
        item.setData(Data([0, 1, 2, 255]), forType: type)
        board.writeObjects([item])
        let delivery = ClipboardTextDelivery(board: board)
        delivery.prepare("测试听写")
        XCTAssertEqual(board.string(forType: .string), "测试听写")
        delivery.restore()
        XCTAssertEqual(board.string(forType: .string), "原来的剪贴板")
        XCTAssertEqual(board.data(forType: type), Data([0, 1, 2, 255]))
    }
    func testDoesNotOverwriteAnythingTheUserCopiedDuringDelivery() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("原来的内容", forType: .string)
        let delivery = ClipboardTextDelivery(board: board)
        delivery.prepare("听写内容")
        board.clearContents(); board.setString("用户新复制的内容", forType: .string)
        delivery.restore()
        XCTAssertEqual(board.string(forType: .string), "用户新复制的内容")
    }
}
