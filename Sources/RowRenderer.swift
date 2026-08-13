import AppKit

/// Draws the row of dots. Separated from the status item so the exact same drawing can be
/// rendered at any scale — the menu bar uses 1x, `--export` uses a higher scale for docs.
///
/// Everything here is vector, so a larger scale is genuinely sharper rather than an
/// upscaled bitmap.
struct RowRenderer {

    // The bar is 24pt tall, so barHeight must leave a little breathing room or macOS
    // scales the image down. 20pt dots is the ceiling before clipping; 18 keeps ~3pt
    // of margin top and bottom. 9 slots at these values is ~194pt wide.
    var dotDiameter: CGFloat = 18
    var dotSpacing: CGFloat = 4
    var overflowGap: CGFloat = 8
    var barHeight: CGFloat = 22

    /// Mid grey with alpha, so it reads against both light and dark menu bars.
    let emptyColor = NSColor(white: 0.5, alpha: 0.55)

    // MARK: - Colour

    /// Ambient states sit quietly: saturation pulled back, brightness lifted into pastel.
    /// `waiting` is deliberately excluded — it is the only state that means "act now", so
    /// it keeps its saturation and goes *darker* instead of paler, standing out against
    /// the pale dots around it by contrast rather than by hue alone.
    func color(for state: SessionState) -> NSColor {
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

    // MARK: - Rendering

    func size(for layout: Layout) -> NSSize {
        let grid = CGFloat(Layout.slotCount) * dotDiameter
            + CGFloat(Layout.slotCount - 1) * dotSpacing
        let overflow = layout.overflow.isEmpty ? 0
            : overflowGap + CGFloat(layout.overflow.count) * (dotDiameter + dotSpacing) - dotSpacing
        return NSSize(width: grid + overflow, height: barHeight)
    }

    /// `background` paints behind the dots — nil for the menu bar, where the bar shows
    /// through, and an explicit colour for exported images that need their own ground.
    func image(for layout: Layout, scale: CGFloat = 1, background: NSColor? = nil) -> NSImage {
        let base = size(for: layout)
        let scaled = NSSize(width: base.width * scale, height: base.height * scale)

        let image = NSImage(size: scaled, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return true }
            context.imageInterpolation = .high
            context.cgContext.scaleBy(x: scale, y: scale)

            if let background {
                background.setFill()
                NSRect(origin: .zero, size: base).fill()
            }

            let y = (barHeight - dotDiameter) / 2
            var x: CGFloat = 0

            for slot in layout.slots {
                draw(state: slot.session?.state, number: slot.number, at: NSPoint(x: x, y: y))
                x += dotDiameter + dotSpacing
            }

            // Overflow dots carry no number: a number means "the [n] you can claim via
            // /rename", and positions past the grid are not claimable.
            if !layout.overflow.isEmpty {
                x += overflowGap - dotSpacing
                for placement in layout.overflow {
                    draw(state: placement.session.state, number: nil, at: NSPoint(x: x, y: y))
                    x += dotDiameter + dotSpacing
                }
            }
            return true
        }
        image.isTemplate = false   // keep our colors; do not tint as a template
        return image
    }

    /// A filled dot when occupied, a hollow ring when the slot is empty, with the slot
    /// number inside so the grid stays readable without opening the dropdown.
    func draw(state: SessionState?, number: Int?, at origin: NSPoint) {
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

    /// Small standalone dot used beside each dropdown row.
    func dotImage(for state: SessionState?) -> NSImage {
        let d: CGFloat = 10
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            if let state {
                color(for: state).setFill()
                NSBezierPath(ovalIn: rect).fill()
            } else {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.2
                emptyColor.setStroke()
                ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
