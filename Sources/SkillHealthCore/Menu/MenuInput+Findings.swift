import Foundation

/// How the menu's counts are drawn from what Skill Health knows. Written once, here, so the icon, the menu
/// and the session note count the same things the same way.
extension MenuInput {
    /// Skills you use with an open failing or deprecated instruction, and how many of each. `urgent`
    /// is what `Urgency` returns: open, failing or deprecated, in skills used in the last 90 days.
    public static func skillIssues(urgent findings: [Finding], skills: [Skill]) -> [SkillIssues] {
        let loads = Dictionary(skills.map { ($0.name, $0.usesLast90Days) }, uniquingKeysWith: { first, _ in first })
        var bySkill: [String: SkillIssues] = [:]
        for finding in findings where finding.severity.isUrgent {
            var row = bySkill[finding.skillName]
                ?? SkillIssues(name: finding.skillName, failing: 0, deprecated: 0, loads: loads[finding.skillName] ?? 0)
            if finding.severity == .breaks { row.failing += 1 } else { row.deprecated += 1 }
            bySkill[finding.skillName] = row
        }
        return bySkill.values.sorted { $0.name < $1.name }
    }

    /// Failing instructions in skills you use that the person set aside and that haven't come back.
    /// They are still failing, so no line may say "none failing" while there are any. Only failing
    /// counts, not deprecated; a fixed or replaced one is closed, not set aside.
    public static func setAsideFailing(in findings: [Finding], skills: [Skill], now: Date = .now) -> Int {
        let used = Set(skills.filter(\.isUsed).map(\.name))
        return findings.count { finding in
            guard finding.severity == .breaks, used.contains(finding.skillName), !finding.isOpen(at: now) else { return false }
            switch finding.status {
            case .setAside, .notForThisProject: return true
            case .open, .patched, .usingAnotherSkill: return false
            }
        }
    }

    /// How many skills you use have been checked (by a check or a shared correction), and the oldest
    /// of those checks: how far back "all checked" reaches.
    public static func checkedUsed(skills: [Skill], audited: [String: Date]) -> (count: Int, oldest: Date?) {
        let dates = skills.filter(\.isUsed).compactMap { audited[$0.name] }
        return (dates.count, dates.min())
    }
}
