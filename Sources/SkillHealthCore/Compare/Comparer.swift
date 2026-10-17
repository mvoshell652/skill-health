import Foundation

/// Checks every recorded skill against its source. Per repository: its default branch, its
/// latest commit and that commit's file list, plus, once ever per batch of installs, the commit
/// the install took and its file list. A source whose latest commit hasn't moved reuses what the
/// last check found, so a quiet day costs two requests per repository.
public struct Comparer: Sendable {
    let host: any SourceHost
    /// Installs further apart than this are separate batches, each with its own commit.
    static let batchGap: TimeInterval = 10 * 60

    public init(host: any SourceHost) {
        self.host = host
    }

    /// How many commits before an install are tried as the version it took.
    static let installCandidates = 5

    /// Checks every recorded skill. `records` are the commits Skill Health updated skills to; they are
    /// read here, never written, so a check can't lose one.
    public func check(_ skills: [Skill], previous: CompareFile, records: UpdateRecords = UpdateRecords(),
                      now: Date) async -> CompareFile {
        var file = previous.version == CompareFile.currentVersion ? previous : CompareFile()
        file.stopped = nil
        let byRepo = Dictionary(grouping: skills.filter { $0.origin != nil }) { $0.origin!.repo }
        for repo in byRepo.keys.sorted() {
            do {
                try await check(repo, skills: byRepo[repo]!, records: records, file: &file, now: now)
            } catch .rateLimited(let resetAt) {
                file.stopped = SkillHealthError.rateLimited(resetAt: resetAt).plainDescription
                break
            } catch {
                file.sources[repo, default: .init()].problem = error.plainDescription
            }
        }
        // Forget skills that are no longer installed, so the file never describes a stale folder.
        let installed = Set(skills.map(\.name))
        file.copies = file.copies.filter { installed.contains($0.key) }
        file.checkedAt = now
        return file
    }

    private func check(_ repo: String, skills: [Skill], records: UpdateRecords, file: inout CompareFile,
                       now: Date) async throws(SkillHealthError) {
        var source = file.sources[repo] ?? .init()
        let branch = try await host.defaultBranch(of: repo)
        if branch != source.branch { source.installs = [:] }
        source.branch = branch
        let head = try await host.headCommit(of: repo, branch: branch)

        // File lists, fetched once per commit per check.
        var trees: [String: SourceTree] = [:]
        func tree(_ commit: String) async throws(SkillHealthError) -> SourceTree {
            if let cached = trees[commit] { return cached }
            let files = try await host.files(of: repo, at: commit)
            trees[commit] = files
            return files
        }

        // The commit each batch of installs took, found once and kept.
        var installCommit: [String: String] = [:]   // skill name -> commit
        for batch in Self.batches(skills) {
            let key = batch.start.formatted(.iso8601)
            let commit: String
            if let known = source.installs[key] {
                commit = known
            } else {
                let candidates = try await host.commits(of: repo, branch: branch, atOrBefore: batch.start,
                                                        limit: Self.installCandidates)
                guard !candidates.isEmpty else { throw .installNotFound(repo, batch.start) }
                commit = try await Self.installedVersion(of: batch.skills, among: candidates, tree: tree)
                source.installs[key] = commit
            }
            // A copy Skill Health updated came from the commit it was updated to, while that update
            // still holds (no reinstall since).
            for skill in batch.skills { installCommit[skill.name] = records.commit(for: skill) ?? commit }
        }

        for skill in skills {
            guard let origin = skill.origin, let installedFrom = installCommit[skill.name] else { continue }
            let old = file.copies[skill.name]
            let reusable = old.map { $0.repo == repo && $0.subpath == origin.subpath } ?? false
            let installed = reusable && old?.installedFrom == installedFrom
                ? old!.installed : Self.folder(origin.subpath, in: try await tree(installedFrom)).blobs
            var current: (blobs: [String: String], executables: Set<String>)?
            if reusable, old?.head == head, old?.sourceExecutables != nil || old?.source == nil {
                current = old!.source.map { ($0, old!.sourceExecutables ?? []) }
            } else {
                let folder = Self.folder(origin.subpath, in: try await tree(head))
                current = folder.blobs.isEmpty ? nil : (folder.blobs, folder.executables)
            }
            file.copies[skill.name] = .init(repo: repo, subpath: origin.subpath, installedFrom: installedFrom,
                                            head: head, installed: installed, source: current?.blobs,
                                            sourceExecutables: current?.executables)
        }
        source.head = head
        source.checkedAt = now
        source.problem = nil
        file.sources[repo] = source
    }

    /// The commit a batch of installs took. By date alone the newest candidate, but in a
    /// repository that merges pull requests a commit can be dated before it reached the branch,
    /// so each candidate is tried against the copies on disk: the one most of them match exactly
    /// is the one installed (an untouched copy is byte for byte the version it came from). Stops
    /// at the first candidate every copy matches. Copies edited since match none, which is fine:
    /// they don't vote.
    static func installedVersion(of skills: [Skill], among candidates: [String],
                                 tree: (String) async throws(SkillHealthError) -> SourceTree) async throws(SkillHealthError) -> String {
        let local = skills.compactMap { skill in skill.origin.map { (LocalCopy.files(in: skill.folder), $0.subpath) } }
        guard local.contains(where: { !$0.0.isEmpty }), candidates.count > 1 else { return candidates[0] }
        var best = (commit: candidates[0], matches: -1)
        for candidate in candidates {
            let files = try await tree(candidate)
            let matches = local.count { copy, subpath in folder(subpath, in: files).blobs == copy }
            if matches > best.matches { best = (candidate, matches) }
            if matches == local.count { break }
        }
        return best.commit
    }

    /// Installs grouped by time: openskills installs a whole repository's skills within seconds,
    /// so each batch took one commit. Keyed by the batch's first install.
    static func batches(_ skills: [Skill]) -> [(start: Date, skills: [Skill])] {
        let sorted = skills.compactMap { skill in skill.origin.map { (skill, $0.installedAt) } }.sorted { $0.1 < $1.1 }
        var batches: [(start: Date, skills: [Skill])] = []
        var last: Date?
        for (skill, at) in sorted {
            if let last, at.timeIntervalSince(last) <= batchGap, !batches.isEmpty {
                batches[batches.count - 1].skills.append(skill)
            } else {
                batches.append((at, [skill]))
            }
            last = at
        }
        return batches
    }

    /// The files under one skill's folder in a repository, by path inside the folder. An empty
    /// subpath means the repository itself is the skill.
    static func folder(_ subpath: String, in files: SourceTree) -> SourceTree {
        let trimmed = subpath.split(separator: "/").joined(separator: "/")
        let prefix = trimmed.isEmpty ? "" : trimmed + "/"
        var result = SourceTree(blobs: [:])
        for (path, blob) in files.blobs where path.hasPrefix(prefix) {
            let inside = String(path.dropFirst(prefix.count))
            let parts = inside.split(separator: "/")
            // The same files LocalCopy leaves out, so the two lists mean the same thing.
            if let name = parts.last, LocalCopy.ignoredFiles.contains(String(name)) { continue }
            if parts.dropLast().contains(where: { LocalCopy.ignoredFolders.contains(String($0)) }) { continue }
            result.blobs[inside] = blob
            if files.executables.contains(path) { result.executables.insert(inside) }
        }
        return result
    }
}

private extension Dictionary {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
