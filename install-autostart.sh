#!/bin/bash
# Register ClaudeStatus as a LaunchAgent so it starts at login.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/ClaudeStatus.app/Contents/MacOS/ClaudeStatus"
LABEL="io.github.claude-statusbar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PL

# Stop any running/registered instance, then (re)register.
pkill -f "ClaudeStatus.app/Contents/MacOS/ClaudeStatus" 2>/dev/null || true
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl kickstart -k "gui/$UID_NUM/$LABEL"
echo "registered & started: $LABEL"
