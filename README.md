# never-late

**Never be late for a meeting ever again.**

A tiny macOS background agent that opens your Zoom or Google Meet link about a minute before the meeting starts. Zoom is already up and waiting when the clock hits the hour, instead of you scrambling through your calendar to find the link.

## Why this exists

Joining a meeting on time should be the most automatic thing in the world. It looks like an obvious feature for Zoom to have, but it doesn't. I was tired of being five minutes late to meetings. It isn't professional, and the cause was never bad intent, just "one more thing" and a calendar notification I swiped away. So I built the feature myself. Hopefully it helps you too.

## Pro tip

In Zoom, turn on **Settings → Video → Turn off my video when joining a meeting**, and mute your microphone on join too. This tool joins for you, so if you aren't at your desk it should not stream your living room to your colleagues.

## How it works

It is a single Swift file with no dependencies. It reads events from Calendar.app through EventKit, so it works with any account Calendar.app syncs (iCloud, Google, Exchange, ...). launchd runs it every 60 seconds, and each run:

1. Reads events starting in the next ~55–125 seconds from all calendars. The window is wider than 60 seconds so consecutive runs overlap and a late launchd tick can't skip a meeting.
2. Skips all-day events and events you declined or marked tentative. Unanswered invites and events you organize are kept.
3. Looks for a link in the event's URL field, then its location, then its notes: `zoom.us/j/…`, `zoommtg://…` or `meet.google.com/xxx-xxxx-xxx`. Events without a link are ignored.
4. Runs `open <link>` once per meeting. Which meetings were already opened is remembered in `~/Library/Application Support/never-late/state.json` (entries are pruned after 24 hours).

A failure on one event is logged and doesn't affect the others. The log is `~/Library/Logs/never-late.log`; it only gets a line when something starts soon or goes wrong.

## Install

Requires macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
./install.sh
```

This compiles the binary into `bin/NeverLate.app`, signs it ad hoc, generates the launchd plist for your paths and loads it. Calendar access belongs to that app bundle, not to your terminal. If macOS asks, choose **Allow Full Access**. Rebuilding changes the signature, so you may be asked again.

To see what the agent sees (this must go through the app bundle so it uses the bundle's permission):

```bash
open -W -n --stdout /dev/stdout bin/NeverLate.app --args --debug --window -3600 3600
```

`--debug` lists every event in the window and why it was kept or skipped. Other options: `--calendars "Work,Home"` to restrict calendars, `--dry-run` to log without opening anything.

Uninstall with `./uninstall.sh`.

## Tests

```bash
./test.sh
```

Compiles the program and checks link extraction against `fixtures/events.json`. It doesn't touch your calendar.

## Limitations

- Only events that Calendar.app has synced are seen. A meeting created in the web UI moments before it starts may not have arrived yet.
- If the Mac is asleep at the trigger time, that meeting isn't opened afterwards.
- Zoom `https` links open in your default browser first, which then hands off to the Zoom app.
- Zoom and Google Meet only. Teams, Webex and others are not matched.

## License

MIT
