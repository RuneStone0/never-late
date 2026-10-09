#!/bin/bash
# Builds the app bundle and (re)loads the launchd agent. Needs the Xcode Command Line Tools (swiftc).
set -euo pipefail

cd "$(dirname "$0")"
LABEL=com.never-late.agent
APP="$PWD/bin/NeverLate.app"
BINARY="$APP/Contents/MacOS/never_late"
LOG="$HOME/Library/Logs/never-late.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

command -v swiftc >/dev/null || { echo "swiftc not found; run: xcode-select --install" >&2; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

# Calendar access is granted to this signed bundle, not to the terminal it was started from.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O never_late.swift -o "$BINARY"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Add :CFBundleExecutable string never_late" \
    -c "Add :CFBundlePackageType string APPL" \
    -c "Add :LSUIElement bool true" \
    "$APP/Contents/Info.plist"
codesign -s - -f --deep "$APP"

sed -e "s|__BINARY__|$BINARY|" -e "s|__LOG__|$LOG|" launchd.plist.template > "$PLIST"
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed. Log: $LOG"
echo "If macOS asks for Calendar access, choose Allow Full Access. To check what the agent sees:"
echo "  open -W -n --stdout /dev/stdout \"$APP\" --args --debug --window -3600 3600"
