import AppKit
import Carbon
import InputMethodKit
import InputLink

/// VibeWand's input method. It is a palette, the kind macOS dictation is: it works beside whatever keyboard input
/// method is selected instead of replacing it. It asks for no key events and has no window; all it does is write
/// the text VibeWand sends into the text field that has the focus.
@objc(VibeWandInputController)
final class InputController: IMKInputController, InputTextClient {
    static let composer = InputComposer()
    private static let caret = NSRange(location: NSNotFound, length: NSNotFound)

    var application: String { client()?.bundleIdentifier() ?? "" }
    func mark(_ text: String) {
        client()?.setMarkedText(text, selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: Self.caret)
    }
    func insert(_ text: String) { client()?.insertText(text, replacementRange: Self.caret) }
    var marking: Bool {
        guard let range = client()?.markedRange() else { return false }
        return range.location != NSNotFound && range.length > 0
    }

    override func recognizedEvents(_ sender: Any!) -> Int { 0 }
    override func activateServer(_ sender: Any!) { Self.composer.activate(self) }
    override func deactivateServer(_ sender: Any!) { Self.composer.deactivate(self) }
    override func commitComposition(_ sender: Any!) { Self.composer.interrupt(self) }
}

/// Switching this input method on and off in macOS. VibeWand runs this program with `select`, `enable` or
/// `deselect` to have it done, because a selection asked for by the app that has just put the input method in
/// place does not hold, while one asked for by a program started afterwards does. It stops being listed when
/// VibeWand deletes it.
enum InputSource {
    private static var this: TISInputSource? {
        let filter = [kTISPropertyBundleID as String: InputLink.bundleID] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }
    private static func holds(_ property: CFString) -> Bool {
        guard let this, let value = TISGetInputSourceProperty(this, property) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue() == kCFBooleanTrue
    }
    /// A palette is selected beside the keyboard input source, not instead of it. macOS keeps a list of the
    /// input methods of other makers that the user has allowed, by identifier, and selects none that is not on
    /// it; once there, an identifier stays when the input method is deleted.
    static func select() -> InputLink.Selection {
        if !holds(kTISPropertyInputSourceIsSelected) {
            TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
            if let this { TISSelectInputSource(this) }
        }
        if holds(kTISPropertyInputSourceIsSelected) { return .selected }
        return this != nil && !holds(kTISPropertyInputSourceIsEnabled) ? .notAllowed : .failed
    }
    /// Asks macOS to enable this input method. For one of another maker macOS enables nothing by this call: it
    /// brings System Settings → Keyboard to the front, where the user is to be asked.
    static func enable() {
        TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        if let this { TISEnableInputSource(this) }
    }
    static func deselect() { if let this { TISDeselectInputSource(this) } }
}

switch CommandLine.arguments.dropFirst().first {
case "select": exit(InputSource.select().rawValue)
case "enable": InputSource.enable(); exit(0)
case "deselect": InputSource.deselect(); exit(0)
default: break
}
let server = IMKServer(name: InputLink.connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
let listener = try? InputListener(path: InputLink.socketPath,
    admits: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier == InputLink.owner },
    onLine: InputController.composer.connect)
NSApplication.shared.run()
