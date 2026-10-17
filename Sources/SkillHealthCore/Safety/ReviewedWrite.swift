import Foundation

/// The only value `Engine.apply(_:)` accepts. Its initializer is internal to SkillHealthCore,
/// so the app can't construct one without going through `ProposedWrite.approve(shownDiff:)`.
public struct ReviewedWrite: Sendable, Hashable {
    public let proposal: ProposedWrite
    public let approvedAt: Date

    init(proposal: ProposedWrite, approvedAt: Date) {
        self.proposal = proposal
        self.approvedAt = approvedAt
    }
}
