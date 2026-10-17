import Foundation

/// An audit's results, the same shape whichever way the audit ran: in Claude Code (the plugin's
/// save script) or in the app. Saved under the same rules as save-findings.sh, so the two can't
/// disagree: every field checked, only findings a second check kept, ids from skill, file and quote,
/// and only the audited skills' findings replaced.
public struct AuditResults: Sendable, Equatable {
    public struct Kept: Sendable, Equatable {
        public let skillName: String
        public let severity: Severity
        public let skillSays: String
        public let trueNow: String
        public let source: URL
        public var wrongSince: String?
        public let file: String?
        public let suggestedText: String?
        public let alternative: String?

        public init(skillName: String, severity: Severity, skillSays: String, trueNow: String, source: URL,
                    wrongSince: String? = nil, file: String? = nil, suggestedText: String? = nil, alternative: String? = nil) {
            self.skillName = skillName
            self.severity = severity
            self.skillSays = skillSays
            self.trueNow = trueNow
            self.source = source
            self.wrongSince = wrongSince
            self.file = file
            self.suggestedText = suggestedText
            self.alternative = alternative
        }
    }

    public let audited: [String]
    public let findings: [Kept]

    public init(audited: [String], findings: [Kept]) {
        self.audited = audited
        self.findings = findings
    }

    /// The same checks as save-findings.sh; the first problem found, in words, or nil. Each names
    /// the rule broken and keeps the JSON field's name, so whoever wrote the results can fix it.
    public var problem: String? {
        if audited.isEmpty { return "audited is empty: it must list the skill names checked" }
        if !audited.allSatisfy({ $0.wholeMatch(of: Self.name) != nil }) { return "audited has a name that \(Self.notAName)" }
        for (i, f) in findings.enumerated() {
            if f.skillName.wholeMatch(of: Self.name) == nil { return "finding \(i): skillName \(Self.notAName)" }
            if !audited.contains(f.skillName) { return "finding \(i): skillName \(f.skillName) isn't in audited" }
            if let field = Self.problem(of: f) { return "finding \(i): \(field)" }
        }
        return nil
    }

    static var name: Regex<Substring> { /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/ }

    // The words of each rule, shared with the tool's own checks and mirrored in save-findings.sh
    // (SaveFindingsTests compares the two).
    public static let notAName = "isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)"
    public static let hiddenWhy = "holds characters that don't show on screen"
    public static let severityRule = "severity must be breaks, deprecated, oldVersion or cosmetic"
    public static let keptRule = "keptBySecondCheck must be true: only findings the second look kept are saved"
    static let fileRule = "file must stay inside the skill folder: no leading / and no . or .. parts"

    /// Why a text field can't be saved, or nil. Lengths count code points, as jq's length does.
    /// `limit` is how it is written for people ("2,000").
    static func textProblem(_ field: String, _ value: String, max: Int, limit: String) -> String? {
        if value.isEmpty { return "\(field) is empty" }
        if value.unicodeScalars.count > max { return "\(field) is over \(limit) characters" }
        if HiddenText.contains(value) { return "\(field) \(hiddenWhy)" }
        return nil
    }

    /// One finding's first bad field, said in words that keep the field's JSON name, or nil.
    public static func problem(of f: Kept) -> String? {
        if f.skillName.wholeMatch(of: name) == nil { return "skillName \(notAName)" }
        if let why = textProblem("skillSays", f.skillSays, max: 2000, limit: "2,000") { return why }
        if let why = textProblem("trueNow", f.trueNow, max: 2000, limit: "2,000") { return why }
        if f.source.scheme != "https" || f.source.absoluteString.unicodeScalars.count > 508 { return "source must be an https link" }
        if let file = f.file {
            if let why = textProblem("file", file, max: 300, limit: "300") { return why }
            if file.hasPrefix("/") || file.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) {
                return fileRule
            }
        }
        if let suggested = f.suggestedText, let why = textProblem("suggestedText", suggested, max: 2000, limit: "2,000") { return why }
        if let alt = f.alternative, alt.wholeMatch(of: name) == nil { return "alternative \(notAName)" }
        if let since = f.wrongSince, !isWrongSince(since) {
            return "wrongSince must be undated, written:YYYY-MM-DD, installed:YYYY-MM-DD or since:YYYY-MM-DD"
        }
        return nil
    }

    /// Results already in findings.json that this version can't read would be dropped by a save,
    /// since saving writes back only what it read.
    public static func unreadableEntriesProblem(_ count: Int) -> String {
        let lost = count == 1 ? "1 instruction in the results of earlier checks couldn't be read, and saving would lose it"
            : "\(count.formatted()) instructions in the results of earlier checks couldn't be read, and saving would lose them"
        return lost + ". Move ~/.claude/skill-health/findings.json aside, then run /skill-health:check again"
    }

    /// How many findings and skills a save keeps: the same wrong line reported twice is one
    /// finding, and a skill listed twice is one skill.
    public var savedCounts: (findings: Int, skills: Int) {
        let ids = Set(findings.map { FindingID.make(skill: $0.skillName, file: $0.file ?? "SKILL.md", quote: $0.skillSays) })
        return (ids.count, Set(audited).count)
    }

    /// The label's shape, and a date that exists: 2026-13-45 and 2026-02-30 are refused, since
    /// one undecodable date would make the whole findings file unreadable.
    static func isWrongSince(_ label: String) -> Bool {
        if label == "undated" { return true }
        guard let match = label.wholeMatch(of: /^(written|installed|since):([0-9]{4}-[0-9]{2}-[0-9]{2})$/) else { return false }
        let day = String(match.output.2)
        let style = Date.ISO8601FormatStyle().year().month().day()
        return (try? style.parse(day)).map { $0.formatted(style) == day } ?? false
    }

    /// The findings file after this audit: earlier findings for other skills kept, these skills'
    /// replaced, and each audited skill dated, with the fingerprint of its files when known (a skill
    /// without one loses any earlier one, since it no longer describes what was checked).
    public func merged(into previous: FindingsFile, now: Date, trees: [String: String] = [:]) -> FindingsFile {
        let new = findings.map { f in
            Finding(id: FindingID.make(skill: f.skillName, file: f.file ?? "SKILL.md", quote: f.skillSays),
                    skillName: f.skillName, severity: f.severity, skillSays: f.skillSays, trueNow: f.trueNow,
                    source: f.source, foundOn: now, wrongSince: WrongSince(label: f.wrongSince), file: f.file,
                    suggestedText: f.suggestedText, alternative: f.alternative, keptBySecondCheck: true)
        }
        // The same line reported twice is one finding, as in the script.
        var seen = Set<Finding.ID>()
        let unique = new.filter { seen.insert($0.id).inserted }
        var file = previous
        file.findings = previous.findings.filter { !audited.contains($0.skillName) } + unique
        for skill in audited {
            file.audited[skill] = now
            file.trees[skill] = trees[skill]
        }
        return file
    }
}
