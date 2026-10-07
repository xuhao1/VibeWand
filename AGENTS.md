# Repository Guidelines

## Project Structure & Module Organization

VibeWand is a native macOS Swift package. Keep device decoding, gesture mapping, and application operations separate.

- `Sources/AU05Device/`: HID protocols, discovery, and device lifecycle; `Sources/AU05Capture/`: capture CLI.
- `Sources/VibeWandBridge/`: SwiftUI/AppKit interface, gestures, application adapters, overlays, the controls card, dictation delivery, the first-run guide, the keyboard as a device, `ListeningModel`, which turns the kernel's model requests into a session of the voice service's Omni model, and `VocabularyKeeper`, which follows a dictated text field when the user allows it and has the kernel learn terms from what they changed. Preserve the internal target name and `org.vibewand.bridge` bundle identifier: they were `VibeKeyBridge` and `org.vibekey.bridge` until 0.11.0, and `FormerIdentity` takes over the settings such a version left, which costs every user their macOS permissions once.
- `Sources/SpeechInput/`: recording, speech providers, the SenseVoice recogniser that runs on this Mac and its models, credentials, dictation lifecycle, the Omni model as a party to a conversation that hears a recording, calls tools and speaks, and that says a given line as written when asked to (`QwenRealtimeConversation`), the same service's synthesis for when the model that acts has no voice (`QwenSpeechSynthesis`), the voices of both as the service lists them (`SpeechVoice`), what is said aloud (`SpeechOutput`), and a dictated passage as written and as the user left it, with the notebook of those waiting to be learned from (`DictationRevision`); `Sources/SpeechAPICheck/`: audio-file checks of a speech API and of that recogniser.
- `Sources/InputLink/`: the wire between VibeWand and its input method, and everything that input method does (`InputComposer`), with no dependency beyond Foundation; `Sources/VibeWandInput/`: the input method itself, a palette that shows a dictation in the focused text field of any app while it is spoken. Keep it a thin shell over `InputComposer`: it asks for no key events and links nothing but Foundation, AppKit, InputMethodKit and Carbon's Text Input Sources, with which it selects itself. A change to how it is installed or selected is checked on a real system, from a state without it (`docs/voice-input.md`).
- `Sources/WandAgent/`: UI-independent command mode: the harness and the profile written for it, the kernel process and its protocol, the coordinator's prompt, the model route and model listing, the endpoint through which VibeWand serves a model to its own kernel (`ModelEndpoint`), the tool catalog and socket, the gateway with its permission modes, task records. `kernel/coordinator` is the one coordinator bundle that both the shipped DeepSeek Harness and one the user installed (plugin mode) run; it declares the harness versions it was verified on. `kernel/overlay` sets VibeWand on an installed harness's own agent when the user hands over its tools. `kernel/view` is the plugin an installed harness's desktop and web apps load to show command mode: a host half that serves a spoken command's recording from VibeWand's task records and a browser half, written by hand in the form the harness's own client bundles take, that shows the command as a voice message. It is added to a harness with that harness's own plugin command, never by writing its profiles. The rest of `kernel/` is the shipped kernel's locked package set and boot check; that set includes the harness's SenseVoice plug-in, which no row loads: dictation runs its recogniser, and `Harness` says where it is.
- `site/`: the project site, one static page in Chinese and English with no build step, served as vibewand.xuhao1.me from the public repository `xuhao1/vibewand-site`. Its text follows the README of the released version, and it states that version in its download links. The promo film it plays is not kept here: `promo/tools/web.sh` makes it into the ignored `site/video/`, and publishing leaves the published copies alone when that folder is absent. Its downloads are this repository's releases since the repository was opened with 0.11.2; see `docs/development.md`.
- `Tests/`: matching XCTest targets. `assets/` contains artwork, and under `assets/apps/` the icons of supported apps, which belong to their owners; `profiles/` contains JSON examples; `docs/` contains bilingual guides; `tools/dualsense-mic/` contains microphone experiments and the bridge.

## Build, Test, and Development Commands

Use full Xcode 26+ for the current SDK APIs. The package targets macOS 26 on arm64; the bundled microphone helper requires Homebrew Opus under `/opt/homebrew`.

- `swift build`: compile package targets for development.
- `swift test`: run all XCTest suites.
- `bash scripts/build-app.sh`: assemble and sign `dist/VibeWand.app`. It runs `scripts/build-kernel.sh`, which downloads the pinned Node.js and DeepSeek Harness packages for command mode; `VIBEWAND_SKIP_KERNEL=1` skips that.
- `bash scripts/run.sh`: launch the bundle, building it if absent; rebuild explicitly after source changes.
- `bash scripts/publish-site.sh`: publish `site/` to `xuhao1/vibewand-site`; `python3 -m http.server --directory site` previews it first.

For toolchain issues, set `DEVELOPER_DIR` to the installed Xcode developer directory; see `docs/development.md`.

## Coding Style & Naming Conventions

Use four-space Swift indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Name files after their principal type or responsibility. Follow surrounding formatting; no repository formatter or linter is configured. Keep UI-independent speech logic in `SpeechInput`, device decoding in `AU05Device`, and command-mode logic that needs no window in `WandAgent`. The model's reach is the tool catalog in `Sources/WandAgent/Tools.swift`, which also holds the choice of voice, mounted only while VibeWand speaks in a voice of the voice service, and the three tools of the vocabulary's keeper, a session of its own; adding a tool, or a row or package to `kernel/coordinator`, is a deliberate change with a test to update. A change to the kernel's package set is also checked against `third-party/README.md`, looking inside any prebuilt library it brings, and against the open items in `docs/licensing-open-items.md`. Keep the two harnesses on one code path: what differs between them belongs in the profile `Harness` writes, not in a second implementation.

## Testing Guidelines

Use XCTest with `*Tests.swift` files and descriptive `test...` methods. Run focused checks with `swift test --filter InteractionTests`, then the full suite for behavior changes. Cover state transitions, cancellation, and malformed input; no numeric coverage threshold is configured. Hardware and app compatibility claims require real-device or real-app verification, including observed UI outcomes. Command mode is tested with `ScriptedKernel` and never drives another app from `swift test`; the opt-in `KernelLiveTests` use a real kernel with a stand-in desktop, the opt-in `ListeningLiveTests` do the same on the voice service's own model with recordings in place of words, and the opt-in `CommandLiveTests` act on real apps in windows they open for themselves and read every result back (`docs/command-acceptance.md`). A live test that posts keys releases what it pressed however it ends, one that moves the pointer puts it back, and one that changes a setting in an app the user works in, such as Codex's model, puts it back the same way.

## Commit & Pull Request Guidelines

History uses concise imperative subjects, such as “Add experimental DualSense Bluetooth microphone bridge.” Keep changes focused. Describe the problem, resulting behavior, validation, and relevant issues; include screenshots for UI changes and device/app versions for compatibility fixes. Update both documentation languages, verify links, and distinguish illustrations from actual screenshots. Read `LICENSE` and `CONTRIBUTING.md` before contributing.

## Security & Agent Configuration

Keep speech keys in macOS Keychain and Feishu credentials in `lark-cli` secure storage; never write secrets to repository files or conversation output. Redact private text and audio from shared evidence.

For Feishu, use explicit per-command `--profile soarlab` for school/SOARLAB/学校/南大/南京大学/课题组 and `--profile mondo` for company/mondo/公司/妙动/妙动科技. Ask which organization when context is insufficient; do not change the default profile for one operation.
