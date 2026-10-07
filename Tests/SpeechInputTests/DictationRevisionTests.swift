import XCTest
@testable import SpeechInput

/// What the vocabulary is learned from: a dictated passage as it was written and as the user left it.
final class DictationRevisionTests: XCTestCase {
    func testAWordTheUserPutRightIsReadOutOfTheFieldWithWhatItWasBefore() throws {
        let written = "我们用歪不万的来控制 Codex"
        let revision = try XCTUnwrap(DictationRevision.read(written: written, before: "你好。" + written + "\n谢谢",
                                                            after: "你好。我们用 VibeWand 来控制 Codex\n谢谢", app: "备忘录"))
        // Only the passage is kept, never what else the field held.
        XCTAssertEqual(revision.said, written)
        XCTAssertEqual(revision.kept, "我们用 VibeWand 来控制 Codex")
        XCTAssertEqual(revision.changes, [.init(from: "歪不万的", to: "VibeWand")])
        XCTAssertEqual(revision.app, "备忘录")
    }

    func testWordsSideBySideThatWereBothChangedAreOneCorrection() throws {
        let revision = try XCTUnwrap(DictationRevision.read(written: "open the cloud code settings and ask quen",
                                                            before: "open the cloud code settings and ask quen",
                                                            after: "open the Claude Code settings and ask Qwen", app: "Notes"))
        XCTAssertEqual(revision.changes, [.init(from: "cloud code", to: "Claude Code"), .init(from: "quen", to: "Qwen")])
    }

    func testNothingIsKeptOfAPassageThatWasLeftAddedToRewrittenOrLost() {
        let written = "明天下午三点开会"
        func read(_ before: String, _ after: String) -> DictationRevision? { DictationRevision.read(written: written, before: before, after: after, app: "") }
        XCTAssertNil(read(written, written))
        // Typing on after it, or in front of it, corrects nothing.
        XCTAssertNil(read(written, written + "，记得带电脑"))
        XCTAssertNil(read(written, "提醒：" + written))
        // Said again in other words.
        XCTAssertNil(read(written, "会议改到后天上午"))
        // The field was sent and something else typed into it.
        XCTAssertNil(read("上文。" + written, "好的"))
        // What stood around the passage was changed too, so the passage cannot be told apart.
        XCTAssertNil(read("上文。" + written, "新上文。明天下午四点开会"))
        // The passage is not in the field at all.
        XCTAssertNil(read("别的内容", "别的内容改了"))
        // Punctuation alone teaches no word.
        XCTAssertNil(read(written, "明天下午三点开会。"))
        XCTAssertNotNil(read(written, "明天下午四点开会"))
    }

    func testTheNotebookKeepsWhatWaitsAndLetsGoOfWhatWasLearnedFrom() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vw-notebook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let notebook = VocabularyNotebook(directory: directory)
        XCTAssertEqual(notebook.pending(), [])
        let first = try XCTUnwrap(DictationRevision.read(written: "用歪不万的", before: "用歪不万的", after: "用 VibeWand", app: "A",
                                                         now: Date(timeIntervalSince1970: 1_791_000_000)))
        let second = try XCTUnwrap(DictationRevision.read(written: "问一下 quen", before: "问一下 quen", after: "问一下 Qwen", app: "B",
                                                          now: Date(timeIntervalSince1970: 1_791_000_060)))
        notebook.add(first); notebook.add(second)
        XCTAssertEqual(VocabularyNotebook(directory: directory).pending(), [first, second])
        notebook.settle([first.id])
        XCTAssertEqual(notebook.pending(), [second])
        // The oldest give way once the notebook is full.
        for _ in 0..<VocabularyNotebook.limit { notebook.add(first) }
        XCTAssertEqual(notebook.pending().count, VocabularyNotebook.limit)
        XCTAssertFalse(notebook.pending().contains(second))
        notebook.clear()
        XCTAssertEqual(notebook.pending(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: notebook.file.path))
    }

    func testLearnedTermsJoinTheVocabularyAfterTheUsersOwnAndNeverRepeatWhatIsKnown() throws {
        var vocabulary = SpeechVocabulary()
        vocabulary.terms = ["妙动科技"]
        vocabulary.learn(adding: ["VibeWand", "  Hermes  ", "妙动科技", "hermes", "", "一整句话写了四十多个字符的内容不是一个词而是一段话所以不会被当成词汇记下来的对吧朋友们", "两行\n的词"])
        // VibeWand is in the built-in list, and the user's own term is theirs already.
        XCTAssertEqual(vocabulary.learned, ["Hermes"])
        XCTAssertEqual(Array(vocabulary.allTerms.prefix(2)), ["妙动科技", "Hermes"])
        XCTAssertTrue(vocabulary.guidance.contains("Hermes"))
        XCTAssertTrue(vocabulary.context?.contains("Hermes") == true)
        vocabulary.learn(adding: ["Kimi K2", "SOARLAB"], removing: ["HERMES"])
        XCTAssertEqual(vocabulary.learned, ["Kimi K2", "SOARLAB"])
        vocabulary.learn(adding: (0..<(SpeechVocabulary.learnedLimit + 5)).map { "term-\($0)" })
        XCTAssertEqual(vocabulary.learned?.count, SpeechVocabulary.learnedLimit)
        XCTAssertEqual(vocabulary.learned?.last, "term-\(SpeechVocabulary.learnedLimit + 4)")
        vocabulary.learn(adding: [], removing: vocabulary.learned ?? [])
        XCTAssertNil(vocabulary.learned)
        // A vocabulary saved before there was anything to learn is read as it was.
        let old = try JSONDecoder().decode(SpeechVocabulary.self, from: Data(#"{"domain":"机器人","terms":["妙动科技"],"computing":false}"#.utf8))
        XCTAssertNil(old.learned)
        XCTAssertEqual(old.allTerms, ["妙动科技"])
    }
}
