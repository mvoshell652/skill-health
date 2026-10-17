import Foundation

/// What became of a plan's skills: those written (or not, with why, in `outcome`) and those
/// refused before anything was touched.
public struct PlannedUpdates: Sendable, Equatable {
    public var outcome = UpdateOutcome()
    /// Skill to why it was left as it was, decided before any file was written.
    public var refused: [String: String] = [:]

    public init() {}
}

extension PendingPlan.Update.Skill {
    /// What is wrong with this skill's change list on its face, or nil. Each change's kind is what
    /// its blobs say (added only when nothing was there, removed only when nothing is left), and its
    /// executable flag is what the last comparison recorded for the source's copy: a plan can't ask
    /// for a file to become runnable that the source doesn't hold runnable.
    func problem(compare: CompareFile) -> String? {
        let executables = compare.copies[skill]?.sourceExecutables
        for change in changes {
            guard FileChange.Kind(before: change.before, after: change.after) == change.kind else {
                return "its list of changes doesn't add up"
            }
            let expected = change.after == nil ? nil : executables.map { $0.contains(change.path) }
            guard change.executable == expected else { return "its list of changes doesn't match how its source lists the files" }
        }
        return nil
    }
}

extension Engine {
    /// The words for a source that couldn't confirm an update.
    static func unconfirmed(_ error: any Error) -> String {
        let base = "Skill Health couldn't reach GitHub to confirm this update"
        guard let error = error as? SkillHealthError else { return "\(base): \(error.localizedDescription)" }
        switch error {
        case .offline(let message): return "\(base): \(message)"
        case .rateLimited(let resetAt):
            let when = resetAt.map { " It resets at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
            return "\(base). GitHub's hourly limit is reached.\(when) Try again then."
        default: return "\(base). \(error.plainDescription)"
        }
    }

    /// Asks the source itself whether an update's files are the ones it holds: for each distinct
    /// repository and commit in the plan, its file list is fetched once, every file that is written
    /// must have the blob id the list gives at <the skill's subpath>/<path>, every file that is
    /// removed must be absent from it, and a file marked runnable must be runnable there. This is
    /// what binds a plan to GitHub rather than to the comparison file and staged downloads, which
    /// anything that can write to ~/.claude/skill-health could forge together. Returns each skill that
    /// didn't confirm, with why; a source that can't be reached confirms nothing.
    public nonisolated func confirmAtSource(_ skills: [PendingPlan.Update.Skill], host: any SourceHost) async -> [String: String] {
        struct Version: Hashable {
            let repo: String
            let commit: String
        }
        var refused: [String: String] = [:]
        for (version, group) in Dictionary(grouping: skills, by: { Version(repo: $0.repo, commit: $0.commit) }) {
            let tree: SourceTree
            do { tree = try await host.files(of: version.repo, at: version.commit) } catch {
                for skill in group { refused[skill.skill] = Self.unconfirmed(error) }
                continue
            }
            for skill in group {
                let subpath = skill.origin.subpath.split(separator: "/").map(String.init)
                for change in skill.changes {
                    let remote = (subpath + [change.path]).joined(separator: "/")
                    let listed = tree.blobs[remote]
                    let runnable = tree.executables.contains(remote)
                    guard listed == change.after, change.after == nil ? change.executable == nil : (change.executable ?? runnable) == runnable else {
                        refused[skill.skill] = "the files prepared for it aren't the ones \(skill.repo) lists for that version"
                        break
                    }
                }
            }
        }
        return refused
    }

    /// Everything between the person approving a plan and the files landing. Per skill: it must
    /// still be a copy to update, unchanged here and with the same source, and the plan's changes
    /// must be exactly what the last comparison and this Mac's files give now (`sourceDelta`), with
    /// kinds and executable flags that agree with their blobs; then GitHub must confirm the files
    /// (`confirmAtSource`); then the staged downloads are read again and checked against their blob
    /// ids, and the copies written, all or nothing per skill (`applyUpdates`). A skill that fails
    /// any step is left as it was, with why.
    public func applyPlanned(_ staged: [PendingPlan.Update.Skill], staging: URL, skills: [Skill], compare: CompareFile,
                             host: any SourceHost, now: Date = .now) async -> PlannedUpdates {
        var result = PlannedUpdates()
        var standing: [(item: PendingPlan.Update.Skill, skill: Skill)] = []
        for item in staged {
            let expected = Dictionary(item.changes.map { ($0.path, SourceDelta.Blobs(before: $0.before, after: $0.after)) },
                                      uniquingKeysWith: { first, _ in first })
            guard let current = skills.first(where: { $0.name == item.skill }), current.isSafeUpdate, current.origin == item.origin,
                  Self.samePath(item.folder, current.folder),
                  let delta = sourceDelta(for: current, compare: compare),
                  delta.repo == item.repo, delta.commit == item.commit,
                  expected.count == item.changes.count, delta.changes == expected else {
                result.refused[item.skill] = "it or its source changed after the preview"
                continue
            }
            if let problem = item.problem(compare: compare) {
                result.refused[item.skill] = problem
                continue
            }
            standing.append((item, current))
        }
        let unconfirmed = await confirmAtSource(standing.map(\.item), host: host)
        var updates: [CopyUpdate] = []
        for (item, current) in standing {
            if let why = unconfirmed[item.skill] {
                result.refused[item.skill] = why
            } else if let update = Self.rebuilt(item, folder: current.folder, staging: staging) {
                updates.append(update)
            } else {
                result.refused[item.skill] = "it changed after the preview"
            }
        }
        if !updates.isEmpty { result.outcome = applyUpdates(updates, now: now) }
        return result
    }

    /// The update as it will be written, from the files on this Mac now and the staged downloads,
    /// each checked against the blob id the plan names; nil if any isn't what the plan says.
    private static func rebuilt(_ item: PendingPlan.Update.Skill, folder: URL, staging: URL) -> CopyUpdate? {
        var changes: [FileChange] = []
        for change in item.changes {
            var before: Data?
            if let blob = change.before {
                guard let file = try? inside(folder, change.path), let data = try? Data(contentsOf: file),
                      GitBlob.id(of: data) == blob else { return nil }
                before = data
            }
            var after: Data?
            if let staged = change.staged {
                guard let file = try? inside(staging, staged), let data = try? Data(contentsOf: file),
                      GitBlob.id(of: data) == change.after else { return nil }
                after = data
            } else if change.after != nil {
                return nil
            }
            changes.append(FileChange(path: change.path, kind: change.kind, before: before, after: after, executable: change.executable))
        }
        return CopyUpdate(skill: item.skill, folder: folder, origin: item.origin, repo: item.repo,
                          commit: item.commit, changes: changes, historyURL: item.historyURL)
    }

    /// Two paths name the same file or folder (a trailing slash or a "." doesn't matter).
    static func samePath(_ a: String, _ b: URL) -> Bool {
        URL(filePath: a).standardizedFileURL.pathComponents == b.standardizedFileURL.pathComponents
    }
}
