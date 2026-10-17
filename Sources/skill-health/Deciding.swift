import AppKit
import Foundation
import SkillHealthCore

// /skill-health:fix's commands: fix a line (preview, then apply after Claude Code asks the person),
// decide (set aside, use another skill, reopen) and draft an issue for the author.

extension Tool {
    /// The finding, which must exist. Without the results of earlier checks or the decisions, "no
    /// finding with that id" could be untrue, so an unreadable file is said first.
    func openFinding(_ id: UUID, in view: Overview) -> (Finding, Skill) {
        if let problem = view.blockingProblem { Self.fail(problem) }
        guard let finding = view.finding(id: id) else {
            Self.fail("There's no finding with that id. Run skill-health findings to see the current ones.")
        }
        guard let skill = view.skill(named: finding.skillName) else {
            Self.fail("\(Self.shown(finding.skillName)) isn't installed any more, so there's nothing to change.")
        }
        return (finding, skill)
    }

    /// Deciding a finding twice is a mistake to say out loud.
    static let alreadyDecided = "That instruction is already decided. skill-health undo list shows what can be undone or reopened."

    // MARK: fix

    func fix() async throws {
        switch arguments.dropFirst().first {
        case "preview": try await fixPreview()
        case "apply": try await fixApply()
        default: Self.usageError("skill-health fix preview <finding> [--with -] | skill-health fix apply <plan>")
        }
    }

    func fixPreview() async throws {
        let id = findingID(operands(after: 2).first)
        let view = await overview()
        let (finding, skill) = openFinding(id, in: view)
        guard finding.isOpen() else { Self.fail(Self.alreadyDecided) }
        var replacement: String?
        if flag("with") {
            let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            // A heredoc ends with a newline the person didn't write as part of the line.
            replacement = text.hasSuffix("\n") && !finding.skillSays.hasSuffix("\n") ? String(text.dropLast()) : text
        }
        let proposal = try await engine.proposePatch(for: finding, in: skill, replacement: replacement)
        let path = proposal.file.path(percentEncoded: false)
        // A very long line is shown cut around the change; apply builds the same text again.
        let diff = proposal.condensedDiff
        let summary = Self.fixSummary(skill: skill.name, path: path, diff: diff)
        try Self.requireWhole(summary)
        let plan = PendingPlan(kind: .fix, summary: summary,
                               fix: .init(finding: finding.id, skill: skill.name, file: path,
                                          before: GitBlob.id(of: Data(proposal.before.utf8)), after: proposal.after))
        try plans.save(plan)
        print("Change to \(Self.shown(path)):")
        print("")
        print(Self.shown(diff))
        if proposal.addsHiddenCharacters {
            print("")
            print("This change holds characters that don't show on screen, marked ⟨U+…⟩ above. They change what Claude reads.")
        }
        print("")
        print("Plan: \(plan.id.uuidString)")
    }

    func fixApply() async throws {
        let plan = try plans.ready(planID(operands(after: 2).first), kind: .fix)
        guard let fix = plan.fix else { throw SkillHealthError.planNotFound }
        let view = await overview()
        let (finding, skill) = openFinding(fix.finding, in: view)
        // Still open: a line fixed, set aside or handed to another skill since the preview is decided.
        guard finding.isOpen() else { Self.fail(Self.alreadyDecided) }
        // The plan names the finding's own skill and file.
        guard fix.skill == skill.name, Self.samePath(fix.file, try Engine.inside(skill.folder, finding.filePath)) else {
            throw SkillHealthError.planMismatch
        }
        let file = URL(filePath: fix.file)
        guard let data = try? Data(contentsOf: file), GitBlob.id(of: data) == fix.before, let before = SkillText.exact(data) else {
            Self.fail("\(file.lastPathComponent) changed after the preview, so nothing was written. Run the preview again.")
        }
        // The plan's text is this file with the finding's quote replaced and nothing else, and the
        // replacement is one the preview could have made: the same rules as `--with`.
        guard let replacement = QuotePatch.replacement(in: before, quote: finding.skillSays, turnedInto: fix.after) else {
            throw SkillHealthError.planMismatch
        }
        try QuotePatch.check(replacement, quote: finding.skillSays)
        let proposal = ProposedWrite(file: file, before: before, after: fix.after)
        // What Claude Code's prompt showed is rebuilt from what is about to be written.
        let summary = Self.fixSummary(skill: fix.skill, path: fix.file, diff: proposal.condensedDiff)
        try Self.requireWhole(summary)
        try Self.require(plan, shows: summary)
        let reviewed = try proposal.approve(shownDiff: proposal.diff)
        let decision = try await engine.patch(reviewed, finding: finding)
        retire(plan)
        print("Written to \(Self.shown(fix.skill)). Claude reads the new line the next time the skill loads.")
        if let backup = decision.patch?.backup { print("The old file is in \(backup). /skill-health:undo puts it back.") }
    }

    // MARK: decide

    func decide() async throws {
        let rest = operands(after: 1)
        let id = findingID(rest.first)
        let view = await overview()
        let (finding, _) = openFinding(id, in: view)
        let existing = view.decisions[finding.id]
        let now = Date.now
        switch rest.dropFirst().first {
        case "set-aside":
            guard finding.isOpen() else { Self.fail("That instruction is already decided. Reopen it first: skill-health decide \(id.uuidString) reopen") }
            let choice = rest.dropFirst(2).first
            var watch: String?
            let until: Date
            switch choice {
            case "30": until = now.addingTimeInterval(30 * 86_400)
            case "90": until = now.addingTimeInterval(90 * 86_400)
            case "until-update":
                guard let copy = view.compare.copies[finding.skillName] else {
                    Self.fail("There's no record of where \(Self.shown(finding.skillName)) came from, so Skill Health can't watch for an update. Choose 30 or 90 days.")
                }
                watch = copy.sourceFingerprint
                until = now.addingTimeInterval(FindingStatus.longestSetAside)
            default: Self.usageError("Set aside for 30 or 90 days, or until-update.")
            }
            let status = FindingStatus.cappedSetAside(until: until, now: now)
            try await engine.record(Decision(status: status, decidedAt: now, untilSourceChanges: watch, reportedAt: existing?.reportedAt), for: finding.id)
            guard case .setAside(let date) = status else { return }
            print(watch == nil ? "Set aside until \(Self.day(date))."
                  : "Set aside until its source changes \(Self.shown(finding.skillName)), or until \(Self.day(date)), whichever comes first.")
        case "another":
            guard finding.isOpen() else { Self.fail("That instruction is already decided. Reopen it first: skill-health decide \(id.uuidString) reopen") }
            guard let other = rest.dropFirst(2).first, view.skill(named: other) != nil, other != finding.skillName else {
                Self.fail("Name another installed skill that covers this instead.")
            }
            try await engine.record(Decision(status: .usingAnotherSkill(name: other), decidedAt: now, reportedAt: existing?.reportedAt), for: finding.id)
            print("Using \(Self.shown(other)) instead. The finding closes, and \(Self.shown(finding.skillName)) stays as it is.")
        case "reopen":
            if case .patched = existing?.status {
                Self.fail("That line was fixed. To put it back, undo the fix: /skill-health:undo \(Self.shown(finding.skillName))")
            }
            guard existing != nil, existing?.status != .open else { Self.fail("That instruction is already open.") }
            try await engine.record(Decision(status: .open, decidedAt: now, reportedAt: existing?.reportedAt), for: finding.id)
            print("Reopened. \(Self.shown(finding.skillName))'s instruction is back in the list to go through.")
        default:
            Self.usageError("skill-health decide <finding> set-aside 30|90|until-update | another <skill> | reopen")
        }
    }

    // MARK: issue

    func issue() async throws {
        let id = findingID(operands(after: 1).first)
        let view = await overview()
        let (finding, skill) = openFinding(id, in: view)
        guard let repo = skill.origin?.repo, GitHubSource.isValidRepo(repo) else {
            Self.fail("\(Self.shown(skill.name)) has no record of a GitHub repository it came from, so there's no author to write to.")
        }
        var draft = IssueDraft(finding: finding)
        guard var url = draft.newIssueURL(repo: repo) else { Self.fail("\(Self.shown(repo)) isn't a GitHub repository Skill Health can open.") }
        var copied = false
        // GitHub refuses very long new-issue links; the full text goes on the clipboard instead.
        if url.absoluteString.count > 7_000 {
            let full = draft.body
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            copied = pasteboard.setString("\(draft.title)\n\n\(full)", forType: .string)
            draft.body = String(full.prefix(2_000)) + "\n\n(The rest is on your clipboard.)"
            url = draft.newIssueURL(repo: repo) ?? url
        }
        print("Title: \(draft.title)")
        print("")
        print(draft.body)
        print("")
        print("New-issue page: \(url.absoluteString)")
        guard flag("open") else { return }
        guard NSWorkspace.shared.open(url) else {
            Self.fail("The browser didn't open. The link is above\(copied ? ", and the full text is on your clipboard" : "").")
        }
        let existing = view.decisions[finding.id]
        var decision = existing ?? Decision(status: finding.status, decidedAt: .now)
        decision.reportedAt = .now
        try await engine.record(decision, for: finding.id)
        print("GitHub's new-issue page is open with the issue filled in. Nothing is posted until you submit it there.")
    }
}
