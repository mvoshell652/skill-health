import Foundation
import SkillHealthCore

// /skill-health:update's commands, and compare. An update brings a copy up to its source; it doesn't
// fix instructions, because a newer copy can be wrong too.

extension Tool {
    func update() async throws {
        switch arguments.dropFirst().first {
        case "list": await updateList()
        case "preview": try await updatePreview()
        case "apply": try await updateApply()
        default: Self.usageError("skill-health update list [--json] | skill-health update preview <skill>... | --all | skill-health update apply <plan>")
        }
    }

    /// Why a skill you use that has something newer at its source isn't offered: a stable code for
    /// the plugin's commands to match on, and the words.
    struct LeftOut {
        let skill: Skill
        let reason: String
        let why: String
    }

    /// Skills you use that are behind and unchanged on this Mac; the others that are behind (or
    /// whose source is gone), with why. A copy changed here whose source hasn't moved has nothing
    /// newer, so it isn't on either list.
    func updateCandidates(in view: Overview) -> (eligible: [Skill], leftOut: [LeftOut]) {
        let eligible = view.skills.filter(\.isSafeUpdate).sorted { ($0.usesLast90Days, $1.name) > ($1.usesLast90Days, $0.name) }
        let leftOut: [LeftOut] = view.used.compactMap { skill in
            switch skill.copy {
            case .changedBoth: LeftOut(skill: skill, reason: "changedBoth", why: "changed on this Mac, so updating would write over your changes")
            case .removedAtSource: LeftOut(skill: skill, reason: "removedAtSource", why: "its source removed it")
            default: nil
            }
        }
        return (eligible, leftOut)
    }

    func compareAge(_ view: Overview) -> (at: Date?, stale: Bool) {
        guard let at = view.compare.checkedAt else { return (nil, true) }
        return (at, Date.now.timeIntervalSince(at) > 24 * 60 * 60)
    }

    func updateList() async {
        requireSkillsFolder()
        let view = await overview()
        let (eligible, leftOut) = updateCandidates(in: view)
        let age = compareAge(view)
        let compared = view.compareProblems
        if json {
            printObject([
                "comparedAt": age.at, "stale": age.stale, "comparedProblems": compared.count, "stopped": view.compare.stopped,
                "eligible": eligible.map { skill -> [String: Any?] in
                    ["skill": skill.name, "loads": skill.usesLast90Days, "repo": skill.origin?.repo,
                     "history": view.compare.copies[skill.name]?.historyURL?.absoluteString]
                },
                "leftOut": leftOut.map { ["skill": $0.skill.name, "reason": $0.reason, "why": $0.why] },
            ])
            return
        }
        guard let at = age.at else {
            // An unreadable comparison reads as none at all; say which it is.
            print(view.compareProblem ?? "Skill Health hasn't compared your skills with their sources yet. Run /skill-health:update, or skill-health compare, to compare them.")
            return
        }
        let when = "Skill Health last compared with GitHub \(Self.ago(at))."
        // A comparison that couldn't read some sources, or stopped early, knows nothing about their
        // newer copies: "none" would be an answer it doesn't have.
        let incomplete = compared.count > 0 || view.compare.stopped != nil
        // Only a skill with a recorded source can be compared, so "none has a newer copy" is said
        // about those, and said plainly when there are none.
        let sourced = view.used.count { $0.origin != nil }
        if eligible.isEmpty {
            if sourced == 0 {
                print("Nothing to update. None of the skills you use has a recorded source, so Skill Health has nothing to compare.")
            } else {
                print(incomplete ? "Nothing to update that Skill Health knows of. \(when)"
                      : "Nothing to update. None of the \(sourced.formatted()) \(sourced == 1 ? "skill you use that has a source has" : "skills you use that have a source has") a newer copy that's safe to take. \(when)")
            }
        } else {
            print(eligible.count == 1 ? "1 skill you use has a newer copy at its source. \(when)"
                  : "\(eligible.count) skills you use have newer copies at their sources. \(when)")
            for skill in eligible { print("  \(Self.shown(skill.name))") }
        }
        if let sentence = compared.sentence { print(sentence) }
        if let paused = Self.pausedLine(view.compare) { print(paused) }
        if age.stale { print("That was more than a day ago, so this list may be out of date. Run skill-health compare to compare again.") }
        if !leftOut.isEmpty {
            print("Left out:")
            for entry in leftOut { print("  \(Self.shown(entry.skill.name)): \(entry.why)") }
        }
    }

    func updatePreview() async throws {
        let view = await overview()
        let (eligible, _) = updateCandidates(in: view)
        let names = flag("all") ? eligible.map(\.name) : operands(after: 2)
        guard !names.isEmpty else { Self.usageError("Name the skills to update, or --all.") }
        let id = UUID()
        let staging = plans.staging(for: id)
        var staged: [PendingPlan.Update.Skill] = []
        var printed = 0
        var notShown = 0
        let budget = 20_000
        for name in names {
            guard let skill = eligible.first(where: { $0.name == name }) else {
                let why = updateCandidates(in: view).leftOut.first { $0.skill.name == name }?.why
                print("\(name): not updated: \(why ?? "it isn't a skill you use with a newer copy that's safe to take").")
                continue
            }
            // One skill at a time, so one bad download skips that skill, not every one.
            let prepared: [CopyUpdate]
            do { prepared = try await engine.prepareUpdates(for: [skill]) } catch {
                print("\(name): not updated: \(error.plainDescription.droppingErrorPrefix)")
                continue
            }
            guard let update = prepared.first, !update.changes.isEmpty else { continue }
            var changes: [PendingPlan.Update.Change] = []
            for change in update.changes {
                var stagedPath: String?
                if let after = change.after {
                    let relative = "\(update.skill)/\(change.path)"
                    let target = relative.split(separator: "/").reduce(staging) { $0.appending(path: String($1)) }
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try after.write(to: target, options: .atomic)
                    stagedPath = relative
                }
                changes.append(.init(path: change.path, kind: change.kind, before: change.before.map(GitBlob.id(of:)),
                                     after: change.after.map(GitBlob.id(of:)), staged: stagedPath, executable: change.executable))
            }
            let item = PendingPlan.Update.Skill(skill: update.skill, folder: update.folder.path(percentEncoded: false),
                                                origin: update.origin, repo: update.repo, commit: update.commit,
                                                historyURL: update.historyURL, changes: changes)
            staged.append(item)
            print(Self.updateHead(item))
            if let history = update.historyURL { print("  What changed upstream: \(history.absoluteString)") }
            for change in update.changes {
                print("  \(change.kind.rawValue): \(Self.shown(change.path))")
                guard let lines = change.lines else {
                    print("    Not text, so not shown.")
                    continue
                }
                let shown = Self.revealed(lines).text
                if printed + shown.count > budget {
                    notShown += shown.split(separator: "\n").count
                    continue
                }
                printed += shown.count
                print(shown.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n"))
            }
            print("")
        }
        guard !staged.isEmpty else {
            try? FileManager.default.removeItem(at: staging)
            Self.fail("Nothing to update from that list.")
        }
        if notShown > 0 {
            print("\(notShown == 1 ? "1 more changed line isn't" : "\(notShown.formatted()) more changed lines aren't") shown here; each file's full new copy is in \(staging.path(percentEncoded: false)).")
        }
        let plan = PendingPlan(id: id, kind: .update, summary: Self.updateSummary(staged), update: .init(skills: staged))
        try plans.save(plan)
        print("Plan: \(plan.id.uuidString)")
    }

    func updateApply() async throws {
        let plan = try plans.ready(planID(operands(after: 2).first), kind: .update)
        guard let staged = plan.update?.skills, !staged.isEmpty else { throw SkillHealthError.planNotFound }
        // What Claude Code's prompt showed is rebuilt from the plan's own change list.
        try Self.require(plan, shows: Self.updateSummary(staged))
        let view = await overview()
        let staging = plans.staging(for: plan.id)
        // Each skill must still be a copy to update, and the files must be the ones the source's own
        // listing gives: the plan, the comparison file and the staged downloads could all be forged
        // together, GitHub's answer can't.
        let result = await engine.applyPlanned(staged, staging: staging, skills: view.skills, compare: view.compare,
                                               host: GitHubSource())
        let outcome = result.outcome
        // The plan is spent once anything was written; a refusal or a busy lock leaves it to run again.
        if !outcome.updated.isEmpty || !outcome.damaged.isEmpty {
            retire(plan)
            try? FileManager.default.removeItem(at: staging)
        }
        let report = outcome.report(refused: result.refused, backups: paths.backups.path(percentEncoded: false))
        report.lines.forEach { print($0) }
        if let failure = report.failure { Self.fail(failure) }
    }

    // MARK: compare

    func compare() async throws {
        requireSkillsFolder()
        let skills = try await engine.discoverSkills()
        let file = try await engine.checkSources(skills)
        let report = try? await engine.readUsage()
        let states = await engine.copyStates(of: skills, compare: file)
        let usedSkills = skills.filter { (report?.loads[$0.name] ?? 0) > 0 }
        let behind = usedSkills.filter { states[$0.name] == .behind }
        let problems = CompareProblems(compare: file, used: usedSkills)
        // Copies of a source that couldn't be read are from an earlier comparison, so they don't count.
        let read = file.copies.values.count { file.sources[$0.repo]?.problem == nil }
        if read > 0 {
            print("Compared \(Self.plural(read, "skill", "skills")) with \(read == 1 ? "its source" : "their sources") on GitHub.")
        }
        if report == nil {
            print("Skill Health couldn't read which skills you use, so which have newer copies isn't known.")
        } else if !behind.isEmpty {
            print("\(Self.plural(behind.count, "skill you use has a newer copy", "skills you use have newer copies")): \(behind.map { Self.shown($0.name) }.sorted().joined(separator: ", ")).")
        } else if problems.count == 0, file.stopped == nil {
            let sourced = usedSkills.count { $0.origin != nil }
            print(sourced == 0 ? "None of the skills you use has a recorded source, so there was nothing to compare."
                  : "None of the \(sourced.formatted()) \(sourced == 1 ? "skill you use that has a source has" : "skills you use that have a source has") a newer copy.")
        }
        if let sentence = problems.sentence { print(sentence) }
        // Only the sources of skills you use, which are the ones the sentence above counts.
        let usedRepos = Set(usedSkills.compactMap { $0.origin?.repo })
        for (repo, source) in file.sources.sorted(by: { $0.key < $1.key }) where usedRepos.contains(repo) {
            if let problem = source.problem { print("  \(Self.shown(repo)): \(problem)") }
        }
        if let paused = Self.pausedLine(file) { print(paused) }
    }
}
