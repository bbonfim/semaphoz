import Foundation

/// One entry from Claude Code's live session registry (`~/.claude/sessions/<pid>.json`).
///
/// The registry is maintained by Claude Code itself: each interactive session writes
/// its own file and keeps `status` current within a couple of seconds. We only read it.
struct SessionRecord: Decodable {
    let pid: Int32
    let sessionId: String?
    let cwd: String?
    let startedAt: Double?          // ms since epoch
    let procStart: String?          // e.g. "Tue Aug 11 12:08:06 2026"
    let name: String?
    let nameSource: String?
    let status: String?             // "busy" | "idle"
    let kind: String?               // "interactive" | "bg"
    let statusUpdatedAt: Double?    // ms since epoch
}

/// What a dot can show. Stage 1 only ever produces `.running` / `.finished`;
/// `.waiting` arrives with the hook layer in stage 2.
enum SessionState {
    case running     // yellow  — registry says "busy"
    case waiting     // red     — blocked on a permission prompt (stage 2)
    case finished    // green   — idle, turn complete
}

struct Session {
    let record: SessionRecord
    let state: SessionState

    var pid: Int32 { record.pid }

    /// The slot this session claims, from a `[n]` prefix on its name — set with
    /// `/rename [3] whatever`. Range is validated by `Layout`, which owns the slot count.
    var claim: Int? { Session.parseClaim(record.name ?? "").claim }

    /// Name with any `[n]` prefix stripped, so the dropdown stays readable.
    var displayName: String {
        let label = Session.parseClaim(record.name ?? "").label
        if !label.isEmpty { return label }
        if let cwd = record.cwd, !cwd.isEmpty { return (cwd as NSString).lastPathComponent }
        return "pid \(record.pid)"
    }

    var cwd: String { record.cwd ?? "" }

    /// Controlling terminal, or nil for background sessions with no terminal to focus.
    var tty: String? { Registry.tty(pid: pid) }

    /// Pulls a `[n]` out of a session name, wherever it sits — `[3] review`, `review [3]`
    /// and `review [3] wip` are all equivalent, so the tag can go wherever reads best.
    ///
    /// Only brackets wrapping digits count, so `[wip] foo` and `foo [bar]` stay intact.
    static func parseClaim(_ raw: String) -> (claim: Int?, label: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let tag = trimmed.range(of: #"\[\d+\]"#, options: .regularExpression),
              let number = Int(trimmed[tag].dropFirst().dropLast())
        else { return (nil, trimmed) }

        // Replace with a space and re-join, so lifting a tag out of the middle of a name
        // does not leave a double space behind.
        let label = trimmed.replacingCharacters(in: tag, with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return (number, label)
    }
    var startedAt: Date {
        Date(timeIntervalSince1970: (record.startedAt ?? 0) / 1000)
    }
    var idleFor: TimeInterval {
        guard let ms = record.statusUpdatedAt else { return 0 }
        return Date().timeIntervalSince1970 - ms / 1000
    }
}

enum Registry {
    static let directory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions")

    /// Read every registry entry and keep only the ones backed by a live process.
    ///
    /// Sorted oldest-first, which is the default left-to-right slot order.
    static func liveSessions() -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        let decoder = JSONDecoder()
        var out: [Session] = []

        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(SessionRecord.self, from: data),
                  isAlive(record)
            else { continue }

            out.append(Session(record: record, state: state(for: record.status)))
        }

        return out.sorted { $0.startedAt < $1.startedAt }
    }

    /// Claude Code's own status enum is `busy | idle | waiting`, and it maps cleanly onto
    /// the three lights. `waiting` is emitted while a session sits on a permission prompt,
    /// including by older already-running sessions (observed on 2.1.220), so no hooks or
    /// session restarts are needed to light one red.
    private static func state(for status: String?) -> SessionState {
        switch status {
        case "busy":    return .running
        case "waiting": return .waiting
        default:        return .finished
        }
    }

    /// A live PID is not enough — PIDs get recycled, and a recycled one would render a
    /// phantom session. Claude Code performs this same procStart check internally.
    private static func isAlive(_ record: SessionRecord) -> Bool {
        guard record.pid > 0 else { return false }
        guard let actual = processStartDate(pid: record.pid) else { return false }
        let candidates = record.procStart.map(parseProcStart) ?? []
        guard !candidates.isEmpty else {
            return true  // no usable start time; fall back to liveness alone
        }
        return candidates.contains { abs(actual.timeIntervalSince($0)) < 2.0 }
    }

    /// Kernel process record. Returns nil when the PID is not running.
    static func procInfo(pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride

        let rc = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard rc == 0, size > 0 else { return nil }
        return info
    }

    /// Boot time of a process, via sysctl. Returns nil when the PID is not running.
    private static func processStartDate(pid: pid_t) -> Date? {
        guard let tv = procInfo(pid: pid)?.kp_proc.p_starttime else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    /// Controlling terminal of a process, e.g. `ttys004`.
    ///
    /// This is how a session is matched to a terminal window. Background sessions have no
    /// controlling terminal and return nil. Never match on window title: a tab's title can
    /// name a different session than the one whose shell actually owns the tty.
    static func tty(pid: pid_t) -> String? {
        guard let dev = procInfo(pid: pid)?.kp_eproc.e_tdev, dev != -1 else { return nil }
        guard let name = devname(dev, S_IFCHR) else { return nil }
        return String(cString: name)
    }

    /// `procStart` is written in `ps -o lstart` form, which space-pads single-digit days.
    ///
    /// Observed to be written in UTC rather than local time, so UTC is tried first. The
    /// local-time fallback keeps this working if that ever changes; both comparisons are
    /// exact to within two seconds, so neither weakens the PID-reuse guard.
    private static let procStartFormatters: [DateFormatter] = [TimeZone(identifier: "UTC"), .current]
        .map { zone in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            f.timeZone = zone
            return f
        }

    private static func parseProcStart(_ raw: String) -> [Date] {
        let normalized = raw.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return procStartFormatters.compactMap { $0.date(from: normalized) }
    }
}
