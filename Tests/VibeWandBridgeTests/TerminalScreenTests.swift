import XCTest
@testable import VibeWandBridge

/// Screens transcribed from Codex CLI 0.160.0, Claude Code 2.1.289 and
/// OpenCode 1.18.34 as iTerm2 3.7.3 exposes them. ▮ marks the cursor.
final class TerminalScreenTests: XCTestCase {
    private func screen(_ text: String) -> TerminalScreen {
        var rows = text.components(separatedBy: "\n")
        let row = rows.firstIndex { $0.contains("▮") }!
        let column = rows[row].range(of: "▮")!.lowerBound.utf16Offset(in: rows[row])
        rows[row] = rows[row].replacingOccurrences(of: "▮", with: "")
        return TerminalScreen(rows: rows, row: row, column: column)
    }
    private func prompt(_ text: String) -> TerminalPrompt { screen(text).prompt() }

    func testCodexPromptIsEmptyUntilTextStandsBeforeTheCursor() {
        XCTAssertEqual(prompt("""
              /review - review any changes and find issues

            › ▮Ask Codex to do anything

              GPT-6.1-Sol xhigh · /private/tmp/vibewand-live
              ? for shortcuts                                   ⚠ 1 warning · f2 to view
            """), .empty)
        // The spinner line names Esc, but the prompt is still there to type into.
        XCTAssertEqual(prompt("""
            • Working (3s • esc to interrupt)

            › ▮Ask Codex to do anything

              GPT-6.1-Sol low · /private/tmp/vibewand-live
            """), .empty)
        XCTAssertEqual(prompt("""
            • Working (4s • esc to interrupt)

            › abcdefghij▮

              GPT-6.1-Sol xhigh · /private/tmp/vibewand-live
              tab to queue message
            """), .draft)
        XCTAssertEqual(prompt("› hello wo▮rld\n\n  GPT-6.1-Sol xhigh"), .draft)
    }

    func testCodexDraftsThatWrapOrRunOverSeveralRows() {
        XCTAssertEqual(prompt("› hello world\n  second▮\n\n  GPT-6.1-Sol xhigh"), .draft)
        XCTAssertEqual(prompt("› hello world\n  second\n  ▮\n\n  GPT-6.1-Sol xhigh"), .draft)
        // Nothing before the cursor, yet the draft goes on below it.
        XCTAssertEqual(prompt("› ▮\n  second\n\n  GPT-6.1-Sol xhigh"), .draft)
    }

    func testCodexListsAreNotMistakenForAPrompt() {
        let list = """
              Select Model and Effort

            › 1. GPT-6.1-Sol (current)  Latest workhorse model for coding and everyday work.
              2. GPT-6-Astra            Frontier intelligence for the most demanding work.
              3. GPT-6-Sol              Previous generation workhorse model.

              enter select · esc back
            """
        // Codex hides the cursor in a list and leaves it wherever it last drew.
        XCTAssertEqual(prompt(list + "▮"), .list)
        XCTAssertEqual(prompt(list.replacingOccurrences(of: "everyday work.", with: "everyday work.▮")), .list)
        XCTAssertEqual(prompt(list.replacingOccurrences(of: "demanding work.", with: "demanding work.▮")), .list)
        XCTAssertEqual(prompt("""
             Resume a previous session

             Type to search

              › 5m ago      Reply ok
                5m ago      Run VibeWand terminal test

            ────────────────────────────────────────▮
             enter resume   ctrl+a archive   esc exit   ctrl+c exit   tab focus   ←/→ option
             ctrl+o comfy   ctrl+t preview   ctrl+e exp   ↑/↓ browse
            """), .list)
    }

    func testClaudeCodePromptAndLists() {
        XCTAssertEqual(prompt("""
            ────────────────────────────────────────
            ❯ ▮Try "fix lint errors"
            ────────────────────────────────────────
              ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
            """), .empty)
        XCTAssertEqual(prompt("────────\n❯\u{A0}▮\n────────"), .empty)
        XCTAssertEqual(prompt("────────\n❯ hello world▮\n────────"), .draft)
        XCTAssertEqual(prompt("────────\n❯ hello world\n  second▮\n────────"), .draft)
        // Claude Code pads with NUL cells and parks the cursor before the selected row.
        XCTAssertEqual(prompt("""
            ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
            \0\0\0Select\0model

            \0\0\0\0\01.\0Default\0(recommended)\0\0Use\0the\0default\0model
            \0\0\0▮❯\02.\0Opus\0✔
            \0\0\0\0\03.\0Fable

            \0\0\0◐\0Medium\0effort\0(default)\0←/→\0to\0adjust

            \0\0\0Enter\0to\0set\0as\0default\0·\0s\0to\0use\0this\0session\0only\0·\0Esc\0to\0cancel
            """), .list)
        XCTAssertEqual(prompt("""
            ────────────────────────────────────────
            \0\0Try\0the\0new\0fullscreen\0renderer?

            \0\0▮❯\01.\0Yes,\0try\0it
            \0\0\0\02.\0Not\0now

            \0\0Enter\0to\0confirm\0·\0Esc\0to\0cancel
            """), .list)
    }

    func testOpenCodeBoxedPrompt() {
        XCTAssertEqual(prompt("""
                     ┃
                     ┃  ▮Ask anything… "Fix a TODO in the codebase"
                     ┃
                     ┃  Sisyphus - Ultraworker · GPT-5.6 Sol OpenAI
                     ╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
                                              tab agents  ctrl+p commands
            """), .empty)
        XCTAssertEqual(prompt("  ┃\n  ┃  hello wo▮rld\n  ┃\n  ┃  Build · GPT-5.6 Sol OpenAI\n  ╹▀▀▀▀"), .draft)
        // Every row of a draft has the bar, so an empty row is not an empty prompt.
        XCTAssertEqual(prompt("  ┃\n  ┃  hello world\n  ┃  ▮\n  ┃\n  ┃  Build · GPT-5.6 Sol OpenAI\n  ╹▀▀▀▀"), .draft)
        XCTAssertEqual(prompt("  ┃\n  ┃  ▮\n  ┃  second\n  ┃\n  ┃  Build · GPT-5.6 Sol OpenAI\n  ╹▀▀▀▀"), .draft)
        // A sidebar shares the box's rows on a wide terminal.
        XCTAssertEqual(prompt("  ┃                         ▎ Context\n  ┃  ▮                       ▎ 12% used\n  ┃\n  ┃  Build · GPT-5.6 Sol\n  ╹▀▀▀▀"), .empty)
        // A dialog drawn over a conversation: the bar left of it belongs to a message.
        XCTAssertEqual(prompt("""
                           Sessions                                  esc

              ┃            ▮Search
              ┃  $ echo vibewand-session-2
              ┃
                           Today
            """), .list)
        XCTAssertEqual(prompt("""
                           Select model                              esc

              ┃  a long message reaching the dia▮Search
              ┃  second row of that message
            """), .list)
    }

    func testTypedCommandMustStandAloneOnThePrompt() {
        XCTAssertTrue(screen("› /resume  resume a saved chat\n\n› /resume▮\n\n  GPT-6.1-Sol xhigh").promptHolds("/resume"))
        XCTAssertFalse(screen("› /resume▮\n\n  GPT-6.1-Sol xhigh").promptHolds("/model"))
        // The cursor stood at the start of a draft nobody could tell from a placeholder.
        XCTAssertEqual(prompt("› ▮hello world\n\n  GPT-6.1-Sol xhigh"), .empty)
        XCTAssertFalse(screen("› /resume▮hello world\n\n  GPT-6.1-Sol xhigh").promptHolds("/resume"))
        XCTAssertFalse(screen("› /resume▮\n  second row\n\n  GPT-6.1-Sol xhigh").promptHolds("/resume"))
        XCTAssertTrue(screen("────\n❯ /model▮\n────\n  /model       Set the AI model for Claude Code").promptHolds("/model"))
        // Claude Code's fullscreen renderer shows the argument hint behind the cursor.
        XCTAssertTrue(screen("────\n❯ /model▮ [model]\n────").promptHolds("/model"))
        XCTAssertTrue(screen("────\n❯ /resume▮ [conversation id or search term]\n────").promptHolds("/resume"))
        XCTAssertFalse(screen("────\n❯ /resume▮ and the rest of a draft\n────").promptHolds("/resume"))
        XCTAssertFalse(screen("────\n❯ /resume ▮[conversation id or search term]\n────").promptHolds("/resume"))
        // OpenCode stacks its matching commands on top of the box, behind the same bar.
        XCTAssertTrue(screen("""
              ┃ /sessions                        Switch session                         ┃
              ┃ /goal                            (builtin) Set, show, pause, resume, or ┃
              ┃
              ┃  /resume▮                                        ▎ Context
              ┃
              ┃  Sisyphus - Ultraworker · GPT-5.6 Terra Fast OpenAI
              ╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
            """).promptHolds("/resume"))
        XCTAssertFalse(screen("  ┃\n  ┃  first row\n  ┃  /resume▮\n  ┃\n  ┃  Build · GPT-5.6 Sol\n  ╹▀▀▀▀").promptHolds("/resume"))
        XCTAssertFalse(screen("› ▮Ask Codex to do anything\n\n  GPT-6.1-Sol xhigh").promptHolds(""))
    }

    func testDraftBehindTheCursorIsRememberedByItsFingerprint() {
        // Moving the cursor to the very start must not turn the draft into a placeholder,
        // and neither must deleting everything before a cursor in the middle of it.
        for (typing, atStart, deleted, cleared) in [
            ("› a▮b\n\n  GPT-6.1-Sol", "› ▮ab\n\n  GPT-6.1-Sol", "› ▮b\n\n  GPT-6.1-Sol", "› ▮Ask Codex to do anything\n\n  GPT-6.1-Sol"),
            ("────\n❯ a▮b\n────", "────\n❯ ▮ab\n────", "────\n❯ ▮b\n────", "────\n❯ ▮Try \"fix lint errors\"\n────"),
            ("  ┃\n  ┃  a▮b\n  ┃\n  ┃  Build\n  ╹▀▀", "  ┃\n  ┃  ▮ab\n  ┃\n  ┃  Build\n  ╹▀▀",
             "  ┃\n  ┃  ▮b\n  ┃\n  ┃  Build\n  ╹▀▀", "  ┃\n  ┃  ▮Ask anything…\n  ┃\n  ┃  Build\n  ╹▀▀")] {
            let draft = screen(typing).fingerprints
            XCTAssertEqual(draft.count, 2)
            XCTAssertEqual(screen(atStart).prompt(), .empty)
            XCTAssertEqual(screen(atStart).prompt(draft: draft), .draft)
            XCTAssertEqual(screen(deleted).prompt(draft: draft), .draft)
            XCTAssertEqual(screen(cleared).prompt(draft: draft), .empty)
        }
        // A prompt showing nothing at all never matches a remembered draft.
        XCTAssertTrue(screen("────\n❯ ▮\n────").fingerprints.isEmpty)
        XCTAssertEqual(screen("────\n❯ ▮\n────").prompt(draft: screen("────\n❯ ab▮\n────").fingerprints), .empty)
        XCTAssertTrue(screen("› one\n  two▮\n\n  GPT-6.1-Sol").fingerprints.isEmpty)
    }

    func testShellsAndUnreadableScreensAreNotPrompts() {
        XCTAssertEqual(prompt("Last login: Mon Oct  5 16:00:00 on ttys008\nxuhao@mac ~ % ls -la▮"), .unknown)
        XCTAssertEqual(prompt("xuhao@mac ~ % ▮"), .unknown)
        XCTAssertEqual(TerminalScreen(rows: [], row: 0, column: 0).prompt(), .unknown)
        XCTAssertEqual(TerminalScreen(rows: ["› "], row: 3, column: 0).prompt(), .unknown)
        XCTAssertEqual(TerminalScreen(rows: ["› "], row: 0, column: 40).prompt(), .empty)
    }
}
