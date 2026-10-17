import Foundation
import SkillHealthCore

// /skill-health:undo's commands: list what can be put back or reopened, preview it, apply it.

extension Tool {
    struct UndoEntry {
        let id: String
        let kind: String
        let skill: String
        let when: Date
        let detail: String
    }

    func undo() async throws {
        switch arguments.dropFirst().first {
        case "list": await undoList()
        case "preview": try await undoPreview()
        case "apply": try await undoApply()
        default: Self.usageError("skill-health undo list [--json] | skill-health undo preview <entry> | skill-health undo apply <plan>")
        }
    }

    /// The skill a fix was made in, and the file's path inside it: from the finding when it is
    /// still listed, otherwise from the skill whose folder holds the file (the finding goes when
    /// its skill is checked again, and a nested file's own folder isn't the skill).
    func fixedIn(_ patch: PatchRecord, finding: Finding?, view: Overview) -> (skill: String, path: String) {
        let file = URL(filePath: patch.file).standardizedFileURL.pathComponents
        let holder = view.skills
            .filter { file.starts(with: $0.folder.standardizedFileURL.pathComponents) }
            .max { $0.folder.standardizedFileURL.pathComponents.count < $1.folder.standardizedFileURL.pathComponents.count }
        let skill = finding?.skillName ?? holder?.name ?? URL(filePath: patch.file).deletingLastPathComponent().lastPathComponent
        let path = finding?.filePath ?? holder.map { file.dropFirst($0.folder.standardizedFileURL.pathComponents.count).joined(separator: "/") }
            ?? URL(filePath: patch.file).lastPathComponent
        return (skill, path)
    }

    /// The line a fix wrote, as the diff numbers it, and what it says, when the file still holds the fix.
    func fixedLine(_ patch: PatchRecord) -> (number: Int, text: String)? {
        guard let now = try? Data(contentsOf: URL(filePath: patch.file)), GitBlob.id(of: now) == patch.written,
              let then = try? Data(contentsOf: URL(filePath: patch.backup)),
              let after = SkillText.exact(now), let before = SkillText.exact(then) else { return nil }
        let diff = ProposedWrite(file: URL(filePath: patch.file), before: before, after: after).diff
        guard let first = diff.split(separator: "\n").first(where: { $0.hasPrefix("+") }),
              let colon = first.firstIndex(of: ":"), let number = Int(first[first.index(after: first.startIndex)..<colon]) else { return nil }
        return (number, String(first[first.index(after: colon)...]))
    }

    /// The start of an instruction, on one line, to tell one entry from another: the first 40
    /// characters, with a mark when there is more.
    static func excerpt(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return shown(String(line.prefix(40))) + (line.count > 40 ? "…" : "")
    }

    /// Fixes, updates and decisions, most recent first. Each says which instruction it is about, so
    /// two entries in one skill are never the same words. A set-aside that has lapsed, or that came
    /// back because its source changed, is already open and isn't listed.
    func undoEntries(in view: Overview) async -> [UndoEntry] {
        var entries: [UndoEntry] = []
        for (key, decision) in view.decisions.decisions {
            guard let id = UUID(uuidString: key) else { continue }
            let finding = view.finding(id: id)
            switch decision.status {
            case .patched:
                guard let patch = decision.patch else { continue }
                let place = fixedIn(patch, finding: finding, view: view)
                let path = Self.shown(place.path)
                let detail: String
                if let line = fixedLine(patch) {
                    detail = "Line \(line.number) of \(path): \(Self.excerpt(line.text))"
                } else {
                    // The file no longer holds the fix, so the line can't be found: the check's own words.
                    detail = "1 line in \(path)" + ((finding?.suggestedText ?? finding?.skillSays).map { ": \(Self.excerpt($0))" } ?? "")
                }
                // A fix whose backup is gone can't be put back, which is what "Nothing to undo" says.
                guard FileManager.default.fileExists(atPath: patch.backup) else { continue }
                entries.append(.init(id: "fix:\(key)", kind: "fix", skill: place.skill, when: decision.decidedAt, detail: detail))
            case .setAside(let until):
                guard let finding, !finding.isOpen() else { continue }
                let orSource = decision.untilSourceChanges == nil ? "" : ", or until its source changes"
                entries.append(.init(id: "decision:\(key)", kind: "decision", skill: finding.skillName, when: decision.decidedAt,
                                     detail: "Set aside until \(Self.day(until))\(orSource): \(Self.excerpt(finding.skillSays))"))
            case .usingAnotherSkill(let name):
                guard let finding, !finding.isOpen() else { continue }
                entries.append(.init(id: "decision:\(key)", kind: "decision", skill: finding.skillName, when: decision.decidedAt,
                                     detail: "Using \(Self.shown(name)) instead: \(Self.excerpt(finding.skillSays))"))
            case .notForThisProject:
                // An older app's "not for this project": still a set-aside the counts include, so it's listed to reopen.
                guard let finding, !finding.isOpen() else { continue }
                entries.append(.init(id: "decision:\(key)", kind: "decision", skill: finding.skillName, when: decision.decidedAt,
                                     detail: "Set aside for this project: \(Self.excerpt(finding.skillSays))"))
            case .open:
                continue
            }
        }
        for (folder, manifest) in engine.updateManifests() {
            entries.append(.init(id: "update:\(manifest.skill):\(folder.lastPathComponent)", kind: "update", skill: manifest.skill,
                                 when: manifest.updatedAt, detail: Self.plural(manifest.files.count, "file", "files")))
        }
        return entries.sorted { ($0.when, $1.id) > ($1.when, $0.id) }
    }

    func undoList() async {
        requireSkillsFolder()
        let view = await overview()
        // Without the results or the decisions, "nothing to undo" could be untrue.
        if let problem = view.blockingProblem { Self.fail(problem) }
        let entries = await undoEntries(in: view)
        // An update whose undo record can't be read can't be undone, and is said, not left out.
        let unreadable = engine.unreadableUpdateManifests().map { $0.path(percentEncoded: false) }
        if json {
            printObject(["entries": entries.map { ["id": $0.id, "kind": $0.kind, "skill": $0.skill, "when": $0.when, "detail": $0.detail] },
                         "unreadable": unreadable])
            return
        }
        defer {
            if !unreadable.isEmpty {
                print(unreadable.count == 1 ? "1 update's undo record couldn't be read, so it can't be undone: \(unreadable[0])"
                      : "\(unreadable.count) updates' undo records couldn't be read, so they can't be undone: \(unreadable.joined(separator: ", "))")
            }
        }
        guard !entries.isEmpty else {
            if unreadable.isEmpty { print("Nothing to undo. No fix or update has been made, or its backup is gone.") }
            return
        }
        for entry in entries {
            let verb = entry.kind == "fix" ? "Fixed" : entry.kind == "update" ? "Updated" : "Decided"
            print("[\(entry.id)] \(Self.shown(entry.skill)): \(verb) \(Self.day(entry.when)). \(entry.detail).")
        }
    }

    /// A fix's undo as the prompt shows it, from its decision record and the files on disk.
    func undoFixPreview(_ id: UUID, in view: Overview) throws(SkillHealthError) -> (summary: String, diff: String, patch: PatchRecord, skill: String, decidedAt: Date) {
        guard let decision = view.decisions[id], let patch = decision.patch, case .patched = decision.status else {
            Self.fail("There's no fix with that id. Run skill-health undo list.")
        }
        let file = URL(filePath: patch.file)
        guard let current = try? Data(contentsOf: file), GitBlob.id(of: current) == patch.written, let now = SkillText.exact(current) else {
            throw .changedSincePatch(file.lastPathComponent)
        }
        guard let original = try? Data(contentsOf: URL(filePath: patch.backup)), GitBlob.id(of: original) == patch.original,
              let then = SkillText.exact(original) else {
            throw .backupMissing(file.lastPathComponent)
        }
        let skill = fixedIn(patch, finding: view.finding(id: id), view: view).skill
        // A very long line is shown cut around the change; apply builds the same text again.
        let diff = ProposedWrite(file: file, before: now, after: then).condensedDiff
        return (Self.undoFixSummary(skill: skill, path: patch.file, diff: diff), diff, patch, skill, decision.decidedAt)
    }

    func undoPreview() async throws {
        guard let entry = operands(after: 2).first else { Self.usageError("Give the entry's id, as skill-health undo list shows it.") }
        let view = await overview()
        if let problem = view.decisionsProblem { Self.fail(problem) }
        let parts = entry.split(separator: ":", maxSplits: 2).map(String.init)
        switch parts.first {
        case "fix":
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { Self.fail("There's no fix with that id. Run skill-health undo list.") }
            let preview = try undoFixPreview(id, in: view)
            try Self.requireWhole(preview.summary)
            let plan = PendingPlan(kind: .undo, summary: preview.summary, undo: .init(finding: id, backup: nil, skill: preview.skill))
            try plans.save(plan)
            print("Putting back \(Self.shown(preview.patch.file)) as it was before \(Self.day(preview.decidedAt)):")
            print("")
            print(Self.shown(preview.diff))
            print("")
            print("Plan: \(plan.id.uuidString)")
        case "update":
            guard parts.count == 3, let match = engine.updateManifests().first(where: { $0.manifest.skill == parts[1] && $0.folder.lastPathComponent == parts[2] })
            else { Self.fail("There's no update with that id. Run skill-health undo list.") }
            let manifest = match.manifest
            try requireInstalled(manifest, in: view)
            let summary = Self.undoUpdateSummary(manifest)
            try Self.requireWhole(summary)
            let plan = PendingPlan(kind: .undo, summary: summary,
                                   undo: .init(finding: nil, backup: match.folder.path(percentEncoded: false), skill: manifest.skill))
            try plans.save(plan)
            print("Putting \(Self.shown(manifest.skill)) back as it was before \(Self.day(manifest.updatedAt)), in \(Self.shown(manifest.folder)):")
            Self.undoUpdateLines(manifest).forEach { print($0) }
            print("")
            print("Plan: \(plan.id.uuidString)")
        case "decision":
            guard parts.count == 2, UUID(uuidString: parts[1]) != nil else { Self.fail("There's no decision with that id. Run skill-health undo list.") }
            print("A decision changes no file, so there's nothing to preview. To reopen it: skill-health decide \(parts[1]) reopen")
        default:
            Self.usageError("Give an entry id as skill-health undo list shows it: fix:…, update:… or decision:….")
        }
    }

    /// An update's record must name the skill that is installed, in its own folder: a record that
    /// points elsewhere can't send an undo to another skill's files.
    func requireInstalled(_ manifest: UpdateManifest, in view: Overview) throws(SkillHealthError) {
        guard let skill = view.skill(named: manifest.skill), Self.samePath(manifest.folder, skill.folder) else {
            throw .undoRecordInvalid("\(Self.shown(manifest.skill)) isn't installed in the folder it names")
        }
    }

    func undoApply() async throws {
        let plan = try plans.ready(planID(operands(after: 2).first), kind: .undo)
        guard let undo = plan.undo else { throw SkillHealthError.planNotFound }
        if let backup = undo.backup {
            // The update's own manifest, read again; the engine checks it names a skill folder.
            guard let match = engine.updateManifests().first(where: { Self.samePath(backup, $0.folder) }) else {
                throw SkillHealthError.planNotFound
            }
            let view = await overview()
            try requireInstalled(match.manifest, in: view)
            try Self.require(plan, shows: Self.undoUpdateSummary(match.manifest))
            try await engine.undoUpdate(at: match.folder)
            retire(plan)
            print("\(Self.shown(match.manifest.skill)) is back to how it was before its update. The next comparison will offer the update again.")
        } else if let id = undo.finding {
            let view = await overview()
            if let problem = view.decisionsProblem { Self.fail(problem) }
            let preview = try undoFixPreview(id, in: view)
            try Self.requireWhole(preview.summary)
            try Self.require(plan, shows: preview.summary)
            try await engine.undoPatch(finding: id)
            retire(plan)
            print("\(Self.shown(preview.skill)) is back to how it was before the fix. The instruction is open again.")
        } else {
            throw SkillHealthError.planNotFound
        }
    }
}
