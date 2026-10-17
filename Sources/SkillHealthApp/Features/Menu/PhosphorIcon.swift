import AppKit

/// Skill Health's mark: the "file-magnifying-glass" glyph of Phosphor Icons (https://phosphoricons.com),
/// bold weight, from the core set at v2.0.8. A page being checked. It is the app icon, the menu bar
/// icon and the empty state's picture, so the three always match.
///
/// Phosphor Icons are MIT licensed, Copyright (c) 2023 Phosphor Icons; the license text is in NOTICE.
/// Scripts/make_icon.swift reads the SVG below to draw Resources/AppIcon.icns, so there is one copy.
enum PhosphorIcon {
    /// The SVG exactly as Phosphor publishes it. Its fill is `currentColor`; `image` sets it.
    static let fileMagnifyingGlassBold = #"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216.49,79.52l-56-56A12,12,0,0,0,152,20H56A20,20,0,0,0,36,40V216a20,20,0,0,0,20,20H200a20,20,0,0,0,20-20V88A12,12,0,0,0,216.49,79.52ZM183,80H160V57ZM60,212V44h76V92a12,12,0,0,0,12,12h48V212Zm96.48-48.49a36,36,0,1,0-17,17l12,12a12,12,0,0,0,17-17ZM112,148a12,12,0,1,1,12,12A12,12,0,0,1,112,148Z"/></svg>
    """#

    /// The glyph as a square image `side` points wide. The artwork sits inside a margin of about
    /// 14 percent, as Phosphor draws it, so the visible page is about 72 percent of `side`.
    /// `color` is a CSS color: "#000000" for a template image, "#FFFFFF" on the icon's tile.
    static func image(side: CGFloat, color: String = "#000000") -> NSImage {
        let markup = fileMagnifyingGlassBold.replacing("currentColor", with: color)
        guard let image = NSImage(data: Data(markup.utf8)) else { return NSImage(size: NSSize(width: side, height: side)) }
        image.size = NSSize(width: side, height: side)
        return image
    }
}
