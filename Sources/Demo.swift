import Foundation

/// A fixed, fake arrangement for documentation screenshots. Enabled with `--demo`.
///
/// Deliberately never touches the real registry: screenshots taken this way cannot leak
/// real session names, working directories, or client project names into the README.
enum Demo {

    static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    /// Slots 1–7 occupied with a mix of states, 8 and 9 left hollow to show empty slots.
    private static let script: [(name: String, state: SessionState)?] = [
        ("api refactor",  .finished),
        ("docs site",     .running),
        ("payments",      .finished),
        ("db migration",  .waiting),
        ("infra",         .finished),
        ("scratch",       .running),
        ("release prep",  .finished),
        nil,
        nil,
    ]

    static func layout() -> Layout {
        let slots = (0..<Layout.slotCount).map { index -> Layout.Slot in
            let entry = index < script.count ? script[index] : nil
            return Layout.Slot(
                number: index + 1,
                placement: entry.map {
                    Layout.Placement(session: session(named: $0.name, state: $0.state),
                                     deniedClaim: nil)
                })
        }
        return Layout(slots: slots, overflow: [])
    }

    private static func session(named name: String, state: SessionState) -> Session {
        Session(
            record: SessionRecord(
                pid: 0, sessionId: nil, cwd: nil, startedAt: nil, procStart: nil,
                name: name, nameSource: nil, status: nil, kind: nil, statusUpdatedAt: nil),
            state: state)
    }
}
