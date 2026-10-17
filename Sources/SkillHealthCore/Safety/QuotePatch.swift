import Foundation

/// A fix to one finding: its quote, found once in its file, replaced by new text. One definition
/// for both ends: the preview builds the change with it, and the apply asks whether the plan it was
/// handed is still exactly that change, so a plan can't carry any other edit to the file.
public enum QuotePatch {
    public static let longestReplacement = 2_000

    /// Whether `replacement` may stand in for the quote: the same rules for a line Claude proposes
    /// (`--with -`), a suggestion from a check, and the text a plan is about to write.
    public static func check(_ replacement: String, quote: String) throws(SkillHealthError) {
        guard !replacement.isEmpty else { throw .badReplacement("it's empty.") }
        guard replacement.unicodeScalars.count <= longestReplacement else { throw .badReplacement("it's longer than \(NumberText.count(longestReplacement)) characters.") }
        guard !HiddenText.contains(replacement) else { throw .badReplacement("it holds characters that don't show on screen.") }
        guard !replacement.unicodeScalars.elementsEqual(quote.unicodeScalars) else { throw .badReplacement("it's the same as the line it would replace.") }
    }

    /// The one place the quote is in the text: nowhere, or more than once, can't be fixed without guessing.
    static func locate(_ quote: String, in text: String, file: String) throws(SkillHealthError) -> Range<String.Index> {
        let found = text.ranges(of: quote)
        guard let first = found.first else { throw .quoteNotFound(file) }
        guard found.count == 1 else { throw .quoteAppearsMoreThanOnce(file, found.count) }
        return first
    }

    /// `text` with the quote's one place replaced.
    static func replacing(_ range: Range<String.Index>, in text: String, with replacement: String) -> String {
        String(text[..<range.lowerBound]) + replacement + String(text[range.upperBound...])
    }

    /// The text that stands in for the quote in `after`, if `after` is `before` with exactly the
    /// quote's one place replaced: the same scalars before it, the same after it. Nil for any other
    /// edit, wherever in the file, and for a quote that isn't there exactly once.
    public static func replacement(in before: String, quote: String, turnedInto after: String) -> String? {
        guard let range = try? locate(quote, in: before, file: "") else { return nil }
        let head = Array(before[..<range.lowerBound].unicodeScalars)
        let tail = Array(before[range.upperBound...].unicodeScalars)
        let scalars = Array(after.unicodeScalars)
        guard scalars.count >= head.count + tail.count,
              scalars.prefix(head.count).elementsEqual(head),
              scalars.suffix(tail.count).elementsEqual(tail) else { return nil }
        return String(String.UnicodeScalarView(scalars[head.count..<(scalars.count - tail.count)]))
    }
}
