import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var layout = Layout.build(from: [])

    // Menu bar geometry. 9 slots at these values is ~194pt wide.
    // The bar is 24pt tall, so barHeight must leave a little breathing room or macOS
    // scales the image down — verify the rendered dot size after changing these.
    // 20pt is the ceiling before clipping; 18 keeps ~3pt of margin top and bottom.
    private let dotDiameter: CGFloat = 18
    private let dotSpacing: CGFloat = 4
    private let overflowGap: CGFloat = 8
    private let barHeight: CGFloat = 22

    /// Mid grey with alpha, so it reads against both light and dark menu bars.
    private let emptyColor = NSColor(white: 0.5, alpha: 0.55)

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
        layout = Layout.build(from: Registry.liveSessions())
        statusItem.button?.image = renderRow()
    }

    @objc private func toggleLaunchAtLogin() {
        if let failure = LoginItem.setEnabled(!LoginItem.isEnabled) {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = failure
            alert.runModal()
        }
    }

    // MARK: - Menu bar rendering

    /// Ambient states sit quietly: saturation pulled back, brightness lifted into pastel.
    /// `waiting` is deliberately excluded — it is the only state that means "act now", so
    /// it keeps its saturation and goes *darker* instead of paler, standing out against
    /// the pale dots around it by contrast rather than by hue alone.
    private func color(for state: SessionState) -> NSColor {
        switch state {
        case .running:  return adjust(.systemYellow, saturation: 0.55, brightness: 1.08)
        case .finished: return adjust(.systemGreen,  saturation: 0.55, brightness: 1.08)
        case .waiting:  return adjust(.systemRed,    saturation: 0.95, brightness: 0.78)
        }
    }

    /// System colours are tuned to grab attention, which makes them shout next to the
    /// monochrome glyphs in the menu bar. Deriving from them rather than hardcoding new
    /// values keeps each hue recognisable and appearance-aware.
    private func adjust(_ color: NSColor, saturation: CGFloat, brightness: CGFloat) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h,
                       saturation: min(1, s * saturation),
                       brightness: min(1, b * brightness),
                       alpha: a)
    }

    /// Picks the digit colour from the fill's luminance rather than fixing it.
    ///
    /// Pale fills need a dark glyph and dark fills need a light one — hardcoding either
    /// means a future palette change silently makes the numbers unreadable, which is
    /// exactly what happened when white digits were tried against the pastel fills.
    private func glyphColor(on fill: NSColor) -> NSColor {
        guard let rgb = fill.usingColorSpace(.deviceRGB) else { return NSColor(white: 0, alpha: 0.78) }
        let luma = 0.2126 * rgb.redComponent
                 + 0.7152 * rgb.greenComponent
                 + 0.0722 * rgb.blueComponent
        return luma > 0.55 ? NSColor(white: 0, alpha: 0.78) : NSColor(white: 1, alpha: 0.95)
    }

    private func renderRow() -> NSImage {
        let gridWidth = CGFloat(Layout.slotCount) * dotDiameter
            + CGFloat(Layout.slotCount - 1) * dotSpacing
        let overflowWidth = layout.overflow.isEmpty ? 0
            : overflowGap + CGFloat(layout.overflow.count) * (dotDiameter + dotSpacing) - dotSpacing

        let size = NSSize(width: gridWidth + overflowWidth, height: barHeight)

        let image = NSImage(size: size, flipped: false) { [weak self] _ in
            guard let self else { return true }
            NSGraphicsContext.current?.imageInterpolation = .high
            let y = (self.barHeight - self.dotDiameter) / 2
            var x: CGFloat = 0

            for slot in self.layout.slots {
                self.draw(state: slot.session?.state, number: slot.number, at: NSPoint(x: x, y: y))
                x += self.dotDiameter + self.dotSpacing
            }

            // Overflow dots carry no number: a number means "the [n] you can claim via
            // /rename", and positions past the grid are not claimable.
            if !self.layout.overflow.isEmpty {
                x += self.overflowGap - self.dotSpacing
                for placement in self.layout.overflow {
                    self.draw(state: placement.session.state, number: nil, at: NSPoint(x: x, y: y))
                    x += self.dotDiameter + self.dotSpacing
                }
            }
            return true
        }
        image.isTemplate = false   // keep our colors; do not tint as a template
        return image
    }

    /// A filled dot when occupied, a hollow ring when the slot is empty, with the slot
    /// number inside so the grid stays readable without opening the dropdown.
    private func draw(state: SessionState?, number: Int?, at origin: NSPoint) {
        let rect = NSRect(x: origin.x, y: origin.y, width: dotDiameter, height: dotDiameter)

        var fill: NSColor?
        if let state {
            let color = color(for: state)
            fill = color
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        } else {
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.2
            emptyColor.setStroke()
            ring.stroke()
        }

        guard let number else { return }
        let text = "\(number)"

        // Unreachable at the default slot count of 9, but kept so raising `slotCount`
        // does not push a two-digit number outside its circle.
        let fontSize = dotDiameter * (text.count > 1 ? 0.50 : 0.62)
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: fill.map(glyphColor(on:)) ?? emptyColor,
        ])

        let size = label.size()
        label.draw(at: NSPoint(x: rect.midX - size.width / 2,
                               y: rect.midY - size.height / 2))
    }

    // MARK: - Dropdown

    private func dotImage(for state: SessionState?) -> NSImage {
        let d: CGFloat = 10
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            if let state {
                self.color(for: state).setFill()
                NSBezierPath(ovalIn: rect).fill()
            } else {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.2
                NSColor(white: 0.5, alpha: 0.55).setStroke()
                ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

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
        item.image = dotImage(for: placement?.session.state)

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
