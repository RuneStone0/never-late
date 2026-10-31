// Opens the Zoom / Google Meet link of Calendar.app events that are about to start.
// Run once a minute by launchd (see install.sh); each run is stateless apart from state.json.
//
// Usage: never_late [options]
//   --dry-run         log what would be opened; don't open anything or write state
//   --debug           like --dry-run, and log every event in the window with why it was kept or skipped
//   --window MIN MAX  look at events starting MIN..MAX seconds from now (default 5 70; may be negative)
//   --calendars A,B   only read these calendar titles (default: all)
//   --fixture FILE    read events from a JSON file instead of Calendar (for tests)

import EventKit
import Foundation

// MARK: - Types

struct Event: Codable {
    var uid: String
    var title: String?
    var startEpoch: Double
    var url: String?
    var location: String?
    var notes: String?
}

struct StateEntry: Codable {
    var title: String
    var link: String
    var start: Double
    var triggeredAt: Double
}

struct RunError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    var dryRun = false
    var debug = false
    var window = (min: 5.0, max: 70.0)
    var calendarNames: [String]?
    var fixturePath: String?

    // The target is "about 10-70s before start". The far end is widened past min+60 so that
    // consecutive 60s runs always overlap despite launchd jitter; dedup makes the overlap harmless.
    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var remaining = arguments[...]

        func value(for flag: String) throws -> String {
            guard let next = remaining.popFirst() else { throw RunError("missing value for \(flag)") }
            return next
        }

        while let flag = remaining.popFirst() {
            switch flag {
            case "--dry-run":
                options.dryRun = true
            case "--debug":
                options.debug = true
                options.dryRun = true
            case "--window":
                guard let lo = Double(try value(for: flag)), let hi = Double(try value(for: flag)) else {
                    throw RunError("--window needs two numbers")
                }
                options.window = (lo, hi)
            case "--calendars":
                options.calendarNames = try value(for: flag).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "--fixture":
                options.fixturePath = try value(for: flag)
            default:
                throw RunError("unknown argument \(flag)")
            }
        }
        return options
    }
}

// MARK: - Paths and logging

let stateRetention: TimeInterval = 24 * 60 * 60

let stateDirectory: URL = {
    if let override = ProcessInfo.processInfo.environment["NEVER_LATE_STATE_DIR"] {
        return URL(fileURLWithPath: override)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/never-late")
}()
let stateFile = stateDirectory.appendingPathComponent("state.json")

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("\(formatter.string(from: Date())) \(message)")
    fflush(stdout)
}

// MARK: - Link extraction

let meetingPattern = try! NSRegularExpression(
    pattern: #"(?:https?://[\w.-]*zoom\.us/j/|zoommtg://)[^\s"'<>\)\]]+"#
        + #"|https?://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}(?:\?[^\s"'<>\)\]&]*)?"#,
    options: [.caseInsensitive]
)

func unescapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// Searches the URL field, then location, then notes; the first match wins.
func findMeetingLink(in event: Event) -> String? {
    for field in [event.url, event.location, event.notes] {
        let text = unescapeHTML(field ?? "")
        guard let match = meetingPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { continue }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
    }
    return nil
}

// MARK: - Calendar

func requestCalendarAccess(_ store: EKEventStore) throws {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess, .authorized:
        return
    case .notDetermined:
        var granted = false
        let done = DispatchSemaphore(value: 0)
        store.requestFullAccessToEvents { ok, _ in
            granted = ok
            done.signal()
        }
        done.wait()
        if !granted { throw RunError("calendar access denied") }
    case let status:
        throw RunError("calendar read access not granted (status \(status.rawValue); 4 = write-only). Allow Full Access in System Settings > Privacy & Security > Calendars")
    }
}

/// Why an event should not trigger a link, or nil if it should.
func skipReason(for event: EKEvent, window: ClosedRange<Date>) -> String? {
    // EventKit returns events that merely overlap the window; only ones that start in it count.
    if !window.contains(event.startDate) { return "not starting in window" }
    if event.isAllDay { return "all-day" }
    switch event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus {
    case .declined: return "declined"
    case .tentative: return "tentative"
    default: return nil  // accepted, unanswered, or no attendee list (you organize it)
    }
}

func fetchCalendarEvents(window: ClosedRange<Date>, options: Options) throws -> [Event] {
    let store = EKEventStore()
    try requestCalendarAccess(store)

    var calendars = store.calendars(for: .event)
    if let names = options.calendarNames { calendars = calendars.filter { names.contains($0.title) } }

    let predicate = store.predicateForEvents(withStart: window.lowerBound, end: window.upperBound, calendars: calendars)
    var events: [Event] = []

    for event in store.events(matching: predicate) {
        let reason = skipReason(for: event, window: window)

        if options.debug {
            let verdict = reason.map { "SKIP(\($0))" } ?? "KEEP"
            let notes = (event.notes ?? "").prefix(120)
            log("DEBUG \(verdict) \((event.title ?? "").debugDescription) calendar=\(event.calendar?.title ?? "-") start=\(event.startDate.map { "\($0)" } ?? "-") url=\(event.url?.absoluteString ?? "-") location=\(event.location ?? "-") notes=\(notes.debugDescription)")
        }
        if reason != nil { continue }

        events.append(Event(
            uid: event.eventIdentifier ?? "",
            title: event.title,
            startEpoch: event.startDate.timeIntervalSince1970,
            url: event.url?.absoluteString,
            location: event.location,
            notes: event.notes
        ))
    }
    return events
}

// MARK: - State

func loadState() -> [String: StateEntry] {
    guard let data = try? Data(contentsOf: stateFile) else { return [:] }
    do {
        return try JSONDecoder().decode([String: StateEntry].self, from: data)
    } catch {
        log("WARN state file unreadable, starting fresh: \(error)")
        return [:]
    }
}

func saveState(_ state: [String: StateEntry]) throws {
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: stateFile, options: .atomic)
}

// MARK: - Run

func openLink(_ link: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [link]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { throw RunError("open exited with status \(process.terminationStatus)") }
}

func run() -> Int32 {
    let options: Options
    do {
        options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        log("ERROR \(error)")
        return 2
    }

    let now = Date()
    let window = now.addingTimeInterval(options.window.min)...now.addingTimeInterval(options.window.max)

    let events: [Event]
    do {
        if let path = options.fixturePath {
            events = try JSONDecoder().decode([Event].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } else {
            events = try fetchCalendarEvents(window: window, options: options)
        }
    } catch {
        log("ERROR fetching events: \(error)")
        return 1
    }

    if !events.isEmpty {
        log("INFO \(events.count) event(s) starting soon: \(events.map { ($0.title ?? "").debugDescription }.joined(separator: ", "))")
    }

    var state = loadState().filter { now.timeIntervalSince1970 - $0.value.triggeredAt < stateRetention }
    var stateChanged = false

    // One bad event must not stop the others, so every failure below is logged and the loop continues.
    for event in events {
        let title = (event.title ?? "").debugDescription
        guard let link = findMeetingLink(in: event) else {
            log("INFO no meeting link found for \(title)")
            continue
        }

        let key = "\(event.uid)|\(Int(event.startEpoch))"
        // The same meeting can appear on several calendars under different ids.
        if state[key] != nil || state.values.contains(where: { $0.link == link && $0.start == event.startEpoch }) { continue }

        if options.dryRun {
            log("DRY-RUN would open \(link) for \(title)")
            continue
        }

        do {
            try openLink(link)
            state[key] = StateEntry(title: event.title ?? "", link: link, start: event.startEpoch, triggeredAt: now.timeIntervalSince1970)
            stateChanged = true
            log("OPENED \(link) for \(title)")
        } catch {
            log("ERROR opening \(link) for \(title): \(error)")
        }
    }

    if stateChanged {
        do {
            try saveState(state)
        } catch {
            log("ERROR saving state: \(error)")
            return 1
        }
    }
    return 0
}

exit(run())
