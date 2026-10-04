#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
swift build -c release
task_binary_dir="$(swift build -c release --show-bin-path)"
task_app="$task_root/dist/VibeWand.app"
mkdir -p "$task_root/dist"
task_stage="$(mktemp -d "$task_root/dist/.bundle-build.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
task_staged_app="$task_stage/VibeWand.app"
mkdir -p "$task_staged_app/Contents/MacOS" "$task_staged_app/Contents/Resources"
cp "$task_binary_dir/VibeWand" "$task_staged_app/Contents/MacOS/VibeWand"
bash "$task_root/scripts/build-icon.sh" "$task_staged_app/Contents/Resources/AppIcon.icns"
cp "$task_root/assets/app-icon/BrandMarkLight.png" "$task_staged_app/Contents/Resources/BrandMarkLight.png"
for task_asset in controller gamepad remote; do
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
<key>CFBundleShortVersionString</key><string>0.5.5</string>
<key>CFBundleVersion</key><string>14</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>GCSupportsControllerUserInteraction</key><true/>
<key>GCSupportedGameControllers</key><array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>
<key>NSAccessibilityUsageDescription</key><string>读取当前输入框和选择器状态，并执行你通过 VibeWand 发出的光标、删除、确认、会话和标签页操作。</string>
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
codesign --force --sign "$task_signing_identity" --identifier org.vibekey.bridge "$task_staged_app"
codesign --verify --deep --strict "$task_staged_app"
if [ -d "$task_app" ]; then
  task_backup="$(mktemp -d "$task_root/dist/.previous-build.XXXXXX")"
  mv "$task_app" "$task_backup/VibeWand.app"
fi
mv "$task_staged_app" "$task_app"
printf '%s\n' "$task_app"
