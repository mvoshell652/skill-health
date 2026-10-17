import Foundation
import SkillHealthCore

/// What every command shares: the engine for the person's .claude folder, the known corrections
/// that ship beside the tool, the plan store, and how output is printed.
struct Tool: Sendable {
    let arguments: [String]
    let engine: Engine
    let paths: SkillHealthPaths
    let plans: PlanStore

    /// The plugin's version, kept equal to plugin/.claude-plugin/plugin.json by a test (ToolTests).
    static let version = "0.6.1"

    init(arguments: [String]) {
        self.arguments = arguments
        let home = ProcessInfo.processInfo.environment["SKILL_HEALTH_CLAUDE_HOME"].map { URL(filePath: $0) }
        paths = SkillHealthPaths(claudeHome: home ?? SkillHealthPaths.defaultClaudeHome)
        engine = Engine(paths: paths)
        plans = PlanStore(paths: paths)
    }

    // MARK: Arguments

    /// The arguments after the command (and subcommand, when `depth` is 2), without flags.
    func operands(after depth: Int) -> [String] {
        Array(arguments.dropFirst(depth)).filter { !$0.hasPrefix("--") }
    }

    func flag(_ name: String) -> Bool { arguments.contains("--\(name)") }

    var json: Bool { flag("json") }

    func findingID(_ text: String?) -> UUID {
        guard let text, let id = UUID(uuidString: text) else {
            Self.usageError("Give the finding's id, as `skill-health findings` lists it.")
        }
        return id
    }

    func planID(_ text: String?) -> UUID {
        guard let text, let id = UUID(uuidString: text) else {
            Self.usageError("Give the plan id the preview printed on its last line (Plan: …).")
        }
        return id
    }

    // MARK: Shared reading

    /// Known corrections: next to the tool in the plugin (bin/../data/corrections.json).
    var shared: SharedCorrections? { sharedRead.corrections }

    /// The known corrections, and why they couldn't be read. Without them a skill a known correction
    /// covers reads as clean, so the reason is said wherever an all-clear would be.
    var sharedRead: (corrections: SharedCorrections?, problem: String?) {
        let override = ProcessInfo.processInfo.environment["SKILL_HEALTH_CORRECTIONS"].map { URL(filePath: $0) }
        let beside = Bundle.main.executableURL?.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "data/corrections.json")
        guard let url = override ?? beside else { return (nil, nil) }
        let path = url.path(percentEncoded: false)
        guard let data = try? Data(contentsOf: url) else {
            return (nil, "Skill Health couldn't find its known corrections (\(path)), so a skill they cover reads as clean. Reinstall the plugin.")
        }
        do { return (try Self.decoder.decode(SharedCorrections.self, from: data), nil) } catch {
            return (nil, "Skill Health couldn't read its known corrections (\(path)), so a skill they cover reads as clean. \(ProblemText.reason(error))")
        }
    }

    func overview() async -> Overview { await engine.overview(shared: shared) }

    /// No folder means no Claude Code here, or a different one: say so instead of reporting nothing.
    func requireSkillsFolder() {
        guard FileManager.default.fileExists(atPath: paths.skills.path(percentEncoded: false)) else {
            Self.fail("There's no skills folder at \(paths.skills.path(percentEncoded: false)), so there's nothing to look at.")
        }
    }

    // MARK: Output

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        // Shared sentences begin "Skill Health couldn't…" for the app; after this prefix that would read
        // "skill-health: Skill Health couldn't…".
        let said = message.hasPrefix("Skill Health ") ? String(message.dropFirst("Skill Health ".count)) : message
        FileHandle.standardError.write(Data("skill-health: \(said)\n".utf8))
        exit(code)
    }

    /// "No skills used in the last 90 days", or, when Claude Code has kept sessions for less time
    /// than that, as far back as it has: nothing earlier can be said.
    static func noneUsedLine(_ usage: UsageReport?) -> String {
        guard let usage, let since = usage.completeSince, !usage.coversWindow else { return "No skills used in the last 90 days" }
        return "No skills used since \(UsageReport.day(since)), as far back as Claude Code has kept sessions"
    }

    /// A comparison GitHub's limit stopped. The stop says when the limit resets, which is untrue a
    /// day later, so an old stop is said as one that can be finished now.
    static func pausedLine(_ compare: CompareFile, now: Date = .now) -> String? {
        guard let stopped = compare.stopped else { return nil }
        if let at = compare.checkedAt, now.timeIntervalSince(at) > 60 * 60 {
            return "The last comparison stopped at GitHub's hourly limit, which has reset since. Run skill-health compare to finish."
        }
        return "\(stopped) Run skill-health compare again after that to finish."
    }

    static func usageError(_ message: String) -> Never { fail(message, code: 2) }

    func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { Self.fail("couldn't write the JSON output.") }
        print(String(decoding: data, as: UTF8.self))
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Words, as the person reads them

    /// A moment, as the person's own calendar has it.
    /// In English whatever the Mac's region: these sentences are English, as the app's are.
    static let english = Locale(identifier: "en_US")

    static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(english))
    }

    /// A date Skill Health stored without a time (a shipped correction's day, a known check) is midnight
    /// UTC and is shown as that day; anything else is a moment, in the person's own calendar.
    static func dayOf(_ date: Date) -> String {
        date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0 ? calendarDay(date) : day(date)
    }

    /// A day-only date ("wrong since 2026-02-18"), stored as midnight UTC: shown in UTC, so it
    /// doesn't move a day earlier west of UTC.
    static func calendarDay(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(english)
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }

    /// "3 hours ago", "yesterday"; "just now" for the last moments and for a time ahead of this
    /// Mac's clock (it reads "in 5 hours" otherwise).
    static func ago(_ date: Date, now: Date = .now) -> String {
        guard now.timeIntervalSince(date) >= 45 else { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(english))
    }

    static func severityWord(_ severity: Severity) -> String {
        switch severity {
        case .breaks: "failing"
        case .deprecated: "deprecated"
        case .oldVersion: "old version"
        case .cosmetic: "cosmetic"
        }
    }

    static func wrongSince(_ value: WrongSince) -> String {
        switch value {
        case .written(let on): "Wrong since it was written (\(calendarDay(on)))"
        case .since(let date): "Wrong since \(calendarDay(date))"
        case .installed(let on): "Already wrong when installed (\(calendarDay(on)))"
        case .undated: "When it became wrong isn't dated"
        }
    }

    static func provenance(_ finding: Finding) -> String {
        if let from = finding.sharedFrom {
            return "Known correction, first found in \(from) on \(dayOf(finding.foundOn))"
        }
        let kept = finding.keptBySecondCheck == true ? ", kept after a second look tried to disprove it" : ""
        return "Found by a check on \(day(finding.foundOn))\(kept)"
    }

    /// "1 failing", "2 deprecated", "1 failing, 2 deprecated".
    static func counts(failing: Int, deprecated: Int) -> String {
        [failing > 0 ? "\(failing) failing" : nil, deprecated > 0 ? "\(deprecated) deprecated" : nil]
            .compactMap(\.self).joined(separator: ", ")
    }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count.formatted()) \(many)"
    }

    /// "4 of at least 79 skills you use checked."; with none used there is nothing to count.
    static func checkedLine(checked: Int, used: Int, lowerBound: Bool) -> String {
        guard used > 0 else { return "No skills used in the last 90 days." }
        return "\(checked.formatted()) of \(lowerBound ? "at least " : "")\(plural(used, "skill", "skills")) you use checked."
    }

    /// "74 skills you use haven't been checked yet." An unchecked count taken from a used count that
    /// is a lower bound is one too.
    static func uncheckedLine(_ unchecked: Int, lowerBound: Bool) -> String {
        let count = lowerBound ? "At least \(unchecked.formatted())" : unchecked.formatted()
        return "\(count) \(unchecked == 1 ? "skill you use hasn't" : "skills you use haven't") been checked yet."
    }

    /// "2 failing instructions are set aside; /skill-health:undo lists them." Nil when none are.
    static func setAsideLine(failing: Int, deprecated: Int) -> String? {
        guard failing + deprecated > 0 else { return nil }
        let what: String
        switch (failing, deprecated) {
        case (_, 0): what = "\(plural(failing, "failing instruction", "failing instructions")) \(failing == 1 ? "is" : "are")"
        case (0, _): what = "\(plural(deprecated, "deprecated instruction", "deprecated instructions")) \(deprecated == 1 ? "is" : "are")"
        default: what = "\(plural(failing, "failing instruction", "failing instructions")) and \(deprecated.formatted()) deprecated are"
        }
        return "\(what) set aside; /skill-health:undo lists them."
    }

    /// Shown in place of characters that change what Claude reads without showing.
    static func revealed(_ diff: String) -> (text: String, hidden: Bool) {
        (HiddenText.revealed(diff), HiddenText.contains(diff))
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Engine messages start "Skill Health error:" for the app; the tool already prefixes "skill-health:".
    var droppingErrorPrefix: String { hasPrefix("Skill Health error: ") ? String(dropFirst("Skill Health error: ".count)) : self }
}
