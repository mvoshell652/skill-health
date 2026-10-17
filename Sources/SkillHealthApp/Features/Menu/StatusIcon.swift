import AppKit
import SwiftUI

/// The menu bar icon: Skill Health's mark (`PhosphorIcon`), a page being checked. When something is
/// failing or deprecated a dot is cut into the corner: menu bar images are templates, so the state
/// is a change of shape, never of color. The label says the same in words, from `MenuModel`.
struct StatusIcon: View {
    let showsDot: Bool
    let label: String

    var body: some View {
        Image(nsImage: MenuBarSymbol.image(badged: showsDot, label: label))
            .accessibilityLabel(label)
    }
}

enum MenuBarSymbol {
    /// The glyph's box. Phosphor leaves a margin around the artwork, so 22 points shows a page
    /// about 16 points wide and 19 tall, in line with the system's own menu bar icons.
    static let pointSize: CGFloat = 22

    /// One template image either way, so the menu bar tints it like every other icon.
    static func image(badged: Bool, label: String) -> NSImage {
        let symbol = PhosphorIcon.image(side: pointSize)
        symbol.accessibilityDescription = label
        guard badged else {
            symbol.isTemplate = true
            return symbol
        }
        // A ring of clear space around a solid dot in the top-right corner, so the dot stays
        // distinct from the strokes it overlaps.
        let canvas = symbol.size
        let dot: CGFloat = 6.7
        let image = NSImage(size: canvas, flipped: false) { _ in
            symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            let center = NSPoint(x: canvas.width - dot / 2, y: canvas.height - dot / 2)
            let gap: CGFloat = 1.6
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: center.x - dot / 2 - gap, y: center.y - dot / 2 - gap,
                                        width: dot + 2 * gap, height: dot + 2 * gap)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }
}

#Preview {
    HStack {
        StatusIcon(showsDot: false, label: "Skill Health")
        StatusIcon(showsDot: true, label: "Skill Health, 3 failing instructions, 4 deprecated")
    }
    .padding()
}
