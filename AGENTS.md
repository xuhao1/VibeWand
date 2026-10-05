# Repository Guidelines

## Project Structure & Module Organization

VibeWand is a native macOS Swift package. Keep device decoding, gesture mapping, and application operations separate.

- `Sources/AU05Device/`: HID protocols, discovery, and device lifecycle; `Sources/AU05Capture/`: capture CLI.
- `Sources/VibeKeyBridge/`: SwiftUI/AppKit interface, gestures, application adapters, overlays, and dictation delivery. Preserve the internal target name and `org.vibekey.bridge` bundle identifier.
- `Sources/SpeechInput/`: recording, speech providers, credentials, and dictation lifecycle; `Sources/SpeechAPICheck/`: audio-file API checks.
- `Sources/WandAgent/`: UI-independent command mode: the kernel process and its protocol, the model route and model listing, the tool catalog and socket, the gateway with its permission modes, task records. `kernel/` holds the kernel's locked package set, its profile and boot check.
- `Tests/`: matching XCTest targets. `assets/` contains artwork; `profiles/` contains JSON examples; `docs/` contains bilingual guides; `tools/dualsense-mic/` contains microphone experiments and the bridge.

## Build, Test, and Development Commands

Use full Xcode 26+ for the current SDK APIs. The package targets macOS 26 on arm64; the bundled microphone helper requires Homebrew Opus under `/opt/homebrew`.

- `swift build`: compile package targets for development.
- `swift test`: run all XCTest suites.
- `bash scripts/build-app.sh`: assemble and sign `dist/VibeWand.app`. It runs `scripts/build-kernel.sh`, which downloads the pinned Node.js and DeepSeek Harness packages for command mode; `VIBEWAND_SKIP_KERNEL=1` skips that.
- `bash scripts/run.sh`: launch the bundle, building it if absent; rebuild explicitly after source changes.

For toolchain issues, set `DEVELOPER_DIR` to the installed Xcode developer directory; see `docs/development.md`.

## Coding Style & Naming Conventions

Use four-space Swift indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Name files after their principal type or responsibility. Follow surrounding formatting; no repository formatter or linter is configured. Keep UI-independent speech logic in `SpeechInput`, device decoding in `AU05Device`, and command-mode logic that needs no window in `WandAgent`. The model's reach is the tool catalog in `Sources/WandAgent/Tools.swift`; adding a tool, or a package to `kernel/profile`, is a deliberate change with a test to update.

## Testing Guidelines

Use XCTest with `*Tests.swift` files and descriptive `test...` methods. Run focused checks with `swift test --filter InteractionTests`, then the full suite for behavior changes. Cover state transitions, cancellation, and malformed input; no numeric coverage threshold is configured. Hardware and app compatibility claims require real-device or real-app verification, including observed UI outcomes. Command mode is tested with `ScriptedKernel` and never drives another app from `swift test`; the opt-in `KernelLiveTests` use a real kernel with a stand-in desktop, and the opt-in `CommandLiveTests` act on real apps in windows they open for themselves and read every result back (`docs/command-acceptance.md`).

## Commit & Pull Request Guidelines

History uses concise imperative subjects, such as “Add experimental DualSense Bluetooth microphone bridge.” Keep changes focused. Describe the problem, resulting behavior, validation, and relevant issues; include screenshots for UI changes and device/app versions for compatibility fixes. Update both documentation languages, verify links, and distinguish illustrations from actual screenshots. Read `LICENSE` and `CONTRIBUTING.md` before contributing.

## Security & Agent Configuration

Keep speech keys in macOS Keychain and Feishu credentials in `lark-cli` secure storage; never write secrets to repository files or conversation output. Redact private text and audio from shared evidence.

For Feishu, use explicit per-command `--profile soarlab` for school/SOARLAB/学校/南大/南京大学/课题组 and `--profile mondo` for company/mondo/公司/妙动/妙动科技. Ask which organization when context is insufficient; do not change the default profile for one operation.
