import Foundation

/// Characters that change what a reader (or Claude) gets without showing on screen. The same rule
/// as save-findings.sh's `hidden`, kept equal by a test:
///   - control characters other than tab and line ends (ESC can rewrite what a terminal shows),
///     and a carriage return that doesn't end a line;
///   - every default-ignorable and format character: zero-width spaces and joiners, the soft
///     hyphen, direction marks, overrides and isolates, invisible operators, the byte-order mark,
///     Hangul fillers, and Unicode tag characters, which can spell out a whole hidden sentence;
///   - the blank braille pattern, which looks like a space;
///   - a variation selector with no character of its own before it: at the start, after a space,
///     or after another selector. One selector after a character is ordinary text (the emoji form
///     of ⚠️, a variant of a CJK ideograph); a run of them can carry a hidden message, one byte each.
public enum HiddenText {
    static let ranges: [ClosedRange<UInt32>] = [
        0x0000...0x0008, 0x000B...0x000C, 0x000E...0x001F, 0x007F...0x009F,
        0x00AD...0x00AD, 0x034F...0x034F, 0x0600...0x0605, 0x061C...0x061C, 0x06DD...0x06DD, 0x070F...0x070F,
        0x0890...0x0891, 0x08E2...0x08E2, 0x115F...0x1160, 0x17B4...0x17B5, 0x180B...0x180F,
        0x200B...0x200F, 0x202A...0x202E, 0x2060...0x206F, 0x2800...0x2800, 0x3164...0x3164,
        0xFEFF...0xFEFF, 0xFFA0...0xFFA0, 0xFFF0...0xFFFB,
        0x110BD...0x110BD, 0x110CD...0x110CD, 0x13430...0x1343F, 0x1BCA0...0x1BCA3, 0x1D173...0x1D17A,
        0xE0000...0xE00FF, 0xE01F0...0xE0FFF,
    ]
    static let selectors: [ClosedRange<UInt32>] = [0xFE00...0xFE0F, 0xE0100...0xE01EF]

    static func isSelector(_ scalar: Unicode.Scalar) -> Bool { selectors.contains { $0.contains(scalar.value) } }

    /// Hidden whatever surrounds it.
    static func alwaysHidden(_ scalar: Unicode.Scalar) -> Bool { ranges.contains { $0.contains(scalar.value) } }

    /// Which of the text's scalars are hidden, in order.
    static func marks(_ scalars: [Unicode.Scalar]) -> [Bool] {
        scalars.indices.map { i in
            let scalar = scalars[i]
            if alwaysHidden(scalar) { return true }
            if scalar == "\r" { return i + 1 >= scalars.count || scalars[i + 1] != "\n" }
            guard isSelector(scalar) else { return false }
            guard i > 0 else { return true }
            let before = scalars[i - 1]
            return isSelector(before) || before.properties.isWhitespace || alwaysHidden(before)
        }
    }

    public static func contains(_ text: String) -> Bool {
        marks(Array(text.unicodeScalars)).contains(true)
    }

    /// The text with each hidden character shown as its code point, e.g. ⟨U+200B⟩, for diffs.
    public static func revealed(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let hidden = marks(scalars)
        guard hidden.contains(true) else { return text }
        var out = String.UnicodeScalarView()
        for (scalar, isHidden) in zip(scalars, hidden) {
            if isHidden {
                out.append(contentsOf: "⟨U+\(String(scalar.value, radix: 16, uppercase: true).leftPadded(to: 4))⟩".unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    public static func stripped(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        return String(String.UnicodeScalarView(zip(scalars, marks(scalars)).filter { !$0.1 }.map(\.0)))
    }
}

private extension String {
    func leftPadded(to width: Int) -> String { count >= width ? self : String(repeating: "0", count: width - count) + self }
}
