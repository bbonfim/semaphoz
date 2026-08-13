import AppKit

/// Brings the terminal window hosting a session to the front.
///
/// A session is matched to a window by its controlling terminal (`ttys004`), which is the
/// only reliable key — a tab's title can name a different session than the shell that owns
/// the tty, for instance when a background session is being viewed from another tab.
enum TerminalFocus {

    enum App {
        case iTerm
        case terminal

        /// Matched against the truncated `p_comm` from the kernel, so prefixes only.
        static func matching(comm: String) -> App? {
            if comm.hasPrefix("iTerm") { return .iTerm }
            if comm == "Terminal" { return .terminal }
            return nil
        }
    }

    /// True when this session is hosted by a terminal we know how to drive.
    static func canFocus(_ session: Session) -> Bool {
        session.tty != nil && owningApp(of: session.pid) != nil
    }

    /// Focuses the session's window and tab. Runs off the main thread: AppleScript can
    /// block for seconds if the target app is busy, and the menu bar must stay responsive.
    static func focus(_ session: Session) {
        guard let tty = session.tty, let app = owningApp(of: session.pid) else { return }
        let script = script(for: app, tty: "/dev/\(tty)")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }

    /// Walks up the process tree looking for a terminal we recognise, so the right
    /// dialect of AppleScript is used rather than assuming one terminal.
    private static func owningApp(of pid: pid_t) -> App? {
        var current = pid
        for _ in 0..<16 {
            guard let info = Registry.procInfo(pid: current) else { return nil }

            var comm = info.kp_proc.p_comm
            let commSize = MemoryLayout.size(ofValue: comm)
            let name = withUnsafePointer(to: &comm) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: commSize) {
                    String(cString: $0)
                }
            }
            if let app = App.matching(comm: name) { return app }

            let parent = info.kp_eproc.e_ppid
            guard parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func script(for app: App, tty: String) -> String {
        switch app {
        case .iTerm:
            return """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      select t
                      select s
                      activate
                      return
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """
        case .terminal:
            return """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected tab of w to t
                    set index of w to 1
                    activate
                    return
                  end if
                end repeat
              end repeat
            end tell
            """
        }
    }
}
