import Foundation
import SkillHealthCore

/// What the menu and the icon are built from. Kept apart from the library's loops: this only reads.
extension Library {
    /// The menu bar menu and the icon's label, in words. Everything is decided in `MenuModel`.
    var menu: MenuModel {
        // Read so the menu is drawn again while a check shows as opened: its words are relative to now.
        _ = clock
        return MenuModel(menuInput())
    }

    /// Installed skills loaded in the last 90 days.
    var usedCount: Int { skills.count(where: \.isUsed) }

    /// Skills you use, most used first.
    private var usedSkills: [Skill] {
        skills.filter(\.isUsed).sorted { ($0.usesLast90Days, $1.name) > ($1.usesLast90Days, $0.name) }
    }

    /// The skills you use with a newer copy that's safe to take, most used first.
    var newerSkills: [MenuInput.Listed] {
        usedSkills.filter(\.isSafeUpdate).map { MenuInput.Listed(name: $0.name, loads: $0.usesLast90Days) }
    }

    /// When a check last covered each skill's files as they are now (`Coverage`, as /skill-health:check reads it).
    var covered: [String: Date] { Coverage.covered(audit: savedFindings, sharedChecked: sharedChecked, trees: trees) }

    /// The skills you use that are due for a check, most used first, and why. None while the results
    /// can't be read: nothing about what was checked is known then.
    func dueSkills(now: Date = .now) -> [MenuInput.Due] {
        guard !findingsUnreadable, !trees.isEmpty else { return [] }
        let covered = covered
        return usedSkills.compactMap { skill in
            guard Coverage.isDue(covered: covered[skill.name], now: now) else { return nil }
            let reason: MenuInput.Due.Reason
            if let date = covered[skill.name] {
                reason = .checkedLongAgo(date)
            } else if let checked = findingsFile.audited[skill.name] {
                // Changed since only when its check saved a fingerprint the files no longer match; a
                // check saved before fingerprints is just dated.
                reason = savedFindings.trees[skill.name] != nil ? .changedSince(checked) : .checkedLongAgo(checked)
            } else {
                reason = .neverChecked
            }
            return MenuInput.Due(name: skill.name, loads: skill.usesLast90Days, reason: reason)
        }
    }

    func menuInput(now: Date = .now) -> MenuInput {
        let load: MenuInput.Load = switch state {
        case .needsFolder: .needsFolder
        case .loading: .loading
        case .failed: .failed
        case .loaded: .loaded
        }
        let readUsage: MenuInput.Usage = switch usage {
        case .notRead, .reading: .reading
        case .failed: .failed
        case .read: .read
        }
        let checked = MenuInput.checkedUsed(skills: skills, audited: findingsFile.audited)
        return MenuInput(
            load: load, usage: readUsage, usageCoversWindow: usageReport?.coversWindow ?? false,
            usedCount: usedCount, checkedUsedCount: checked.count, oldestCheck: checked.oldest,
            skills: MenuInput.skillIssues(urgent: urgentFindings, skills: skills),
            setAsideFailing: MenuInput.setAsideFailing(in: findingsFile.findings, skills: skills, now: now),
            // An unreadable results file is said once by the menu itself ("couldn't read the results of
            // earlier checks", in the check group or, with none, a group of its own); the long wording
            // with the system's reason stays in Settings, not as a second header here.
            findingsUnreadable: findingsUnreadable,
            problems: [findingsUnreadable ? nil : findingsProblem, decisionsProblem].compactMap(\.self),
            newerCopies: safeUpdateCount, newer: newerSkills, due: dueSkills(now: now), plugin: pluginState, canOpenClaudeCode: canOpenClaudeCode, sampleMode: showsSamples,
            checkOpenedAt: checkOpenedAt, findingsChangedSinceCheck: findingsChangedSinceCheck, now: now)
    }
}
