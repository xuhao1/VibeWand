import AppKit
import XCTest
import AU05Device
@testable import VibeWandBridge

/// The keyboard as a device: which key combinations stand for which controls, and what a key press becomes.
/// No event tap is installed and no key is posted.
final class KeyboardLayoutTests: XCTestCase {
    private let hyper: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
    private func code(_ key: ApplicationKey) -> CGKeyCode { key.keyCode }

    func testTheStandardLayoutGivesEachControlItsOwnCombinationThatNeedsThreeModifiers() {
        let layout = KeyboardLayout.standard
        XCTAssertEqual(Set(layout.chords.keys), Set(KeyboardLayout.controls.map(\.rawValue)))
        XCTAssertEqual(KeyboardLayout.controls.map(layout.label), ["⌃⌥⌘Space", "⌃⌥⌘↑", "⌃⌥⌘←", "⌃⌥⌘→", "⌃⌥⌘Return", "⌃⌥⌘Backspace"])
        XCTAssertTrue(layout.clashes.isEmpty)
        XCTAssertEqual(layout.control(code: code(.left), flags: hyper), .left)
        XCTAssertEqual(layout.control(code: code(.space), flags: hyper), .voice)
        // The same key with other modifiers, or none, is the app's own.
        XCTAssertNil(layout.control(code: code(.left), flags: []))
        XCTAssertNil(layout.control(code: code(.left), flags: [.maskAlternate]))
        XCTAssertNil(layout.control(code: code(.left), flags: hyper.union(.maskShift)))
        // Flags that are not modifiers the user holds, such as the keypad bit arrows carry, do not matter.
        XCTAssertEqual(layout.control(code: code(.left), flags: hyper.union([.maskNumericPad, .maskSecondaryFn])), .left)
    }

    func testATypingKeyWithoutAModifierNeverFiresAndASharedCombinationFiresOnlyForTheFirstControl() {
        var layout = KeyboardLayout.standard
        layout.chords[DeviceControl.ok.rawValue] = KeyChord(code: code(.returnKey))
        for key in [ApplicationKey.returnKey, .a, .seven, .space, .escape, .backspace, .left, .tab] {
            XCTAssertFalse(KeyboardLayout.usable(KeyChord(code: code(key))), key.rawValue)
        }
        XCTAssertFalse(KeyboardLayout.usable(KeyChord(code: code(.five), shift: true)), "shift alone still types")
        XCTAssertNil(layout.control(code: code(.returnKey), flags: []), "plain Return must stay the app's")
        // A function key types nothing, so it may stand alone.
        layout.chords[DeviceControl.ok.rawValue] = KeyChord(code: code(.f8))
        XCTAssertTrue(KeyboardLayout.usable(KeyChord(code: code(.f8))))
        XCTAssertEqual(layout.control(code: code(.f8), flags: []), .ok)

        layout.chords[DeviceControl.escape.rawValue] = layout.chord(.dial)
        XCTAssertEqual(layout.clashes, [.escape])
        XCTAssertEqual(layout.control(code: code(.up), flags: hyper), .dial)
        layout.chords[DeviceControl.escape.rawValue] = nil
        XCTAssertEqual(layout.label(.escape), "")
        XCTAssertTrue(layout.clashes.isEmpty)
    }

    func testTheLayoutIsKeptInPreferencesAndTheTemplateNamesItsControlsByTheirCombinations() throws {
        let name = "VibeWand.KeyboardLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(KeyboardLayout.load(defaults), .standard)
        var layout = KeyboardLayout.standard
        layout.chords[DeviceControl.dial.rawValue] = KeyChord(code: code(.k), option: true, control: true)
        layout.chords[DeviceControl.ok.rawValue] = KeyChord(code: 106)
        layout.save(defaults)
        XCTAssertEqual(KeyboardLayout.load(defaults).label(.dial), "⌃⌥K")
        XCTAssertEqual(KeyboardLayout.load(defaults), layout)

        let template = DeviceTemplateID.keyboard.template
        XCTAssertEqual(template.controls.map(\.control), KeyboardLayout.controls)
        XCTAssertTrue(template.controls[0].title.hasPrefix(KeyboardLayout.current.label(.voice)))
        // It behaves like the handset: the same presets, and the keyboard's own command key instead of a button.
        XCTAssertEqual(template.defaultConfiguration.action(.reading, .voice, .hold), .dictation)
        XCTAssertEqual(template.defaultConfiguration.action(.reading, .dial, .single), DeviceTemplateID.vibeKey.template.defaultConfiguration.action(.reading, .dial, .single))
        XCTAssertTrue(template.commandBindings.isEmpty)
        XCTAssertFalse(template.requiresHIDProfile)
    }

    @MainActor
    func testAButtonIsPressedAndReleasedOnceHoweverLongItsKeyRepeatsAndATurnKeepsTurning() {
        let source = KeyboardInputSource()
        source.layout = { .standard }
        var events: [String] = []
        source.onEvent = { events.append("\($0.control.rawValue).\($0.phase.rawValue)") }

        // Holding the dictation combination: one press, repeats swallowed, one release even after the modifiers went first.
        XCTAssertTrue(source.handle(code: code(.space), flags: hyper, down: true, repeated: false))
        XCTAssertTrue(source.handle(code: code(.space), flags: hyper, down: true, repeated: true))
        XCTAssertTrue(source.handle(code: code(.space), flags: [], down: false, repeated: false))
        XCTAssertEqual(events, ["voice.down", "voice.up"])

        // A direction is a turn: one step for the press and one for each repeat, and nothing on release.
        events = []
        XCTAssertTrue(source.handle(code: code(.right), flags: hyper, down: true, repeated: false))
        XCTAssertTrue(source.handle(code: code(.right), flags: hyper, down: true, repeated: true))
        XCTAssertTrue(source.handle(code: code(.right), flags: hyper, down: true, repeated: true))
        XCTAssertTrue(source.handle(code: code(.right), flags: hyper, down: false, repeated: false))
        XCTAssertEqual(events, ["right.pulse", "right.pulse", "right.pulse"])

        // Every other key passes through untouched, on the way down and on the way up.
        events = []
        XCTAssertFalse(source.handle(code: code(.space), flags: [], down: true, repeated: false))
        XCTAssertFalse(source.handle(code: code(.space), flags: [], down: false, repeated: false))
        XCTAssertFalse(source.handle(code: code(.a), flags: hyper, down: true, repeated: false))
        XCTAssertFalse(source.handle(code: code(.left), flags: [.maskCommand], down: true, repeated: false))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(source.connection, .stopped, "nothing listens until the source is started")
    }

    /// A custom keyboard's extra keys have no place in a list of key names: they are known by the code they send.
    func testAnyKeyAKeyboardSendsCanStandForAControlAndTheExtraOnesMayStandAlone() {
        XCTAssertEqual(KeyChord(code: 106).label, "F16")
        XCTAssertEqual(KeyChord(code: 87, control: true).label, "⌃Num 5")
        XCTAssertEqual(KeyChord(code: 76, flags: [.maskCommand, .maskShift, .maskNumericPad]).label, "⇧⌘Num Enter")
        XCTAssertEqual(KeyChord(code: 200).label, L10n.tr("键 200", "Key 200"))
        XCTAssertEqual(KeyChord(code: code(.space), flags: hyper), KeyboardLayout.standard.chord(.voice))
        // F13 and up, the number pad, the paging keys and keys with no name at all type nothing in a text field's main block.
        for bare in [105, 90, 82, 76, 114, 200, code(.pageDown), code(.home)] as [CGKeyCode] {
            XCTAssertTrue(KeyboardLayout.usable(KeyChord(code: bare)), "\(bare)")
        }
        var layout = KeyboardLayout.standard
        layout.chords[DeviceControl.right.rawValue] = KeyChord(code: 200)
        layout.chords[DeviceControl.left.rawValue] = KeyChord(code: 200, shift: true)
        XCTAssertEqual(layout.control(code: 200, flags: []), .right)
        XCTAssertEqual(layout.control(code: 200, flags: [.maskShift]), .left)
        XCTAssertNil(layout.control(code: 200, flags: [.maskCommand]))
        XCTAssertTrue(layout.clashes.isEmpty)
    }

    @MainActor
    func testRecordingTakesTheNextKeyWhateverItIsAndThatPressStandsForNothing() {
        let source = KeyboardInputSource()
        var layout = KeyboardLayout.standard
        source.layout = { layout }
        var events: [String] = [], recorded: [KeyChord] = []
        source.onEvent = { events.append("\($0.control.rawValue).\($0.phase.rawValue)") }
        defer { KeyboardInputSource.capture = nil }
        // As the settings do it: one key is taken, and it becomes the control's combination at once.
        func record(_ control: DeviceControl) {
            KeyboardInputSource.capture = { pressed in
                KeyboardInputSource.capture = nil
                recorded.append(pressed)
                layout.chords[control.rawValue] = pressed
            }
        }

        // A key the layout already uses is recorded like any other instead of firing its control.
        record(.ok)
        XCTAssertTrue(source.handle(code: code(.space), flags: hyper, down: true, repeated: false))
        XCTAssertEqual(recorded, [KeyboardLayout.standard.chord(.voice)!])
        // Still held, it repeats: the press that was recorded does not start what it now stands for.
        XCTAssertTrue(source.handle(code: code(.space), flags: hyper, down: true, repeated: true))
        XCTAssertTrue(source.handle(code: code(.space), flags: [], down: false, repeated: false))
        XCTAssertTrue(events.isEmpty)

        // An extra key with no name and no modifier: recorded by pressing it, then it works alone.
        record(.right)
        XCTAssertTrue(source.handle(code: 200, flags: [], down: true, repeated: false))
        XCTAssertTrue(source.handle(code: 200, flags: [], down: false, repeated: false))
        XCTAssertEqual(recorded.last, KeyChord(code: 200))
        XCTAssertNil(KeyboardInputSource.capture)
        XCTAssertTrue(source.handle(code: 200, flags: [], down: true, repeated: false))
        XCTAssertTrue(source.handle(code: 200, flags: [], down: false, repeated: false))
        XCTAssertEqual(events, ["right.pulse"])
        // With nothing being recorded, other keys are the app's again.
        XCTAssertFalse(source.handle(code: 201, flags: [], down: true, repeated: false))
    }

    func testTheOverlayGivesEveryKeyboardControlAKeyCapBesideItsCaption() throws {
        for expanded in [false, true] {
            let column = OverlayLayout.deviceRect(for: .keyboard, expanded: expanded)
            var caps: [NSRect] = []
            for control in KeyboardLayout.controls {
                let cap = try XCTUnwrap(OverlayLayout.keyCap(control, expanded: expanded))
                XCTAssertTrue(column.contains(cap), "\(control)")
                XCTAssertFalse(caps.contains { $0.intersects(cap) }, "\(control) overlaps another cap")
                caps.append(cap)
            }
            // The two directions share a row; every other control has one of its own.
            XCTAssertEqual(Set(caps.map(\.minY)).count, OverlayLayout.keyboardRows.count)
            XCTAssertEqual(try XCTUnwrap(OverlayLayout.keyCap(.left, expanded: expanded)).minY, try XCTUnwrap(OverlayLayout.keyCap(.right, expanded: expanded)).minY)
        }
        XCTAssertEqual(HUDGuidance.shortName(.ok, template: .keyboard), KeyboardLayout.current.label(.ok))
    }
}
