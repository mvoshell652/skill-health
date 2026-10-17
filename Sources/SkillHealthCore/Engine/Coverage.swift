import Foundation

/// When a check last covered a skill's files exactly as they are now, the one rule the app's menu and
/// the plugin's /skill-health:check share: a check saved here whose fingerprint matches the files now, or
/// Skill Health's shared list for these files, whichever is later. A skill that changed since, or whose
/// check was saved before fingerprints, has none.
public enum Coverage {
    /// How long a check holds for files that haven't changed: docs and tools move on even when a
    /// skill doesn't, so an unchanged skill is due again after this.
    public static let recheckAfter: TimeInterval = 90 * 24 * 60 * 60

    /// - Parameters:
    ///   - audit: findings.json as saved, before the shared list is joined in.
    ///   - sharedChecked: the shared list's check date for each skill whose files match one.
    ///   - trees: each skill's fingerprint now (`SharedCorrections.tree`).
    public static func covered(audit: FindingsFile, sharedChecked: [String: Date], trees: [String: String]) -> [String: Date] {
        var covered: [String: Date] = [:]
        for (name, tree) in trees {
            let own = audit.trees[name] == tree ? audit.audited[name] : nil
            if let latest = [own, sharedChecked[name]].compactMap(\.self).max() { covered[name] = latest }
        }
        return covered
    }

    /// When a covered skill is due again.
    public static func due(after covered: Date) -> Date { covered.addingTimeInterval(recheckAfter) }

    /// A skill is due for a check unless a check covered its files as they are now, in the last 90 days.
    public static func isDue(covered: Date?, now: Date) -> Bool {
        guard let covered else { return true }
        return due(after: covered) <= now
    }
}
