import Foundation

/// Everything Skill Health knows at one moment, joined the way the app joins it: the skills with their
/// loads and copy states, the audit's findings plus the known corrections that match these exact
/// files, the person's decisions applied, and what can't be read said in words. The plugin's
/// command-line tool works from this, so it sees what the menu shows.
public struct Overview: Sendable {
    public let skills: [Skill]
    public let usage: UsageReport?
    public let usageProblem: String?
    /// The skills folder exists but couldn't be listed, so the skills above are none at all, not no skills.
    public let skillsProblem: String?
    /// Audit findings and matching known corrections, one list, with decisions applied.
    public let findings: FindingsFile
    public let decisions: DecisionsFile
    public let compare: CompareFile
    public let findingsProblem: String?
    /// findings.json as a whole couldn't be read (findingsProblem says why), as opposed to a few
    /// of its entries: nothing about what was checked can be said.
    public let findingsUnreadable: Bool
    /// How many entries of findings.json couldn't be read, while the file as a whole could.
    public let findingsUnreadableEntries: Int
    /// compare.json couldn't be read, so newer copies aren't known (it reads as never compared).
    public let compareProblem: String?
    public let decisionsProblem: String?
    /// When a check last covered each skill's files exactly as they are now: a check saved here whose
    /// fingerprint matches, or Skill Health's shared list for these files. A skill that changed since, or
    /// whose check predates fingerprints, has none.
    public let covered: [String: Date]

    /// When an unchanged skill is due for a check again. Nil when no check covers its files as they
    /// are now: it was never checked, or it changed since.
    public func recheckDue(_ name: String) -> Date? { covered[name].map(Coverage.due(after:)) }

    /// A check leaves this skill out: its files are the ones a check covered in the last 90 days.
    public func isUpToDate(_ name: String, now: Date = .now) -> Bool { !Coverage.isDue(covered: covered[name], now: now) }

    /// What makes any answer about findings or decisions untrue: the skills can't be listed, the
    /// results of earlier checks can't be read, or the person's decisions can't. Silence never
    /// means nothing to do.
    public var blockingProblem: String? {
        skillsProblem ?? (findingsUnreadable ? findingsProblem : nil) ?? decisionsProblem
    }

    /// What stops a check from being saved, so it is said before anything is spent on one: the
    /// results file can't be read, or has entries a save would drop (Engine.save refuses both).
    /// Unreadable decisions don't matter here: a check writes only findings.json.
    public var checkBlockingProblem: String? {
        if let skillsProblem { return skillsProblem }
        if findingsUnreadable { return findingsProblem }
        if findingsUnreadableEntries > 0 { return AuditResults.unreadableEntriesProblem(findingsUnreadableEntries) + "." }
        return nil
    }

    public var used: [Skill] { skills.filter(\.isUsed) }
    /// Open failing and deprecated findings in skills you use, most severe first.
    public var urgent: [Finding] { Urgency.findings(findings.findings, skills: skills) }

    public func skill(named name: String) -> Skill? { skills.first { $0.name == name } }
    public func finding(id: Finding.ID) -> Finding? { findings.findings.first { $0.id == id } }
    /// When the skill was last checked, by an audit or by a known correction for these exact files.
    public func checkedOn(_ name: String) -> Date? { findings.audited[name] }

    /// Failing and deprecated instructions the person set aside, or handed to another skill, that
    /// haven't come back: still wrong in the skill, just not open. In skills you use, or in the one
    /// skill named. Any "nothing to fix" has to say these are there.
    public func setAside(skill name: String? = nil, now: Date = .now) -> (failing: Int, deprecated: Int) {
        let usedNames = Set(used.map(\.name))
        var count = (failing: 0, deprecated: 0)
        for finding in findings.findings where finding.severity.isUrgent && !finding.isOpen(at: now) {
            guard name.map({ $0 == finding.skillName }) ?? usedNames.contains(finding.skillName) else { continue }
            switch finding.status {
            case .setAside, .usingAnotherSkill, .notForThisProject:
                if finding.severity == .breaks { count.failing += 1 } else { count.deprecated += 1 }
            case .open, .patched: break
            }
        }
        return count
    }

    /// Why an open finding still has an earlier decision on file: its set-aside date passed, its
    /// source changed the skill (a set-aside "until update"), or the fixed line came back. Nil when
    /// there is no earlier decision, or it still holds.
    public enum Lapse: String, Sendable {
        case expired, sourceChanged, lineCameBack
    }

    public func lapse(of finding: Finding, now: Date = .now) -> Lapse? {
        guard finding.isOpen(at: now), let decision = decisions[finding.id] else { return nil }
        switch decision.status {
        case .open: return nil
        case .patched: return .lineCameBack
        case .setAside(let until) where until <= now: return .expired
        case .setAside, .usingAnotherSkill, .notForThisProject:
            // Still open with time left on the decision: only the source changing the skill does that.
            let moved = decision.untilSourceChanges.flatMap { watched in
                compare.copies[finding.skillName].map { $0.sourceFingerprint != watched }
            }
            return moved == true ? .sourceChanged : nil
        }
    }

    /// What the last comparison couldn't reach, for the sources of skills you use.
    public var compareProblems: CompareProblems { CompareProblems(compare: compare, used: used) }
}

/// The sources the last comparison couldn't read, among those behind skills you use. A comparison
/// that failed knows nothing about newer copies, so no line may say there are none.
public struct CompareProblems: Sendable, Equatable {
    /// How many repositories the skills you use came from.
    public let sources: Int
    /// Why each one that failed couldn't be read, in words, by repository.
    public let problems: [String]

    public init(compare: CompareFile, used: [Skill]) {
        let repos = Set(used.compactMap { $0.origin?.repo })
        sources = repos.count
        problems = repos.sorted().compactMap { compare.sources[$0]?.problem }
    }

    /// How an offline failure begins (SkillHealthError.offline); a test keeps the two equal.
    static let offlinePrefix = "Skill Health couldn't reach GitHub"

    public var count: Int { problems.count }

    /// Said where a line would otherwise say there are no newer copies; nil when every source was read.
    public var sentence: String? {
        guard count > 0 else { return nil }
        if count == sources, problems.allSatisfy({ $0.hasPrefix(Self.offlinePrefix) }) {
            return "Skill Health couldn't reach GitHub at the last comparison, so newer copies aren't known."
        }
        return count == 1 ? "1 source couldn't be reached at the last comparison, so newer copies from it aren't known."
            : "\(count.formatted()) sources couldn't be reached at the last comparison, so newer copies from them aren't known."
    }
}

/// The join itself, one function for the app and the tool.
public enum FindingsJoin {
    /// An audit's own finding wins over a known correction with the same id (the same wrong line).
    /// A check of the person's own that covered a skill's files as they are now, on or after a known
    /// correction's date, replaces the known corrections for that skill: it is the later look at the
    /// same files, and its second look may have thrown the correction out.
    /// A patched finding comes back when its file says the wrong line again and no longer holds
    /// the fix; a set-aside "until the next update" comes back when the source's files change.
    /// - Parameter trees: each skill's fingerprint now (`SharedCorrections.tree`).
    public static func join(audit: FindingsFile, shared: [Finding], sharedChecked: [String: Date], trees: [String: String],
                            decisions: DecisionsFile, compare: CompareFile, skills: [Skill]) -> FindingsFile {
        var joined = audit
        let known = Set(joined.findings.map(\.id))
        joined.findings += shared.filter { correction in
            guard !known.contains(correction.id) else { return false }
            let skill = correction.skillName
            // Only a check saved with a fingerprint, of these exact files, counts (as in `Coverage`).
            let ownCheck = trees[skill].flatMap { now in audit.trees[skill] == now ? audit.audited[skill] : nil }
            return !(ownCheck.map { $0 >= correction.foundOn } ?? false)
        }
        joined.audited.merge(sharedChecked) { audit, shared in max(audit, shared) }
        let folders = Dictionary(skills.map { ($0.name, $0.folder) }, uniquingKeysWith: { first, _ in first })
        return joined.deciding(with: decisions, sourceFingerprints: compare.copies.mapValues(\.sourceFingerprint)) { finding in
            guard let patch = decisions[finding.id]?.patch, let folder = folders[finding.skillName],
                  let data = try? Data(contentsOf: folder.appending(path: finding.filePath)),
                  GitBlob.id(of: data) != patch.written, let text = String(data: data, encoding: .utf8) else { return false }
            return text.contains(finding.skillSays) && !(finding.suggestedText.map(text.contains) ?? false)
        }
    }
}

extension Engine {
    /// Reads everything and joins it. Usage comes from the cache when it's current, so this is fast
    /// after the first read; a usage read that fails is reported, and every skill counts as unused.
    public func overview(shared: SharedCorrections?) async -> Overview {
        let discovered: [Skill]
        var skillsProblem: String?
        do { discovered = try discoverSkills() } catch {
            discovered = []
            skillsProblem = ProblemText.skillsUnreadable(paths.skills.path(percentEncoded: false), ProblemText.reason(error))
        }
        var usage: UsageReport?
        var usageProblem: String?
        do { usage = try await readUsage() } catch { usageProblem = error.localizedDescription }
        let compare = loadCompare()
        let credited = discovered.map { $0.crediting(usage?.loads ?? [:]) }
        let inspected = await inspect(credited, compare: compare, shared: shared)
        let skills = credited.map { skill in
            var known = skill
            known.copy = inspected.states[skill.name]
            return known
        }
        var findingsProblem: String?
        var findingsUnreadable = false
        let audit: FindingsFile
        do { audit = try loadFindings() } catch {
            audit = FindingsFile()
            findingsUnreadable = true
            findingsProblem = ProblemText.resultsUnreadable(ProblemText.reason(error))
        }
        if audit.unreadable > 0 {
            findingsProblem = ProblemText.resultsPartlyUnreadable(audit.unreadable)
        }
        var decisionsProblem: String?
        let decisions: DecisionsFile
        do { decisions = try loadDecisions() } catch {
            decisions = DecisionsFile()
            decisionsProblem = error.plainDescription
        }
        let joined = FindingsJoin.join(audit: audit, shared: inspected.sharedFindings, sharedChecked: inspected.checked, trees: inspected.trees,
                                       decisions: decisions, compare: compare, skills: skills)
        let covered = Coverage.covered(audit: audit, sharedChecked: inspected.checked, trees: inspected.trees)
        return Overview(skills: skills, usage: usage, usageProblem: usageProblem, skillsProblem: skillsProblem, findings: joined, decisions: decisions,
                        compare: compare, findingsProblem: findingsProblem, findingsUnreadable: findingsUnreadable,
                        findingsUnreadableEntries: audit.unreadable, compareProblem: compareProblem(),
                        decisionsProblem: decisionsProblem, covered: covered)
    }
}
