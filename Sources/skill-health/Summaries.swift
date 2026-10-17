import Foundation
import SkillHealthCore

// What Claude Code's approval prompt shows for each kind of plan. The preview builds the summary
// from what it will write; apply builds it again from the same data and refuses unless the two
// match, so the person approves what is written, not what a plan file says about it.
//
// Everything from a skill, a path or a repository goes through `shown`: a name with a character
// that doesn't show on screen is spelled out as its code point, so the prompt can't read one way
// and name another file.

extension Tool {
    /// Text from a skill folder, a listing or a record, as the person reads it in a prompt.
    static func shown(_ text: String) -> String { HiddenText.revealed(text) }

    static func fixSummary(skill: String, path: String, diff: String) -> String {
        "Fix \(shown(skill)), \(shown(path))\n\n\(shown(diff))"
    }

    static func undoFixSummary(skill: String, path: String, diff: String) -> String {
        "Undo the fix in \(shown(skill)), \(shown(path))\n\n\(shown(diff))"
    }

    /// What a change is by its blobs alone, as every apply derives it; the stored kind only when
    /// the blobs say nothing (such a change is refused at apply).
    private static func kind(_ change: PendingPlan.Update.Change) -> FileChange.Kind {
        FileChange.Kind(before: change.before, after: change.after) ?? change.kind
    }

    /// One line per file an undo touches. The words come from the file's blobs before and after
    /// (what the update left and what it replaced), not from the kind the record says.
    static func undoUpdateLines(_ manifest: UpdateManifest) -> [String] {
        manifest.files.map { file in
            let path = shown(file.path)
            switch FileChange.Kind(before: file.before, after: file.after) {
            case .added: return "  removes \(path) (the update added it)"
            case .changed: return "  puts back \(path)"
            case .removed: return "  restores \(path) (the update removed it)"
            case nil: return "  has no record of what the update did to \(path)"
            }
        }
    }

    static func undoUpdateSummary(_ manifest: UpdateManifest) -> String {
        "Undo the update of \(shown(manifest.skill)) (\(day(manifest.updatedAt))), in \(shown(manifest.folder))\n\n"
            + undoUpdateLines(manifest).joined(separator: "\n")
    }

    /// "python-env: 2 changed, 1 added (from owner/repo)".
    static func updateHead(_ skill: PendingPlan.Update.Skill) -> String {
        let kinds = Dictionary(grouping: skill.changes, by: { kind($0) })
        let counts = [FileChange.Kind.changed, .added, .removed].compactMap { kind in kinds[kind].map { "\($0.count) \(kind.rawValue)" } }
        return "\(shown(skill.skill)): \(counts.joined(separator: ", ")) (from \(shown(skill.repo)))"
    }

    static func updateSummary(_ skills: [PendingPlan.Update.Skill]) -> String {
        let source = skills.count == 1 ? "its source" : "their sources"
        return "Update \(plural(skills.count, "skill", "skills")) from \(source) (current files go to backups first):\n"
            + skills.map { "- \(updateHead($0)): " + $0.changes.map { shown($0.path) }.joined(separator: ", ") }.joined(separator: "\n")
    }

    /// A summary must fit the prompt whole: cutting it would leave part of the change unseen. Counted
    /// in unicode scalars, which is how the gate hook (jq) cuts what it shows.
    static func requireWhole(_ summary: String) throws(SkillHealthError) {
        guard summary.unicodeScalars.count <= PendingPlan.summaryLimit else { throw .summaryTooLong }
    }

    /// Refuses a plan whose summary isn't the one its own data gives.
    static func require(_ plan: PendingPlan, shows summary: String) throws(SkillHealthError) {
        guard PendingPlan.fitted(summary).unicodeScalars.elementsEqual(plan.summary.unicodeScalars) else { throw .planMismatch }
    }

    /// Two paths name the same file or folder (a trailing slash or a "." doesn't matter).
    static func samePath(_ a: String, _ b: URL) -> Bool {
        URL(filePath: a).standardizedFileURL.pathComponents == b.standardizedFileURL.pathComponents
    }

    /// A plan is spent once its change is written. If it can't be marked used and can't be deleted
    /// either, the change still stands, and the person hears the plan could be run again.
    func retire(_ plan: PendingPlan) {
        guard !plans.retire(plan) else { return }
        let file = plans.url(for: plan.id).path(percentEncoded: false)
        FileHandle.standardError.write(Data("skill-health: the change was written, but its plan \(plan.id.uuidString) couldn't be marked used or deleted, so it could be applied again. Delete \(file).\n".utf8))
    }
}
