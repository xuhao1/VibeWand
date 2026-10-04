#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
task_out="$task_root/output/dualsense-mic"
task_app="$task_out/VibeWand Mic.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Frameworks" "$task_app/Contents/Resources"
cc -std=c11 -O2 -mmacosx-version-min=26.0 -Wall -Wextra -Werror -c "$task_root/tools/dualsense-mic/bridge/AudioRing.c" -o "$task_out/AudioRing.o"
swiftc -swift-version 5 -O -target arm64-apple-macos26.0 \
    -I/opt/homebrew/include -L/opt/homebrew/lib -lopus -lz \
    -import-objc-header "$task_root/tools/dualsense-mic/bridge/Bridge.h" \
    "$task_root/tools/dualsense-mic/bridge/main.swift" "$task_out/AudioRing.o" \
    -framework AppKit -framework AVFoundation -framework CoreAudio -framework IOKit \
    -o "$task_app/Contents/MacOS/VibeWandMic"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.vibewand.dualsense-mic.experimental</string>
<key>CFBundleName</key><string>VibeWand Mic</string>
<key>CFBundleExecutable</key><string>VibeWandMic</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSAudioCaptureUsageDescription</key><string>把本程序解码的 DualSense 麦克风声音接入系统输入。只采集本程序的音频，不采集其他应用或系统混音。</string>
<key>NSMicrophoneUsageDescription</key><string>验证 DualSense 蓝牙麦克风的本地音频输入。</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>连接已配对的 DualSense 手柄麦克风。</string>
</dict></plist>
PLIST
cp /opt/homebrew/opt/opus/lib/libopus.0.dylib "$task_app/Contents/Frameworks/libopus.0.dylib"
cp /opt/homebrew/opt/opus/COPYING "$task_app/Contents/Resources/Opus-COPYING.txt"
install_name_tool -change /opt/homebrew/opt/opus/lib/libopus.0.dylib '@executable_path/../Frameworks/libopus.0.dylib' "$task_app/Contents/MacOS/VibeWandMic"
install_name_tool -id '@rpath/libopus.0.dylib' "$task_app/Contents/Frameworks/libopus.0.dylib"
codesign --force --sign - "$task_app/Contents/Frameworks/libopus.0.dylib"
codesign --force --sign - "$task_app"
echo "$task_app"
