import XCTest
import InputLink
@testable import VibeWandBridge

/// VibeWand's end of the link, against the input method's own composer over a real socket.
final class InputMethodTests: XCTestCase {
    private final class Field: InputTextClient {
        let application = "com.example.chat"
        var written = "", marked = ""
        func mark(_ text: String) { marked = text }
        func insert(_ text: String) { written += text; marked = "" }
        var marking: Bool { !marked.isEmpty }
    }
    private func pause(_ seconds: Double = 0.15) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    @MainActor
    func testTheCopyThisBuildCarriesIsPlacedWithoutItsQuarantineAndOnlyWhenItDiffers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vw-input-place-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let embedded = root.appendingPathComponent("VibeWand.app/Contents/Helpers/VibeWandInput.app")
        let installed = root.appendingPathComponent("Library/Input Methods/VibeWandInput.app")
        let binary = "Contents/MacOS/VibeWandInput"
        try FileManager.default.createDirectory(at: embedded.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try Data("this build".utf8).write(to: embedded.appendingPathComponent(binary))
        try Data("<plist/>".utf8).write(to: embedded.appendingPathComponent("Contents/Info.plist"))
        for url in [embedded, embedded.appendingPathComponent(binary)] {
            XCTAssertEqual(setxattr(url.path, "com.apple.quarantine", "0081;0;Safari;", 15, 0, 0), 0)
        }
        let input = InputMethod(embedded: embedded, installed: installed, socket: root.appendingPathComponent("none.sock").path)
        XCTAssertTrue(input.available)
        XCTAssertTrue(input.stale)
        try input.place()
        XCTAssertFalse(input.stale)
        for url in [installed, installed.appendingPathComponent(binary)] {
            XCTAssertEqual(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0), -1, "the copy must be free to start")
        }
        // An update of VibeWand brings another input method than the one in place.
        try Data("the next build".utf8).write(to: embedded.appendingPathComponent(binary))
        XCTAssertTrue(input.stale)
        try input.place()
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent(binary), encoding: .utf8), "the next build")
    }

    @MainActor
    func testADictationIsShownThenReplacedAndALostInputMethodAnswersTheCommit() async throws {
        let path = NSTemporaryDirectory() + "vw-input-\(UInt32.random(in: 0...UInt32.max)).sock"
        let nowhere = URL(fileURLWithPath: NSTemporaryDirectory() + "vw-no-input-method.app")
        let composer = InputComposer(), field = Field()
        let listener = try InputListener(path: path, admits: { _ in true }, onLine: composer.connect)
        defer { _ = listener }
        let input = InputMethod(embedded: nowhere, installed: nowhere, socket: path)
        XCTAssertFalse(input.available)
        XCTAssertFalse(input.begin("com.example.chat"), "The first dictation after connecting has no text field yet")
        composer.activate(field)
        await pause()
        XCTAssertTrue(input.connected)
        XCTAssertEqual(input.client, "com.example.chat")
        XCTAssertFalse(input.begin("com.example.terminal"))

        XCTAssertTrue(input.begin("com.example.chat"))
        input.show("边说"); input.show("边说边写")
        await pause()
        XCTAssertEqual(field.marked, "边说边写")
        var written: Bool?
        input.commit("边说边写。") { written = $0 }
        await pause()
        XCTAssertEqual(written, true)
        XCTAssertEqual(field.written, "边说边写。")

        // Text with lines in it is pasted instead: what was shown is taken back first.
        XCTAssertTrue(input.begin("com.example.chat"))
        input.show("两段话")
        await pause()
        var cleared = false
        input.cancel { cleared = field.marked.isEmpty }
        await pause()
        XCTAssertTrue(cleared)
        XCTAssertEqual(field.written, "边说边写。")

        var interrupted = false
        input.onEnded = { kept in interrupted = kept }
        XCTAssertTrue(input.begin("com.example.chat"))
        input.show("第二句")
        await pause()
        composer.interrupt(field)
        await pause()
        XCTAssertTrue(interrupted)
        XCTAssertEqual(field.written, "边说边写。第二句")

        // The input method drops this connection while a commit is waiting for its answer.
        XCTAssertTrue(input.begin("com.example.chat"))
        var pair: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
        defer { close(pair[1]) }
        composer.connect(InputLine(descriptor: pair[0]))
        written = nil
        input.commit("第三句") { written = $0 }
        await pause()
        XCTAssertEqual(written, false)
        XCTAssertFalse(input.connected)
        XCTAssertNil(input.client)
    }
}
