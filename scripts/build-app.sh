#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
task_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
task_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
# The Swift Build backend can write the deployment target into the SDK field.
# Set the linker platform explicitly; keep macOS 13 as the minimum runtime.
# VIBEWAND_CONFIGURATION=debug gives a fast development bundle; releases use the default.
task_configuration="${VIBEWAND_CONFIGURATION:-release}"
swift build -c "$task_configuration" --sdk "$task_sdk_path" -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$task_sdk_version"
task_binary_dir="$(swift build -c "$task_configuration" --show-bin-path)"
task_app="${VIBEWAND_APP_PATH:-$task_root/dist/VibeWand.app}"
mkdir -p "$task_root/dist"
task_stage="$(mktemp -d "$task_root/dist/.bundle-build.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
task_staged_app="$task_stage/VibeWand.app"
mkdir -p "$task_staged_app/Contents/MacOS" "$task_staged_app/Contents/Resources" "$task_staged_app/Contents/Helpers" "$task_staged_app/Contents/Frameworks"
cp "$task_binary_dir/VibeWand" "$task_staged_app/Contents/MacOS/VibeWand"
task_linked_sdk="$(otool -l "$task_staged_app/Contents/MacOS/VibeWand" | awk '/LC_BUILD_VERSION/ { active=1 } active && $1 == "sdk" { print $2; exit }')"
if [ "$task_linked_sdk" != "$task_sdk_version" ]; then
  printf 'SDK mismatch: built against %s, executable reports %s\n' "$task_sdk_version" "$task_linked_sdk" >&2
  exit 1
fi
# Bundle the Bluetooth HID/Opus bridge for the opt-in controller voice path.
# Development builds may reuse the helper from an earlier run (VIBEWAND_REUSE_HELPER=1).
if [ "${VIBEWAND_REUSE_HELPER:-0}" != "1" ] || [ ! -x "$task_root/output/dualsense-mic/VibeWand Mic.app/Contents/MacOS/VibeWandMic" ]; then
  sh "$task_root/tools/dualsense-mic/bridge/build.sh"
fi
cp "$task_root/output/dualsense-mic/VibeWand Mic.app/Contents/MacOS/VibeWandMic" "$task_staged_app/Contents/Helpers/VibeWandMic"
cp "$task_root/output/dualsense-mic/VibeWand Mic.app/Contents/Frameworks/libopus.0.dylib" "$task_staged_app/Contents/Frameworks/libopus.0.dylib"
cp "$task_root/output/dualsense-mic/VibeWand Mic.app/Contents/Resources/Opus-COPYING.txt" "$task_staged_app/Contents/Resources/Opus-COPYING.txt"
bash "$task_root/scripts/build-icon.sh" "$task_staged_app/Contents/Resources/AppIcon.icns"
cp "$task_root/assets/app-icon/BrandMarkLight.png" "$task_staged_app/Contents/Resources/BrandMarkLight.png"
for task_asset in controller gamepad gamepad-overlay remote; do
  if [ -f "$task_root/assets/device/$task_asset.png" ]; then
    cp "$task_root/assets/device/$task_asset.png" "$task_staged_app/Contents/Resources/$task_asset.png"
  fi
done
cp "$task_root/LICENSE" "$task_staged_app/Contents/Resources/LICENSE"
cp -R "$task_root/third-party" "$task_staged_app/Contents/Resources/third-party"
cat > "$task_staged_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>VibeWand</string>
<key>CFBundleDisplayName</key><string>VibeWand</string>
<key>CFBundleIdentifier</key><string>org.vibekey.bridge</string>
<key>CFBundleExecutable</key><string>VibeWand</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.8.1</string>
<key>CFBundleVersion</key><string>22</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>GCSupportsControllerUserInteraction</key><true/>
<key>GCSupportedGameControllers</key><array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>
<key>NSAccessibilityUsageDescription</key><string>读取当前输入框和选择器状态，并执行你通过 VibeWand 发出的光标、删除、确认、会话和标签页操作。</string>
<key>NSAudioCaptureUsageDescription</key><string>将 DualSense 蓝牙麦克风声音接入本程序可选的语音输入；仅接收本程序发布的音频。</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>连接已配对的 DualSense 手柄麦克风。</string>
<key>NSMicrophoneUsageDescription</key><string>按住听写键时使用麦克风，将语音转换为输入框中的文字。</string>
<key>NSSpeechRecognitionUsageDescription</key><string>使用 macOS 语音识别，将你主动录制的语音转换为文字。</string>
</dict></plist>
PLIST
task_signing_identity="${VIBEWAND_SIGNING_IDENTITY:-${VIBEKEY_SIGNING_IDENTITY:-}}"
if [ -z "$task_signing_identity" ]; then
  task_identity_list="$(security find-identity -v -p codesigning | awk '/Apple Development:/ { print $2 }')"
  task_identity_count="$(printf '%s\n' "$task_identity_list" | awk 'NF { n++ } END { print n+0 }')"
  if [ "$task_identity_count" -eq 1 ]; then
    task_signing_identity="$task_identity_list"
  elif [ "$task_identity_count" -gt 1 ]; then
    printf '%s\n' 'Multiple Apple Development identities found; select one with VIBEWAND_SIGNING_IDENTITY.' >&2
    exit 1
  else
    task_signing_identity='-'
    printf '%s\n' 'No development identity found; using ad-hoc signing. Updates may require Accessibility re-registration.' >&2
  fi
fi
codesign --force --sign "$task_signing_identity" "$task_staged_app/Contents/Frameworks/libopus.0.dylib"
codesign --force --sign "$task_signing_identity" "$task_staged_app/Contents/Helpers/VibeWandMic"
codesign --force --sign "$task_signing_identity" --identifier org.vibekey.bridge "$task_staged_app"
codesign --verify --deep --strict "$task_staged_app"
if [ -d "$task_app" ]; then
  if [ "${VIBEWAND_KEEP_PREVIOUS:-1}" = "1" ]; then
    task_backup="$(mktemp -d "$task_root/dist/.previous-build.XXXXXX")"
    mv "$task_app" "$task_backup/VibeWand.app"
  else
    rm -rf "$task_app"
  fi
fi
mkdir -p "$(dirname "$task_app")"
mv "$task_staged_app" "$task_app"
printf '%s\n' "$task_app"
