import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let renderer = RowRenderer()
    private var timer: Timer?
    private var layout = Layout.build(from: [])

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Data

    private func refresh() {
        layout = Demo.isEnabled ? Demo.layout() : Layout.build(from: Registry.liveSessions())
        statusItem.button?.image = renderer.image(for: layout)
    }

    @objc private func toggleLaunchAtLogin() {
        if let failure = LoginItem.setEnabled(!LoginItem.isEnabled) {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = failure
            alert.runModal()
        }
    }

    // MARK: - Dropdown

    private func label(for state: SessionState) -> String {
        switch state {
        case .running:  return "running"
        case .waiting:  return "waiting"
        case .finished: return "idle"
        }
    }

    private func age(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()

        for slot in layout.slots {
            menu.addItem(row(number: "\(slot.number)", placement: slot.placement))
        }

        if !layout.overflow.isEmpty {
            menu.addItem(.separator())
            for placement in layout.overflow {
                menu.addItem(row(number: "+", placement: placement))
            }
        }

        menu.addItem(.separator())

        let sessions = layout.slots.compactMap(\.session) + layout.overflow.map(\.session)
        let total = sessions.count
        let running = sessions.filter { $0.state == .running }.count
        let summary = NSMenuItem(
            title: "\(total) session\(total == 1 ? "" : "s") · \(running) running",
            action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)

        let launch = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let credit = NSMenuItem(title: "Semaphoz \(version) · by bbonfim", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        menu.addItem(credit)

        menu.addItem(NSMenuItem(
            title: "Quit Semaphoz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func row(number: String, placement: Layout.Placement?) -> NSMenuItem {
        let item = NSMenuItem()
        item.image = renderer.dotImage(for: placement?.session.state)

        guard let placement else {
            item.attributedTitle = NSAttributedString(
                string: "\(number)   —",
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor,
                             .font: NSFont.menuFont(ofSize: 0)])
            item.isEnabled = false
            return item
        }

        let session = placement.session
        var detail = "  ·  \(label(for: session.state))  ·  \(age(session.idleFor))"

        // Explain a refused claim inline, so an unexpected position is self-diagnosing
        // rather than looking like a bug.
        if let denied = placement.deniedClaim {
            let reason = (1...Layout.slotCount).contains(denied) ? "taken" : "out of range"
            detail += "  ·  [\(denied)] \(reason)"
        }

        let text = NSMutableAttributedString(
            string: "\(number)   \(session.displayName)",
            attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(
            string: detail,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.menuFont(ofSize: 0)]))

        item.attributedTitle = text
        item.toolTip = "\(session.cwd)\npid \(session.pid)"
        return item
    }
}
