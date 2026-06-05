#!/bin/bash
# Unregister the LaunchAgent and stop ClaudeStatus.
set -euo pipefail
LABEL="io.github.claude-statusbar"
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -f "ClaudeStatus.app/Contents/MacOS/ClaudeStatus" 2>/dev/null || true
echo "uninstalled: $LABEL"
