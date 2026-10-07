import XCTest
import SwiftUI
import SpeechInput
import WandAgent
@testable import VibeWandBridge

/// The first-run guide: when it is owed, what its steps borrow and give back. Nothing here touches another app.
final class OnboardingTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let name = "VibeWand.OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    @MainActor private func makeRuntime(_ defaults: UserDefaults, senseVoice: SenseVoice? = nil) -> BridgeRuntime {
        let voice = VoiceInputController(preferences: SpeechPreferences(defaults: defaults), senseVoice: senseVoice, engineFactory: { _ in TranscriptReplayEngine(previews: ["你好"]) })
        let templates = DeviceTemplateStore(defaults: defaults)
        return BridgeRuntime(source: UnconfiguredHIDSource(template: templates.selectedTemplate), templates: templates, voiceInput: voice) {
            CommandController(settings: CommandSettings(defaults: defaults, credentials: KeychainSpeechCredentials(service: "org.vibewand.bridge.tests.none"), harness: { _ in nil }),
                              tools: CommandTools(adapter: $0), voice: $1, support: FileManager.default.temporaryDirectory.appendingPathComponent("vw-onboarding-\(UUID().uuidString)"))
        }
    }

    func testTheGuideIsOwedOnceToSomeoneNewAndNeverSprungOnSomeoneWhoAlreadySetVibeWandUp() {
        // A first launch: nothing has been saved yet.
        let fresh = isolatedDefaults()
        XCTAssertTrue(Onboarding.owed(fresh))
        // Launching writes preferences of its own; the guide is still owed until it has been closed.
        fresh.set(true, forKey: "hudVisible")
        XCTAssertTrue(Onboarding.owed(fresh))
        Onboarding.close(fresh)
        XCTAssertFalse(Onboarding.owed(fresh))

        // Someone who used a build before the guide existed has settings and no record of it.
        for key in Onboarding.earlier {
            let used = isolatedDefaults()
            used.set("x", forKey: key)
            XCTAssertFalse(Onboarding.owed(used), key)
            XCTAssertEqual(used.string(forKey: Onboarding.key), "done")
        }
        // Trying the first launch again is a choice made in Settings.
        let again = isolatedDefaults()
        again.set(true, forKey: "hudVisible")
        XCTAssertFalse(Onboarding.owed(again))
        Onboarding.showAtNextLaunch(again)
        XCTAssertTrue(Onboarding.owed(again))
    }

    @MainActor
    func testTheDeviceStepBorrowsTheDevicesInputAndGivesItBack() {
        let runtime = makeRuntime(isolatedDefaults())
        let guide = OnboardingModel(runtime: runtime)
        XCTAssertEqual(guide.step, .welcome)
        XCTAssertFalse(runtime.captureOnly)
        guide.go(to: .device)
        // While the device is being tried its buttons reach no app.
        XCTAssertTrue(runtime.captureOnly)
        XCTAssertEqual(guide.visited, [.welcome, .device])
        guide.advance(1)
        XCTAssertEqual(guide.step, .voice)
        XCTAssertFalse(runtime.captureOnly)
        // Someone who was only capturing input before stays that way afterwards.
        runtime.captureOnly = true
        guide.advance(-1)
        XCTAssertTrue(runtime.captureOnly)
        guide.leave(.device)
        XCTAssertTrue(runtime.captureOnly)
        runtime.captureOnly = false

        // Closing the window from the device step gives the input back too, and the last step's way on closes the guide.
        guide.go(to: .device)
        guide.leave(guide.step)
        XCTAssertFalse(runtime.captureOnly)
        var closed = 0
        guide.close = { closed += 1 }
        guide.go(to: .done)
        guide.advance(1)
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(OnboardingStep.allCases.map(\.rawValue), Array(0..<7))
    }

    /// Optional visual evidence of every step, from our own hidden views.
    @MainActor
    func testTheGuideRendersForReview() async throws {
        guard let path = ProcessInfo.processInfo.environment["VIBEWAND_ONBOARDING_REVIEW"] else { throw XCTSkip("Set VIBEWAND_ONBOARDING_REVIEW to a folder") }
        _ = NSApplication.shared
        let runtime = makeRuntime(isolatedDefaults())
        let overlay = OverlayController { _, _ in XCTFail("Rendering must not dispatch input") }
        let model = SettingsModel(runtime: runtime, overlay: overlay), guide = OnboardingModel(runtime: runtime)
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldLanguage = L10n.shared.language
        defer { L10n.shared.language = oldLanguage; guide.leave(guide.step); runtime.stop() }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: OnboardingView(model: model, guide: guide))
        window.contentView = host
        for (name, language, appearance) in [("zh", AppLanguage.zhHans, NSAppearance.Name.aqua), ("en-dark", .english, .darkAqua)] {
            L10n.shared.language = language
            window.appearance = NSAppearance(named: appearance)
            for step in OnboardingStep.allCases {
                guide.go(to: step)
                if step == .device { guide.tested = [.dial, .voice, .left] }
                try await Task.sleep(nanoseconds: 900_000_000)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name)-\(step.rawValue)-\(step).png"))
            }
        }
        // The same two steps for someone with no device: the keyboard as the layout.
        L10n.shared.language = .zhHans
        window.appearance = NSAppearance(named: .aqua)
        try runtime.selectTemplate(.keyboard)
        for step in [OnboardingStep.device, .keys] {
            guide.go(to: step); model.refresh()
            guide.tested = [.voice, .left]
            try await Task.sleep(nanoseconds: 900_000_000)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("keyboard-\(step.rawValue)-\(step).png"))
        }
        // Where its combinations are recorded: the settings for that layout, with a key no list names on one control.
        var layout = KeyboardLayout.standard
        layout.chords[DeviceControl.ok.rawValue] = KeyChord(code: 106)
        layout.chords[DeviceControl.escape.rawValue] = KeyChord(code: 0)
        let kept = KeyboardLayout.current
        KeyboardLayout.current = layout
        defer { KeyboardLayout.current = kept }
        for control in [DeviceControl.ok, .escape] {
            model.selectedControl = control.rawValue; model.refresh()
            let page = NSHostingView(rootView: DeviceSettings(model: model).padding(20).background(Color(nsColor: .windowBackgroundColor)))
            let frame = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [], backing: .buffered, defer: false)
            frame.contentView = page; frame.appearance = NSAppearance(named: .aqua)
            try await Task.sleep(nanoseconds: 900_000_000)
            page.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(page.bitmapImageRepForCachingDisplay(in: page.bounds))
            page.cacheDisplay(in: page.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("keyboard-settings-\(control.rawValue).png"))
        }
    }

    /// Optional visual evidence of SenseVoice in the voice settings and in the guide: with its models still to
    /// fetch into a harness's home, and with them in place. The recogniser is not run and nothing is downloaded.
    @MainActor
    func testSenseVoiceRendersForReview() async throws {
        guard let path = ProcessInfo.processInfo.environment["VIBEWAND_SENSEVOICE_REVIEW"] else { throw XCTSkip("Set VIBEWAND_SENSEVOICE_REVIEW to a folder") }
        _ = NSApplication.shared
        let files = FileManager.default, scratch = files.temporaryDirectory.appendingPathComponent("vw-sensevoice-review-\(UUID().uuidString)")
        defer { try? files.removeItem(at: scratch) }
        func asset(_ name: String, _ bytes: Int) -> [String: Any] { ["name": name, "url": "https://huggingface.co/org/repo/resolve/abc/\(name)", "bytes": bytes, "sha256": String(repeating: "0", count: 64)] }
        let store = scratch.appendingPathComponent(".dsh/speech-to-text/sensevoice")
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["models": ["int8": asset("model.int8.onnx", 239_233_841)], "tokens": asset("tokens.txt", 315_894), "vad": asset("silero_vad.onnx", 1_807_522)])
            .write(to: scratch.appendingPathComponent("assets.json"))
        let local = SenseVoice(runtime: .init(node: URL(fileURLWithPath: "/usr/bin/false"), worker: scratch.appendingPathComponent("worker.js"),
                                              assets: scratch.appendingPathComponent("assets.json"), stores: [store]))
        let defaults = isolatedDefaults()
        var speech = SpeechConfiguration()
        speech.mode = .builtIn; speech.selectProvider(.senseVoice)
        try SpeechPreferences(defaults: defaults).save(speech)
        let runtime = makeRuntime(defaults, senseVoice: local)
        let overlay = OverlayController { _, _ in XCTFail("Rendering must not dispatch input") }
        let model = SettingsModel(runtime: runtime, overlay: overlay), guide = OnboardingModel(runtime: runtime)
        let directory = URL(fileURLWithPath: path)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldLanguage = L10n.shared.language
        defer { L10n.shared.language = oldLanguage; guide.leave(guide.step); runtime.stop() }
        func render(_ view: some View, _ size: NSSize, _ name: String) async throws {
            let host = NSHostingView(rootView: AnyView(view.background(Color(nsColor: .windowBackgroundColor))))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [], backing: .buffered, defer: false)
            window.contentView = host; window.appearance = NSAppearance(named: .aqua)
            try await Task.sleep(nanoseconds: 700_000_000)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name))
        }
        for (name, language) in [("zh", AppLanguage.zhHans), ("en", .english)] {
            L10n.shared.language = language
            XCTAssertEqual(local.state, name == "zh" ? .missing : .ready)
            try await render(SpeechSettings(model: model, voice: runtime.voiceInput).id(name), NSSize(width: 1100, height: 1500), "settings-\(name)-\(name == "zh" ? "missing" : "ready").png")
            guide.go(to: .voice)
            try await render(OnboardingView(model: model, guide: guide).id(name), OnboardingView.size, "guide-\(name).png")
            guard name == "zh" else { continue }
            // The files as a harness would have left them: empty stand-ins of the right length.
            for (folder, file, bytes) in [("sensevoice-onnx", "model.int8.onnx", 239_233_841), ("sensevoice-onnx", "tokens.txt", 315_894), ("silero", "silero_vad.onnx", 1_807_522)] {
                let target = store.appendingPathComponent("models/\(folder)/\(file)")
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                files.createFile(atPath: target.path, contents: nil)
                let handle = try FileHandle(forWritingTo: target)
                try handle.truncate(atOffset: UInt64(bytes)); try handle.close()
            }
            local.refresh()
        }
    }
}

final class FormerIdentityTests: XCTestCase {
    func testSettingsKeptUnderTheFormerIdentifierAreTakenOverOnceAndWhatIsAlreadySetWins() {
        let defaults = UserDefaults.standard
        let former = "org.vibewand.tests.former." + UUID().uuidString, own = "org.vibewand.tests.own." + UUID().uuidString
        defer { defaults.removePersistentDomain(forName: former); defaults.removePersistentDomain(forName: own) }
        defaults.setPersistentDomain(["hudScale": 1.5, "onboardingState": "done", "VibeKeyBridge.overlayOrigin": "{10, 20}"], forName: former)
        defaults.setPersistentDomain(["hudScale": 2.0], forName: own)

        FormerIdentity.adopt(from: former, as: own, in: defaults)
        var settings = defaults.persistentDomain(forName: own) ?? [:]
        XCTAssertEqual(settings["hudScale"] as? Double, 2.0)
        XCTAssertEqual(settings["onboardingState"] as? String, "done")
        XCTAssertEqual(settings["VibeWandBridge.overlayOrigin"] as? String, "{10, 20}")
        XCTAssertNil(settings["VibeKeyBridge.overlayOrigin"])
        XCTAssertEqual(defaults.persistentDomain(forName: former)?["VibeKeyBridge.overlayOrigin"] as? String, "{10, 20}", "the former settings stay for a version that still reads them")

        // A setting removed afterwards does not come back from the former identifier at the next launch.
        settings["onboardingState"] = nil
        defaults.setPersistentDomain(settings, forName: own)
        FormerIdentity.adopt(from: former, as: own, in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: own)?["onboardingState"])

        // Nothing is taken over by a copy that still has the former identifier, nor outside an app bundle.
        let untouched = "org.vibewand.tests.none." + UUID().uuidString
        FormerIdentity.adopt(from: former, as: former, in: defaults)
        FormerIdentity.adopt(from: former, as: nil, in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: former)?[FormerIdentity.adopted])
        XCTAssertNil(defaults.persistentDomain(forName: untouched))
    }
}
