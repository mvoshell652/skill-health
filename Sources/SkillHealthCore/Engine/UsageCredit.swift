import Foundation

extension Skill {
    /// This skill with its loads counted, by exact name only. A namespaced load is a different
    /// skill: "anthropic-skills:supabase" is a plugin's own copy, and "playlist:db-ops" is a
    /// playlist group. Loading a group doesn't count as using its member skills (owner decision,
    /// 2026-10-03).
    public func crediting(_ loads: [String: Int]) -> Skill {
        var counted = self
        counted.usesLast90Days = loads[name] ?? 0
        return counted
    }
}
