#!/bin/bash
# Compiles the watcher and checks link extraction against fixtures/events.json (no calendar access needed).
set -euo pipefail
cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O never_late.swift -o "$tmp/szm"

actual=$(NEVER_LATE_STATE_DIR="$tmp/state" "$tmp/szm" --dry-run --fixture fixtures/events.json | sed -n 's/^.* DRY-RUN would open //p')
expected=$(cat <<'LINKS'
https://acme.zoom.us/j/111111111?pwd=abc for "URL field wins"
https://us02web.zoom.us/j/444444444?pwd=xyz for "Location fallback"
https://zoom.us/j/555555555?pwd=a&b=1 for "Notes with escaped html"
zoommtg://zoom.us/join?confno=666666666 for "zoommtg scheme"
https://meet.google.com/abc-defg-hij?authuser=0 for "Meet in url"
https://meet.google.com/xyz-abcd-efg for "Meet via google redirect in notes"
https://zoom.us/j/123456789 for "Zoom in location beats Meet in notes"
LINKS
)

if [ "$actual" = "$expected" ]; then
    echo "PASS"
else
    echo "FAIL" >&2
    diff <(echo "$expected") <(echo "$actual") >&2 || true
    exit 1
fi
