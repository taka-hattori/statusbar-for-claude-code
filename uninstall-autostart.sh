#!/bin/bash
# Unregister the LaunchAgent and stop StatusbarForClaudeCode.
set -euo pipefail
UID_NUM="$(id -u)"
# Includes the pre-rename label/app so old installs are removed too.
for LABEL in io.github.statusbar-for-claude-code io.github.claude-statusbar; do
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
done
pkill -f "StatusbarForClaudeCode.app/Contents/MacOS/StatusbarForClaudeCode" 2>/dev/null || true
pkill -f "ClaudeStatus.app/Contents/MacOS/ClaudeStatus" 2>/dev/null || true
echo "uninstalled: io.github.statusbar-for-claude-code"
