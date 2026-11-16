# AGENTS.md

Context for AI coding agents (and humans) working on never-late. Read this before changing anything.

## What this is

A macOS background agent that opens the Zoom or Google Meet link of a calendar event about a minute before it starts. One Swift file (`never_late.swift`), no dependencies. launchd runs it every 60 seconds; each run is stateless apart from `~/Library/Application Support/never-late/state.json`.

## This repository is PUBLIC

`github.com/RuneStone0/never-late` is a public personal project. Everything committed, including history, commit messages, fixtures, logs pasted into docs and screenshots, is visible to the world and may be cached or indexed even if deleted later.

Before every commit and push:

1. Run `./scripts/privacy-scan.sh`. It must print `PASS`. It checks tracked files and the full git history for home paths, email addresses, tokens, private IPs, and any terms listed in `.privacy-patterns.local`.
2. Keep `.privacy-patterns.local` (gitignored, never commit it) populated with any employer, client or internal names that must never appear here. Create it if missing.
3. Look at `git diff --staged` yourself. The scanner is a safety net, not a substitute.

Hard rules:

- No employer, client or colleague names, internal hostnames, ticket IDs or work-calendar content. Fixtures and examples must be synthetic (`acme.zoom.us`, `meet.google.com/abc-defg-hij`, fake titles).
- No real meeting links, meeting IDs or passcodes, and no real log or `state.json` contents.
- No absolute paths containing a username; use `~` or `$HOME`.
- No credentials of any kind.
- Commit identity must be the personal GitHub noreply address, set repo-locally (`git config user.name` / `user.email`). The global git identity on this machine is a work one and must not leak into this repo. The scanner flags any non-noreply identity in history.
- Don't add `Co-Authored-By` trailers to commits.
- If something private does land in history, stop and tell the user. Don't just add a follow-up commit: history has to be rewritten and the secret rotated.

## Layout

| Path | Purpose |
| --- | --- |
| `never_late.swift` | The whole program: calendar read, filtering, link extraction, dedup state, `open` |
| `install.sh` / `uninstall.sh` | Build `bin/NeverLate.app`, ad-hoc sign it, (un)load the launchd agent |
| `launchd.plist.template` | launchd job template (`StartInterval` 60); `install.sh` fills in paths |
| `Info.plist` | App bundle metadata and the Calendar usage strings |
| `test.sh` + `fixtures/events.json` | Link-extraction tests, no calendar access needed |
| `scripts/privacy-scan.sh` | Pre-push privacy scan (see above) |
| `assets/logo.svg` | Project logo used in the README |

`bin/` is build output and gitignored.

## Build, test, run

```bash
./test.sh        # compiles and checks link extraction against fixtures; must print PASS
./install.sh     # builds bin/NeverLate.app and (re)loads the launchd agent
open -W -n --stdout /dev/stdout bin/NeverLate.app --args --debug --window -3600 3600   # see what the agent sees
```

Run `./test.sh` after any change to link extraction or filtering. Add a fixture for every new link shape.

## Design notes and gotchas

- **Timing window.** Default window is `5..70` seconds before start. The agent opens a meeting the first run it falls inside, so the open time lands between 10 and 70 seconds before the start. The window must stay wider than the 60 s run interval (max − min > 60) so consecutive runs overlap despite launchd jitter; dedup makes the overlap harmless. If you change the lead time, update the comment in `never_late.swift`, the usage line, and the README.
- **Calendar permission belongs to the app bundle**, not the terminal. Always test against the real calendar through `bin/NeverLate.app` via `open`, not by running the raw binary. Ad-hoc signing means every rebuild can re-trigger the permission prompt.
- **Don't run the raw binary against a real calendar in scripts or tests.** Use `--fixture` and `--dry-run`. `NEVER_LATE_STATE_DIR` redirects the state directory for tests.
- **Logs contain meeting titles.** `--debug` also logs URL, location and notes. Never paste real log output into the repo, issues or PRs.
- **Skipped on purpose:** all-day events, declined and tentative events. Unanswered invites and organizer events are kept.
- **Supported links:** Zoom (`zoom.us/j/…`, `zoommtg://…`) and Google Meet. Link lookup order is URL field, location, then notes.
- **Known limitation:** a Mac that is asleep at trigger time misses that meeting. Keep it documented in the README rather than hiding it.
- Keep it dependency-free and a single Swift file unless there's a strong reason.

## Conventions

- Match the existing terse comment style; comments explain why, not what.
- Keep the README accurate: features, options table, and limitations should reflect the code.
- Keep commits small with imperative subject lines.

## Pushing

The user's own remote is `git@github.com:RuneStone0/never-late.git`. The sandboxed shell cannot reach the SSH agent, so pushes from an agent session go over HTTPS with the personal account's token (`gh auth token --user RuneStone0`) supplied for that one command. Never store the token in the remote URL, in config, or in any file.
