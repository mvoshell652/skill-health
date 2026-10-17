import Foundation
import SkillHealthCore

/// Why the files Claude Code reads at the start of a session weren't brought up to date. They are left as
/// they were: an empty list written over a good one would silence the corrections.
struct RefreshProblem: Error {
    let message: String
}

extension Tool {
    /// A command that changes what the next session's note and corrections would say: a check's
    /// results, a comparison (a set-aside until the source changes can reopen), a decision, or a
    /// fix, update or undo that was applied.
    var changesWhatClaudeGets: Bool {
        switch arguments.first {
        case "save-findings", "decide", "compare": true
        case "fix", "update", "undo": arguments.dropFirst().first == "apply"
        default: false
        }
    }

    /// Brings status.json and the two files the plugin's SessionStart hook prints up to date: the note
    /// for the person, and the corrections for Claude. The Mac app writes the same files with the same
    /// code, so either alone is enough. Local files only: nothing is sent, and no skill is changed.
    func refreshSessionFiles() async throws -> StatusSnapshot {
        guard FileManager.default.fileExists(atPath: paths.skills.path(percentEncoded: false)) else {
            throw RefreshProblem(message: "There's no skills folder at \(paths.skills.path(percentEncoded: false)), so there's nothing to look at.")
        }
        let read = sharedRead
        let view = await engine.overview(shared: read.corrections)
        // The same rule as every command that reads: while the results, the decisions, the known
        // corrections or the usage can't be read, an empty list could be untrue, so nothing is written.
        let problem = view.blockingProblem ?? read.problem ?? view.usageProblem.map { "Skill Health couldn't read which skills you use: \($0)" }
        if let problem { throw RefreshProblem(message: problem) }
        let snapshot = StatusSnapshot.make(findings: view.findings.findings, skills: view.skills)
        try await engine.writeStatus(snapshot)
        try await engine.markRefreshed()
        return snapshot
    }

    /// `skill-health refresh`.
    func refresh() async {
        // Started by the session hook with nothing waiting on it: a read that hangs (a stalled mount)
        // would otherwise leave a process behind for good.
        alarm(10 * 60)
        do {
            let snapshot = try await refreshSessionFiles()
            let count = snapshot.corrections.count
            print(count == 0
                  ? "Claude has nothing to be told at the start of a session: none of the skills you use has an open failing instruction."
                  : "Claude will get \(Self.plural(count, "correction", "corrections")) at the start of a session.")
        } catch let problem as RefreshProblem {
            Self.fail(problem.message)
        } catch {
            Self.fail(error.localizedDescription)
        }
    }

    /// After a command that changed something: the same refresh, without failing the command that
    /// just succeeded. The session hook brings the files up to date on its own if this one couldn't.
    func refreshQuietly() async {
        _ = try? await refreshSessionFiles()
    }
}
