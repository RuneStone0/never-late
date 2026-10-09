#!/bin/bash
# Unloads and removes the launchd agent. Leaves the log and state file in place.
set -euo pipefail

LABEL=com.never-late.agent
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Uninstalled. Remove ~/Library/Logs/never-late.log and ~/Library/Application Support/never-late to clean up fully."
