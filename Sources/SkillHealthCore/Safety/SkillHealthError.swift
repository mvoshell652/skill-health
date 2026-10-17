import Foundation

/// Every engine failure means nothing was written (the "Skill Health error:" contract, spec section 8).
public enum SkillHealthError: Error, Sendable, Equatable, LocalizedError {
    case diffNotShown
    case fileChangedSinceReview(URL)
    case notInsideSkills(URL)
    case linkedFile(URL)
    // Checking sources (M3). These say what happened in words a person can act on.
    case rateLimited(resetAt: Date?)
    case sourceNotFound(String)
    case sourceFailed(String, Int)
    case sourceTooLarge(String)
    case installNotFound(String, Date)
    case badSource(String)
    case offline(String)
    // Updating copies (flow G).
    case downloadMismatch(String)
    case unsafePath(String)
    case copyChangedSinceReview(String)
    // Deciding a finding (flow F).
    case noSuggestedText
    case quoteNotFound(String)
    case fileUnreadable(String)
    case decisionsUnreadable(String)
    case busy(String)
    case badReplacement(String)
    case changedSinceUpdate(String)
    case backupMissing(String)
    case planNotFound
    case planExpired
    case planUsed
    case quoteAppearsMoreThanOnce(String, Int)
    case nothingToUndo
    case changedSincePatch(String)
    case auditRejected(String)
    case findingsUnreadable(String)
    case planMismatch
    case planAltered
    case summaryTooLong
    case notRecorded(file: String, why: String)
    case changedNotRecorded(file: String, backup: String, why: String)
    case undoNotRecorded(skill: String, why: String)
    case undoChangedNotRecorded(skill: String, why: String)
    case undoRecordInvalid(String)
    case hiddenInPath(String)
    case cantLock(folder: String, why: String)
    // In-app audits (the person's own Anthropic API key).
    case apiRefused(String)
    case apiFailed(String)

    public var errorDescription: String? {
        switch self {
        case .diffNotShown: "Skill Health error: that change wasn't shown in full, so nothing was written."
        case .fileChangedSinceReview(let file): "Skill Health error: \(file.lastPathComponent) changed after you reviewed it. Nothing was written; review it again."
        case .notInsideSkills(let file): "Skill Health error: \(file.path(percentEncoded: false)) isn't inside the skills folder, so Skill Health won't write it."
        case .linkedFile(let file): "Skill Health error: \(file.lastPathComponent) is a link to another file. Edit it where it lives; Skill Health won't replace the link."
        default: "Skill Health error: " + plainDescription
        }
    }

    /// The message without the "Skill Health error:" prefix, for a line in the app. Times are local.
    public var plainDescription: String {
        switch self {
        case .rateLimited(let resetAt):
            // What happens next depends on who reads it (the app compares again by itself only when
            // Compare daily is on), so each says that part itself.
            if let resetAt {
                "GitHub allows 60 requests an hour without an account. It resets at \(resetAt.formatted(date: .omitted, time: .shortened))."
            } else {
                "GitHub allows 60 requests an hour without an account. It resets within the hour."
            }
        case .sourceNotFound(let repo): "\(repo) isn't on GitHub any more, or it's private."
        case .sourceFailed(let repo, let status): "GitHub couldn't answer for \(repo) (status \(status))."
        case .sourceTooLarge(let repo): "\(repo) is too large for GitHub to list in one answer."
        case .installNotFound(let repo, let at): "\(repo) has no version from before the install on \(at.formatted(date: .abbreviated, time: .omitted))."
        case .badSource(let repo): "\(repo) isn't a GitHub repository name Skill Health can check."
        case .offline(let message): "Skill Health couldn't reach GitHub: \(message)"
        case .downloadMismatch(let path): "\(path) didn't download as GitHub listed it, so nothing was written."
        case .unsafePath(let path): "\(path) would land outside its skill folder or through a link, so Skill Health won't write it."
        case .copyChangedSinceReview(let skill): "\(skill) changed after you reviewed it. Nothing in it was written; review it again."
        case .noSuggestedText: "No replacement was suggested for this line. Pass one with --with -."
        case .quoteNotFound(let file): "The line isn't in \(file) any more, so there's nothing to fix."
        case .fileUnreadable(let file): "Skill Health couldn't read \(file) as text, so it can't change it."
        case .busy(let holder): "\(holder.prefix(1).uppercased() + holder.dropFirst()) is saving Skill Health's files. Try again in a moment."
        case .changedSinceUpdate(let skill): "\(skill) has changed since it was updated, so putting the old copy back would lose those changes. Nothing was changed."
        case .backupMissing(let path): "The backup of \(path) is missing or doesn't match what was replaced, so Skill Health can't put it back. Nothing was changed."
        case .badReplacement(let why): "That replacement can't be used: \(why)"
        case .planNotFound: "That change isn't ready any more. Run the preview again."
        case .planExpired: "That change was prepared more than 15 minutes ago. Run the preview again, so what's written is what you see now."
        case .planUsed: "That change has already been written."
        case .decisionsUnreadable(let why): ProblemText.decisionsUnreadable(why)
        case .quoteAppearsMoreThanOnce(let file, let count): "The quoted text appears \(count) times in \(file), so Skill Health can't tell which one to change."
        case .nothingToUndo: "There's no fix to undo."
        case .changedSincePatch(let file): "\(file) changed after the fix, so undoing it would lose that change. Nothing was written."
        case .auditRejected(let problem): "The results of the check weren't saved: \(problem)."
        case .findingsUnreadable(let why): ProblemText.resultsUnreadable(why)
        case .planMismatch: "That plan doesn't match the change it describes, so nothing was written. Run the preview again."
        case .planAltered: "That plan was changed after the preview, so nothing was written. Run the preview again."
        case .summaryTooLong:
            "The text this change removes and adds is too long to show in full in Claude Code's approval prompt (\(NumberText.count(PendingPlan.summaryLimit)) characters), even with the unchanged parts of long lines left out, so Skill Health won't prepare it. Use a shorter replacement, or change it by hand."
        case .notRecorded(let file, let why): "Skill Health couldn't record the change, so it put \(file) back as it was. Nothing was changed: \(why)"
        case .changedNotRecorded(let file, let backup, let why):
            "\(file) was changed, but Skill Health couldn't record that or put the file back. The old file is in \(backup). \(why)"
        case .undoNotRecorded(let skill, let why):
            "Skill Health couldn't record putting \(skill) back, so it left \(skill) as the update made it. Nothing was changed: \(why)"
        case .undoChangedNotRecorded(let skill, let why):
            "\(skill) was put back as it was before the update, but Skill Health couldn't save that and couldn't undo it again, so its records are out of date. \(why)"
        case .undoRecordInvalid(let why): "Skill Health's record of that update doesn't match the skill it names (\(why)), so nothing was put back."
        case .hiddenInPath(let path): "\(HiddenText.revealed(path)) has characters in its name that don't show on screen, so Skill Health won't write it."
        case .cantLock(let folder, let why): "Skill Health can't write to \(folder): \(why). Check that folder's permissions, then try again."
        case .apiRefused(let message), .apiFailed(let message): message
        default: errorDescription.map { $0.replacing("Skill Health error: ", with: "") } ?? "\(self)"
        }
    }
}
