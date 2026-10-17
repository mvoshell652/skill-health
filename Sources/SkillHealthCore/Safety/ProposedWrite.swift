import Foundation

/// A change Skill Health wants to make to a skill file. It can't be applied directly:
/// the only way to a write is `approve(shownDiff:)`, which needs the exact diff the person saw.
public struct ProposedWrite: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let file: URL
    public let before: String
    public let after: String

    public init(id: UUID = UUID(), file: URL, before: String, after: String) {
        self.id = id
        self.file = file
        self.before = before
        self.after = after
    }

    /// Every removed and inserted line, with its line number, in order. Uses the standard
    /// library's Myers diff, so duplicate lines, deletions and reorders are never hidden. Lines are
    /// compared by their unicode scalars, not as Swift compares strings: String equality treats
    /// canonically equivalent text as the same (the Kelvin sign and K, a Greek question mark and ;),
    /// so a change from one to the other would never show, and would still be written.
    public var diff: String { render(condensed: false) }

    /// The same, with a long changed line cut around the change: the unchanged start and end of a
    /// line that is in both its removed and its inserted version are replaced by a note of how
    /// many characters were left out (the same text on both sides, so nothing that changes is
    /// hidden). What the person reads in a preview and in Claude Code's approval prompt, so a
    /// fix on a very long line fits the prompt.
    public var condensedDiff: String { render(condensed: true) }

    /// The unchanged characters kept on each side of the change in a long line.
    static let context = 60
    /// A stretch of unchanged characters is cut only when at least this many go: a note is about
    /// 30 characters, and a cut that saves nothing would only get in the way.
    static let smallestCut = 100

    /// Whether the change puts in a character that doesn't show on screen (HiddenText) that the
    /// lines it removes didn't have. A file that starts with a byte-order mark has one on its first
    /// line before and after; a change there adds nothing.
    public var addsHiddenCharacters: Bool {
        let lines = comparison
        func counts(_ texts: [Substring]) -> [UInt32: Int] {
            var found: [UInt32: Int] = [:]
            for text in texts {
                let scalars = Array(text.unicodeScalars)
                for (scalar, hidden) in zip(scalars, HiddenText.marks(scalars)) where hidden { found[scalar.value, default: 0] += 1 }
            }
            return found
        }
        let removed = counts(lines.removed.map { lines.old[$0] })
        return counts(lines.inserted.map { lines.new[$0] }).contains { removed[$0.key, default: 0] < $0.value }
    }

    /// The person approved after seeing `diff`. Refuses an empty diff and any diff that isn't this
    /// change's, compared scalar by scalar. (The tool's previews show `condensedDiff`, which leaves
    /// out only text that is the same before and after, and bind the approval to it themselves.)
    public func approve(shownDiff: String, at date: Date = .now) throws(SkillHealthError) -> ReviewedWrite {
        let diff = self.diff
        guard !diff.isEmpty, shownDiff.unicodeScalars.elementsEqual(diff.unicodeScalars) else { throw .diffNotShown }
        return ReviewedWrite(proposal: self, approvedAt: date)
    }

    // MARK: The comparison

    private struct Comparison {
        let old: [Substring]
        let new: [Substring]
        /// Offsets of the removed lines in `old` and the inserted lines in `new`, top to bottom.
        let removed: [Int]
        let inserted: [Int]

        /// A removed line and the inserted line that replaces it: within each run of changes with no
        /// unchanged line between, the first removed with the first inserted, and so on. A line with
        /// no partner (a pure addition or removal) is not here.
        var pairs: [(removed: Int, inserted: Int)] {
            let removedSet = Set(removed), insertedSet = Set(inserted)
            var pairs: [(Int, Int)] = []
            var i = 0, j = 0
            while i < old.count || j < new.count {
                guard removedSet.contains(i) || insertedSet.contains(j) else {
                    i += 1
                    j += 1
                    continue
                }
                var gone: [Int] = [], came: [Int] = []
                var moved = true
                while moved {
                    moved = false
                    while i < old.count, removedSet.contains(i) { gone.append(i); i += 1; moved = true }
                    while j < new.count, insertedSet.contains(j) { came.append(j); j += 1; moved = true }
                }
                pairs += zip(gone, came).map { ($0, $1) }
            }
            return pairs
        }
    }

    /// Any line end: Swift reads CRLF as one character, so splitting on "\n" alone would show
    /// a Windows-style file as a single changed line.
    private static func lines(_ text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    private var comparison: Comparison {
        let old = Self.lines(before), new = Self.lines(after)
        let changes = new.difference(from: old) { $0.unicodeScalars.elementsEqual($1.unicodeScalars) }
        var removed: [Int] = [], inserted: [Int] = []
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.append(offset)
            case .insert(let offset, _, _): inserted.append(offset)
            }
        }
        return Comparison(old: old, new: new, removed: removed.sorted(), inserted: inserted.sorted())
    }

    private func render(condensed: Bool) -> String {
        let lines = comparison
        var removedText = Dictionary(uniqueKeysWithValues: lines.removed.map { ($0, String(lines.old[$0])) })
        var insertedText = Dictionary(uniqueKeysWithValues: lines.inserted.map { ($0, String(lines.new[$0])) })
        if condensed {
            for pair in lines.pairs {
                let cut = Self.condensed(removedText[pair.removed] ?? "", insertedText[pair.inserted] ?? "")
                removedText[pair.removed] = cut.removed
                insertedText[pair.inserted] = cut.inserted
            }
        }
        // Removals (numbered in the old file) then insertions (numbered in the new), each top to bottom.
        return (lines.removed.map { "-\($0 + 1): \(removedText[$0] ?? "")" }
            + lines.inserted.map { "+\($0 + 1): \(insertedText[$0] ?? "")" }).joined(separator: "\n")
    }

    /// A replaced line with its unchanged start and end cut down to `context` scalars each, both
    /// versions cut the same way. Computed on scalars, the unit the file is compared in.
    static func condensed(_ removed: String, _ inserted: String) -> (removed: String, inserted: String) {
        let a = Array(removed.unicodeScalars), b = Array(inserted.unicodeScalars)
        let shorter = min(a.count, b.count)
        var head = 0
        while head < shorter, a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < shorter - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let cutHead = head - context >= smallestCut ? head - context : 0
        let cutTail = tail - context >= smallestCut ? tail - context : 0
        guard cutHead > 0 || cutTail > 0 else { return (removed, inserted) }
        func cut(_ scalars: [Unicode.Scalar]) -> String {
            var text = String.UnicodeScalarView()
            if cutHead > 0 { text.append(contentsOf: note(cutHead).unicodeScalars) }
            text.append(contentsOf: scalars[cutHead..<(scalars.count - cutTail)])
            if cutTail > 0 { text.append(contentsOf: note(cutTail).unicodeScalars) }
            return String(text)
        }
        return (cut(a), cut(b))
    }

    private static func note(_ count: Int) -> String { "⟨… \(NumberText.count(count)) unchanged characters …⟩" }
}
