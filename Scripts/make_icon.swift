// Renders the app icon, Resources/AppIcon.icns: Skill Health's mark in white on a blue tile.
//   swift Scripts/make_icon.swift
// The mark is a Phosphor Icons glyph (MIT License, see NOTICE). Its SVG lives once, in
// Sources/SkillHealthApp/Features/Menu/PhosphorIcon.swift, which this script reads, so the app icon,
// the menu bar icon and the empty state's picture can't drift apart.
import AppKit

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = try String(contentsOf: root.appending(path: "Sources/SkillHealthApp/Features/Menu/PhosphorIcon.swift"), encoding: .utf8)
guard let open = source.range(of: "#\"\"\"\n"),
      let close = source.range(of: "\"\"\"#", range: open.upperBound..<source.endIndex) else {
    fatalError("Couldn't find the SVG in PhosphorIcon.swift")
}
let svg = source[open.upperBound..<close.lowerBound]
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: "currentColor", with: "#FFFFFF")
guard let glyph = NSImage(data: Data(svg.utf8)) else { fatalError("The SVG didn't load") }

let iconset = URL.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// One square image: the macOS icon grid's rounded rectangle (824 of 1024, inset 100), a top-down
/// gradient, and the glyph in white. Phosphor draws inside a margin of about 14 percent, so a glyph
/// box of 0.66 of the tile puts the page itself at about half the tile.
func render(_ side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(side) / 1024
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.52, blue: 0.96, alpha: 1),
               ending: NSColor(srgbRed: 0.13, green: 0.31, blue: 0.75, alpha: 1))!.draw(in: shape, angle: -90)
    let box = tile.width * 0.66
    glyph.draw(in: NSRect(x: tile.midX - box / 2, y: tile.midY - box / 2, width: box, height: box))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
