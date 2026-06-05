#!/bin/bash
# Build ClaudeStatus.app from main.swift.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/ClaudeStatus.app"
MACOS="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"

swiftc -O "$DIR/main.swift" -o "$MACOS/ClaudeStatus" -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeStatus</string>
  <key>CFBundleDisplayName</key><string>Claude Status</string>
  <key>CFBundleIdentifier</key><string>io.github.claude-statusbar</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>ClaudeStatus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST

echo "built: $APP"
