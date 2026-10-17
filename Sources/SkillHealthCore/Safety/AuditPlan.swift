import Foundation

/// What an audit would cover and roughly what it costs. The audit itself runs in Claude Code
/// (/skill-health:audit, M5), where the person answers the scope and cost questions; this is the
/// estimate the app shows and writes into audit-plan.json for that skill to ask with.
public struct AuditPlan: Sendable, Hashable {
    public let skillNames: [String]
    public let estimatedTokens: Int

    /// Measured on the 27 Sep 2026 audit: about 180,000 tokens a skill, could be 30% either way.
    /// A flat average, kept for audit-plan.json (the old /skill-health:audit); `tokens(bytes:)` replaces it.
    public static let tokensPerSkill = 180_000

    /// What checking one skill costs, from its size. Measured on the 9 Oct 2026 check of 79 skills
    /// on Sonnet 5.5, in the units Claude Code reports for an agent (its context when it finished):
    /// an auditor came to about 35,000 tokens plus 640 a KB of the skill's files (r = 0.78), and a
    /// skill's one second look, needed by about half of skills, about 82,000 plus 200 a KB. So
    /// 75,000 plus 750 a KB, to the nearest thousand; could be 30% either way.
    public static func tokens(bytes: Int) -> Int {
        let estimate = 75_000 + 750 * Double(max(0, bytes)) / 1024
        return Int((estimate / 1000).rounded()) * 1000
    }

    public init(skillNames: [String]) {
        self.skillNames = skillNames
        self.estimatedTokens = skillNames.count * Self.tokensPerSkill
    }
}
