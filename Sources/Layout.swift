import Foundation

/// A fixed grid of slots. Because the grid is fixed, dots never slide: a slot is either
/// occupied or hollow, and its position on screen never depends on what else is running.
struct Layout {
    /// Nine, not ten, so every slot number has a keyboard analogue: terminals map ⌘1–⌘9
    /// to tabs, but ⌘0 is generally not a tab shortcut, leaving slot 10 the odd one out.
    /// Single digits also keep every number rendering at the same size in the menu bar.
    static let slotCount = 9

    /// A session placed on the grid, plus the claim it was refused (if any) so the
    /// dropdown can explain why a `[n]` did not land where the user expected.
    struct Placement {
        let session: Session
        let deniedClaim: Int?
    }

    struct Slot {
        let number: Int              // 1-based, matches the `[n]` typed via /rename
        let placement: Placement?

        var session: Session? { placement?.session }
    }

    let slots: [Slot]
    let overflow: [Placement]        // sessions past the grid; these vanish on exit

    var activeCount: Int { slots.compactMap(\.placement).count + overflow.count }

    /// Allocation, in two passes:
    ///
    /// 1. Sessions carrying a valid `[n]` claim their slot. Running these first is what
    ///    makes the claim authoritative — an auto-assigned session can never occupy a
    ///    claimed slot, so no eviction step is needed.
    /// 2. Everything else — unnumbered sessions, plus claims that were refused — takes
    ///    the lowest free slot, oldest first. Past the grid, they overflow to the right.
    ///
    /// A claim is refused when the number is out of range, or when an older live session
    /// already holds it. Oldest-wins keeps the outcome stable rather than depending on
    /// which duplicate happened to be read first.
    static func build(from sessions: [Session]) -> Layout {
        var occupants = [Int: Placement]()
        var fallback = [(session: Session, denied: Int?)]()

        for session in sessions {          // Registry returns these oldest-first
            guard let claim = session.claim else { continue }
            if (1...slotCount).contains(claim), occupants[claim] == nil {
                occupants[claim] = Placement(session: session, deniedClaim: nil)
            } else {
                fallback.append((session, claim))
            }
        }

        fallback.append(contentsOf: sessions.filter { $0.claim == nil }.map { ($0, nil) })
        fallback.sort { $0.session.startedAt < $1.session.startedAt }

        var overflow = [Placement]()
        for item in fallback {
            let placement = Placement(session: item.session, deniedClaim: item.denied)
            if let free = (1...slotCount).first(where: { occupants[$0] == nil }) {
                occupants[free] = placement
            } else {
                overflow.append(placement)
            }
        }

        let slots = (1...slotCount).map { Slot(number: $0, placement: occupants[$0]) }
        return Layout(slots: slots, overflow: overflow)
    }
}
