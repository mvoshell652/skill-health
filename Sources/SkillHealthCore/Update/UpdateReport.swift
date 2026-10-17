import Foundation

/// What the tool's update command says after it ran, and whether that counts as a failure. Built
/// apart from the tool so the words and the exit status are tested together.
public struct UpdateReport: Sendable, Equatable {
    public var lines: [String]
    /// Set when the command must exit non-zero: a skill is partly updated, one was updated but its
    /// undo record couldn't be saved, or nothing was updated.
    public var failure: String?
}

extension UpdateOutcome {
    /// `refused` is the skills left alone before anything was written, with why; `backups` the
    /// folder the replaced copies went to. A skill that needs attention is named first, and is never
    /// among those /skill-health:undo is said to put back.
    public func report(refused: [String: String] = [:], backups: String) -> UpdateReport {
        func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(NumberText.count(n)) \(many)" }
        var lines: [String] = []
        for (skill, why) in damaged.sorted(by: { $0.key < $1.key }) { lines.append("\(skill) needs attention: \(why)") }
        let undoable = updated.filter { damaged[$0] == nil }
        if !updated.isEmpty {
            lines.append("Updated \(count(updated.count, "skill", "skills")): \(updated.joined(separator: ", ")).")
        }
        if !undoable.isEmpty {
            let which = undoable.count == updated.count ? "a skill" : undoable.joined(separator: ", ")
            lines.append("The old copies are in \(backups), and /skill-health:undo puts \(which) back.")
        }
        for (skill, why) in refused.merging(skipped, uniquingKeysWith: { first, _ in first }).sorted(by: { $0.key < $1.key }) {
            lines.append("\(skill) was left as it was: \(why)")
        }
        let partly = damaged.keys.filter { !updated.contains($0) }.sorted()
        let unrecorded = damaged.keys.filter { updated.contains($0) }.sorted()
        var failures: [String] = []
        if !partly.isEmpty {
            failures.append("\(partly.joined(separator: ", ")) \(partly.count == 1 ? "is" : "are") partly updated. The old files are in \(backups).")
        }
        if !unrecorded.isEmpty {
            failures.append("\(unrecorded.joined(separator: ", ")) \(unrecorded.count == 1 ? "was" : "were") updated, but Skill Health couldn't save everything it keeps for \(unrecorded.count == 1 ? "it" : "them"), as said above.")
        }
        if failures.isEmpty, updated.isEmpty { failures.append("Nothing was updated.") }
        return UpdateReport(lines: lines, failure: failures.isEmpty ? nil : failures.joined(separator: " "))
    }
}
