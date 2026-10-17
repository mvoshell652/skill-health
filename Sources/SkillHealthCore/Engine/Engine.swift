import Foundation

/// The one engine both front ends use. Being an actor orders calls inside one process;
/// the app and the CLI are separate processes, so every file is written whole with an
/// atomic rename and readers never see a half-written file. Skill files change only
/// through `apply(_:)`.
public actor Engine {
    public nonisolated let paths: SkillHealthPaths
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    /// How deep this actor is inside `locked`: the lock is one per process, and a locked call can
    /// make another (a patch records its decision).
    private var lockDepth = 0

    public init(paths: SkillHealthPaths) {
        self.paths = paths
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    // MARK: Reading

    /// Every skill folder and its openskills receipt. Local files only; nothing is sent.
    /// No skills folder yet means no skills, not an error.
    public func discoverSkills() throws -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.skills.path(percentEncoded: false)) else { return [] }
        // By path, not URL: Foundation's URL listing throws "not a directory" when ~/.claude/skills is
        // itself a symlink to a folder (dotfile managers, a shared ~/.agents/skills), the path listing doesn't.
        let names = try fm.contentsOfDirectory(atPath: paths.skills.path(percentEncoded: false))
        return names.compactMap { name -> Skill? in
            let folder = paths.skills.appending(path: name, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: folder.appending(path: "SKILL.md").path(percentEncoded: false)) else { return nil }
            let origin = (try? Data(contentsOf: folder.appending(path: ".openskills.json")))
                .flatMap { try? decoder.decode(OpenSkillsReceipt.self, from: $0) }
                .map { Origin(repo: $0.source, subpath: $0.subpath, installedAt: $0.installedAt) }
            return Skill(name: folder.lastPathComponent, folder: folder, origin: origin)
        }
        .sorted { $0.name < $1.name }
    }

    /// Which skills were loaded in the last 90 days, from Claude Code's session files. Runs off
    /// the actor: a first read can take many seconds, and skill discovery and writes must not
    /// queue behind it.
    @concurrent
    public nonisolated func readUsage(now: Date = .now) async throws -> UsageReport {
        try UsageReader(paths: paths).read(now: now)
    }

    /// A missing file means nothing has been audited yet. Any other failure is an error,
    /// never an empty list, so a broken file can't read as a clean report.
    public func loadFindings() throws -> FindingsFile {
        try read(FindingsFile.self, from: paths.findings) ?? FindingsFile()
    }

    public func loadSettings() throws -> Settings {
        try read(Settings.self, from: paths.settings) ?? Settings()
    }

    public func readStatus() -> StatusSnapshot? {
        try? read(StatusSnapshot.self, from: paths.status)
    }

    /// The plugin's name in Claude Code: `skill-health@<marketplace>` in its record of installed plugins.
    public static let pluginName = "skill-health"

    /// Whether Claude Code has the Skill Health plugin, and when its hook last read Skill Health's notes.
    public func claudeCodeLink() -> ClaudeCodeLink {
        let fm = FileManager.default
        let lastRead = (try? fm.attributesOfItem(atPath: paths.hookRead.path(percentEncoded: false)))?[.modificationDate] as? Date
        // Claude Code's own record of installed plugins: an internal format, so only a hint.
        // The hook having run is the proof.
        let record = paths.claudeHome.appending(path: "plugins/installed_plugins.json")
        let installed = (try? Data(contentsOf: record))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["plugins"] as? [String: Any] }
            .map { $0.keys.contains { $0.hasPrefix(Self.pluginName + "@") } } ?? false
        return ClaudeCodeLink(installed: installed, lastRead: lastRead)
    }

    // MARK: Skill Health's own files

    public func saveFindings(_ file: FindingsFile) throws { try write(file, to: paths.findings) }

    public func saveSettings(_ settings: Settings) throws { try write(settings, to: paths.settings) }

    /// Writes status.json and the two files the plugin's hook prints. Skips the write when
    /// nothing changed, except once a day: the hook goes quiet once its files are 7 days old
    /// (whatever writes them may be gone), so the running app, or the plugin's `skill-health
    /// refresh`, keeps them fresh.
    public func writeStatus(_ snapshot: StatusSnapshot, now: Date = .now) throws {
        let fm = FileManager.default
        let written = (try? fm.attributesOfItem(atPath: paths.status.path(percentEncoded: false)))?[.modificationDate] as? Date
        // A file dated in the future (a clock that ran ahead once) is not "recent": rewrite it, or the
        // hook would never find it fresh.
        if let current = readStatus(), current.sameContent(as: snapshot),
           let written, (0..<24 * 60 * 60).contains(now.timeIntervalSince(written)) { return }
        try write(snapshot, to: paths.status)
        try writeHook(SessionStartHook.output(snapshot: snapshot, lastNoteAt: nil, now: now)?.output, to: paths.hookNote)
        try writeHook(SessionStartHook.output(snapshot: snapshot, lastNoteAt: now, now: now)?.output, to: paths.hookQuiet)
    }

    /// Notes that what Claude gets was just brought up to date, even if it didn't change, so the
    /// plugin's session hook doesn't start another refresh for a day (see plugin/scripts/session-start.sh).
    public func markRefreshed() throws {
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try Data().write(to: paths.refreshed, options: .atomic)
    }

    /// One hook file, or none at all when the hook should stay silent.
    private func writeHook(_ output: HookOutput?, to url: URL) throws {
        guard let output else {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { try FileManager.default.removeItem(at: url) }
            return
        }
        try write(output, to: url)
    }

    // MARK: Skill files

    /// The only way Skill Health changes a skill file. Refuses files outside the skills folder,
    /// links, and files that changed after the person reviewed the diff (compared byte for
    /// byte). Copies the current file to backups first.
    @discardableResult
    public func apply(_ write: ReviewedWrite, now: Date = .now) throws -> URL {
        let file = write.proposal.file
        let resolved = try writable(file)
        let root = paths.skills.resolvingSymlinksInPath().pathComponents

        let current = try Data(contentsOf: file)
        guard current == Data(write.proposal.before.utf8) else { throw SkillHealthError.fileChangedSinceReview(file) }

        // backups/<skill>/<timestamp>-<id>/<path inside the skill>: unique per write, and a
        // nested file like references/api.md keeps both its skill and its folder.
        let inside = resolved.dropFirst(root.count)
        let skillName = inside.first ?? "unknown"
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
            .replacing(":", with: "-")
        let backup = inside.dropFirst().reduce(
            paths.backups.appending(path: skillName).appending(path: "\(stamp)-\(write.proposal.id.uuidString.prefix(8))")
        ) { $0.appending(path: $1) }
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try current.write(to: backup, options: .atomic)
        try Data(write.proposal.after.utf8).write(to: file, options: .atomic)
        return backup
    }

    /// The file's path with its folders' links resolved, if Skill Health may write it: inside the skills
    /// folder (a skill folder that links elsewhere isn't), and not itself a link.
    func writable(_ file: URL) throws -> [String] {
        // Compare path components, not strings: a directory URL can carry a trailing slash.
        // Resolve links on the folder side only, so a link at the file itself is still caught.
        let root = paths.skills.resolvingSymlinksInPath().pathComponents
        let resolved = file.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents + [file.lastPathComponent]
        guard resolved.count > root.count + 1, Array(resolved.prefix(root.count)) == root else {
            throw SkillHealthError.notInsideSkills(file)
        }
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw SkillHealthError.linkedFile(file) }
        return resolved
    }

    // MARK: Sources (M3)

    /// What the last check found. A missing or unreadable file is an empty one: it holds only
    /// what the next check rebuilds, so nothing is lost by starting over.
    /// (Update records live apart, in updates.json, for exactly this reason.)
    public func loadCompare() -> CompareFile {
        (try? read(CompareFile.self, from: paths.compare)) ?? CompareFile()
    }

    /// Why compare.json can't be read, or nil when it can or doesn't exist yet. Starting over is
    /// safe (loadCompare), but a person should hear that the comparison they ran is gone.
    public func compareProblem() -> String? {
        do { _ = try read(CompareFile.self, from: paths.compare); return nil } catch {
            return ProblemText.compareUnreadable(ProblemText.reason(error))
        }
    }

    /// Checks every recorded skill against its source and saves what was found. Update records
    /// are read, never rebuilt; afterwards, records that no longer hold (the skill was removed
    /// or reinstalled) are dropped, in a step with no await, so an update can't land in between.
    public func checkSources(_ skills: [Skill], host: any SourceHost = GitHubSource(), now: Date = .now) async throws -> CompareFile {
        let started = loadUpdateRecords()
        var file = await Comparer(host: host).check(skills, previous: loadCompare(), records: started, now: now)
        try locked {
            // An update or an undo can land while GitHub answers (the plugin's tool runs apart from
            // the app). Its skill's listing is then newer than the one computed here: keep it.
            let landed = loadUpdateRecords()
            if landed != started {
                let current = loadCompare()
                for name in Set(landed.records.keys).union(started.records.keys) where landed.records[name] != started.records[name] {
                    if let copy = current.copies[name] { file.copies[name] = copy }
                }
            }
            try write(file, to: paths.compare)
            let records = loadUpdateRecords()
            let kept = records.kept(for: skills)
            if kept != records { try write(kept, to: paths.updateRecords) }
        }
        return file
    }

    public func loadUpdateRecords() -> UpdateRecords {
        (try? read(UpdateRecords.self, from: paths.updateRecords)) ?? UpdateRecords()
    }

    /// Each compared skill's state from its files on disk now, against the last check. No
    /// network, and off the actor: it reads every file of every recorded skill.
    @concurrent
    public nonisolated func copyStates(of skills: [Skill], compare: CompareFile) async -> [String: CopyState] {
        await inspect(skills, compare: compare, shared: nil).states
    }

    /// One pass over every skill's files: its state against the last comparison, the shared
    /// corrections that match it (findings, and when an identical copy was checked whole), and the
    /// fingerprint of its files now, for skills read. Reads each folder once; no network; off the actor.
    @concurrent
    public nonisolated func inspect(_ skills: [Skill], compare: CompareFile, shared: SharedCorrections?) async
        -> (states: [String: CopyState], sharedFindings: [Finding], checked: [String: Date], trees: [String: String]) {
        var states: [String: CopyState] = [:]
        var findings: [Finding] = []
        var checked: [String: Date] = [:]
        var trees: [String: String] = [:]
        for skill in skills {
            let recorded = skill.origin.flatMap { origin in
                compare.copies[skill.name].flatMap { $0.repo == origin.repo && $0.subpath == origin.subpath ? $0 : nil }
            }
            guard recorded != nil || shared != nil else { continue }
            let files = LocalCopy.files(in: skill.folder)
            trees[skill.name] = SharedCorrections.tree(of: files)
            if let recorded { states[skill.name] = recorded.state(local: files) }
            if let shared {
                let match = shared.matches(skill: skill, files: files)
                findings += match.findings
                if let on = match.checkedOn { checked[skill.name] = on }
            }
        }
        return (states, findings, checked, trees)
    }

    // MARK: Updating copies (flow G)

    /// What updating this copy would change, by blob id, from the last comparison and the files on
    /// disk now; nil when it isn't a copy Skill Health would update. No network: the plugin's tool checks
    /// a prepared update against this before writing it, so what is written is what GitHub listed.
    public nonisolated func sourceDelta(for skill: Skill, compare: CompareFile) -> SourceDelta? {
        guard let origin = skill.origin, let copy = compare.copies[skill.name], let source = copy.source,
              origin.repo == copy.repo, origin.subpath == copy.subpath else { return nil }
        let local = LocalCopy.files(in: skill.folder)
        guard local == copy.installed, local != source else { return nil }
        var changes: [String: SourceDelta.Blobs] = [:]
        for path in Set(local.keys).union(source.keys) where local[path] != source[path] {
            changes[path] = .init(before: local[path], after: source[path])
        }
        return SourceDelta(repo: copy.repo, commit: copy.head, changes: changes)
    }

    /// What would bring each given copy up to its source, with every new file downloaded and
    /// checked against the id GitHub listed. Only copies that are behind and unchanged since
    /// install qualify; anything else is left out. Nothing is written.
    public func prepareUpdates(for skills: [Skill], host: any SourceHost = GitHubSource()) async throws(SkillHealthError) -> [CopyUpdate] {
        let compare = loadCompare()
        var updates: [CopyUpdate] = []
        for skill in skills {
            guard let origin = skill.origin, let copy = compare.copies[skill.name], let source = copy.source,
                  origin.repo == copy.repo, origin.subpath == copy.subpath else { continue }
            let local = LocalCopy.files(in: skill.folder)
            guard local == copy.installed, local != source else { continue }
            var changes: [FileChange] = []
            for path in Set(local.keys).union(source.keys).sorted() where local[path] != source[path] {
                let file = try Self.inside(skill.folder, path)
                let before = local[path] == nil ? nil : try? Data(contentsOf: file)
                var after: Data?
                if let blob = source[path] {
                    let remote = copy.subpath.split(separator: "/").map(String.init) + [path]
                    let data = try await host.contents(of: copy.repo, at: copy.head, path: remote.joined(separator: "/"))
                    guard GitBlob.id(of: data) == blob else { throw .downloadMismatch(path) }
                    after = data
                }
                let kind: FileChange.Kind = before == nil ? .added : after == nil ? .removed : .changed
                let executable = after == nil ? nil : copy.sourceExecutables.map { $0.contains(path) }
                changes.append(FileChange(path: path, kind: kind, before: before, after: after, executable: executable))
            }
            updates.append(CopyUpdate(skill: skill.name, folder: skill.folder, origin: origin, repo: copy.repo,
                                      commit: copy.head, changes: changes, historyURL: copy.historyURL))
        }
        return updates
    }

    /// Writes the updates the person agreed to, after seeing every change. Per skill it is all or
    /// nothing: if any file differs from what was reviewed, that skill is skipped untouched.
    /// Order: check everything, back up what will be replaced or removed (with its mode), remove,
    /// then write; removing first lets a rename that only changes case (Skill.md to SKILL.md) work
    /// on a case-insensitive disk. A failed write puts the skill back and says if that failed too.
    /// Each skill's record is saved the moment its files land, from what was actually written.
    public func applyUpdates(_ updates: [CopyUpdate], now: Date = .now) -> UpdateOutcome {
        do {
            return try locked { applyUpdatesLocked(updates, now: now) }
        } catch {
            var outcome = UpdateOutcome()
            let why = (error as? SkillHealthError)?.plainDescription ?? error.localizedDescription
            for update in updates { outcome.skipped[update.skill] = why }
            return outcome
        }
    }

    private func applyUpdatesLocked(_ updates: [CopyUpdate], now: Date) -> UpdateOutcome {
        var outcome = UpdateOutcome()
        var compare = loadCompare()
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)).replacing(":", with: "-")
        let fm = FileManager.default
        for update in updates {
            let backup = paths.backups.appending(path: update.skill).appending(path: "\(stamp)-update")
            do {
                // A skill folder that links somewhere outside the skills folder isn't Skill Health's to
                // write, the same rule as a patch (Engine.writable).
                let root = paths.skills.resolvingSymlinksInPath().pathComponents
                let resolvedFolder = update.folder.resolvingSymlinksInPath().pathComponents
                guard resolvedFolder.count > root.count, Array(resolvedFolder.prefix(root.count)) == root else {
                    throw SkillHealthError.notInsideSkills(update.folder)
                }
                // Everything checked before anything is touched. A file that is new here may only
                // occupy its path already if it's the same file (by case) that this update removes.
                let removing = Dictionary(update.changes.filter { $0.after == nil }.map { ($0.path.lowercased(), $0.before) },
                                          uniquingKeysWith: { first, _ in first })
                for change in update.changes {
                    let onDisk = try? Data(contentsOf: Self.inside(update.folder, change.path))
                    if change.before == nil {
                        guard onDisk == nil || (change.after != nil && removing[change.path.lowercased()].map({ $0 == onDisk }) == true) else {
                            throw SkillHealthError.copyChangedSinceReview(update.skill)
                        }
                    } else {
                        guard onDisk == change.before else { throw SkillHealthError.copyChangedSinceReview(update.skill) }
                    }
                }
                var saved: [(file: URL, backup: URL, permissions: Int?)] = []
                var written: [URL] = []
                var removed: [URL] = []
                do {
                    for change in update.changes where change.before != nil {
                        let file = try Self.inside(update.folder, change.path)
                        let permissions = (try? fm.attributesOfItem(atPath: file.path(percentEncoded: false)))?[.posixPermissions] as? Int
                        let copy = change.path.split(separator: "/").reduce(backup) { $0.appending(path: String($1)) }
                        try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try change.before!.write(to: copy, options: .atomic)
                        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: copy.path(percentEncoded: false)) }
                        saved.append((file, copy, permissions))
                    }
                    for change in update.changes where change.after == nil {
                        let file = try Self.inside(update.folder, change.path)
                        try fm.removeItem(at: file)
                        removed.append(file)
                    }
                    for change in update.changes {
                        guard let after = change.after else { continue }
                        let file = try Self.inside(update.folder, change.path)
                        let kept = saved.first { $0.file == file }?.permissions ?? 0o644
                        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try after.write(to: file, options: .atomic)
                        written.append(file)
                        // The source's executable bit when known; otherwise the file keeps its mode.
                        let mode = change.executable.map { $0 ? kept | 0o111 : kept & ~0o111 } ?? kept
                        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path(percentEncoded: false))
                    }
                } catch {
                    // Put back what was written or removed, and say plainly if that failed too. A
                    // file this update never touched is left alone, and so is one that already holds
                    // its backup's bytes: rewriting either could only fail for nothing.
                    var unrestored: [String] = []
                    for file in written where !saved.contains(where: { $0.file == file }) {
                        do { try fm.removeItem(at: file) } catch { unrestored.append(file.lastPathComponent) }
                    }
                    for entry in saved where written.contains(entry.file) || removed.contains(entry.file) {
                        if let now = try? Data(contentsOf: entry.file), let was = try? Data(contentsOf: entry.backup),
                           GitBlob.id(of: now) == GitBlob.id(of: was) { continue }
                        do {
                            try fm.createDirectory(at: entry.file.deletingLastPathComponent(), withIntermediateDirectories: true)
                            if fm.fileExists(atPath: entry.file.path(percentEncoded: false)) { try fm.removeItem(at: entry.file) }
                            try fm.copyItem(at: entry.backup, to: entry.file)
                        } catch {
                            unrestored.append(entry.file.lastPathComponent)
                        }
                    }
                    if !unrestored.isEmpty {
                        outcome.damaged[update.skill] = "Partly updated, and \(unrestored.joined(separator: ", ")) couldn't be put back. The originals are in \(backup.path(percentEncoded: false))."
                        if !saved.isEmpty { outcome.backups = paths.backups }
                        continue
                    }
                    throw error
                }
                if !saved.isEmpty { outcome.backups = paths.backups }
                // What undo needs, beside the backups: every file's blob and mode before and after,
                // and the record this update replaces. Not critical to the update itself, so a
                // failure only means this update can't be undone by Skill Health.
                var records = loadUpdateRecords()
                let manifest = UpdateManifest(
                    skill: update.skill, folder: update.folder.path(percentEncoded: false), repo: update.repo,
                    toCommit: update.commit, updatedAt: now, previousRecord: records.records[update.skill],
                    previousInstalledFrom: compare.copies[update.skill]?.installedFrom,
                    files: update.changes.map { change in
                        let file = try? Self.inside(update.folder, change.path)
                        let mode = file.flatMap { (try? fm.attributesOfItem(atPath: $0.path(percentEncoded: false)))?[.posixPermissions] as? Int }
                        return .init(path: change.path, kind: change.kind,
                                     before: change.before.map(GitBlob.id(of:)), after: change.after.map(GitBlob.id(of:)),
                                     beforeMode: saved.first { $0.file == file }?.permissions, afterMode: change.after == nil ? nil : mode)
                    })
                do {
                    try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                    try encoder.encode(manifest).write(to: backup.appending(path: UpdateManifest.fileName), options: .atomic)
                } catch {
                    outcome.damaged[update.skill] = "Updated, but Skill Health couldn't save what would undo it: \(error.localizedDescription)"
                }
                // The record, at once and in its own file: what this copy came from now.
                records.records[update.skill] = .init(repo: update.repo, subpath: update.origin.subpath,
                                                      installedAt: update.origin.installedAt, commit: update.commit, updatedAt: now)
                do { try write(records, to: paths.updateRecords) } catch {
                    outcome.damaged[update.skill] = "Updated, but Skill Health couldn't record it, so a later check may show it as changed on this Mac: \(error.localizedDescription)"
                }
                // The copy's listing, from the files actually written, not from a newer check.
                if var copy = compare.copies[update.skill] {
                    copy.installedFrom = update.commit
                    copy.installed = LocalCopy.files(in: update.folder)
                    compare.copies[update.skill] = copy
                }
                outcome.updated.append(update.skill)
            } catch let error as SkillHealthError {
                outcome.skipped[update.skill] = error.plainDescription
            } catch {
                outcome.skipped[update.skill] = error.localizedDescription
            }
        }
        // Not critical: the records are already saved, and the next check rebuilds this.
        if !outcome.updated.isEmpty { try? write(compare, to: paths.compare) }
        return outcome
    }

    /// A path from a source's listing, made safe to write: no empty, "." or ".." parts, no part
    /// with a character that doesn't show on screen (a name the person couldn't read in a prompt),
    /// inside the skill folder, and never through a link (the file itself or any folder on the way).
    public static func inside(_ folder: URL, _ path: String) throws(SkillHealthError) -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw .unsafePath(path) }
        guard !parts.contains(where: { HiddenText.contains(String($0)) }) else { throw .hiddenInPath(path) }
        var url = folder
        for part in parts {
            url = url.appending(path: String(part))
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw .unsafePath(path) }
        }
        return url
    }

    // MARK: Undoing an update

    /// Every update Skill Health can still undo, most recent first: each backup folder holding a
    /// manifest that hasn't been undone.
    public nonisolated func updateManifests() -> [(folder: URL, manifest: UpdateManifest)] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [(URL, UpdateManifest)] = []
        for skill in (try? fm.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)) ?? [] {
            for run in (try? fm.contentsOfDirectory(at: skill, includingPropertiesForKeys: nil)) ?? [] {
                let file = run.appending(path: UpdateManifest.fileName)
                guard let data = try? Data(contentsOf: file), let manifest = try? decoder.decode(UpdateManifest.self, from: data) else { continue }
                found.append((run, manifest))
            }
        }
        return found.sorted { $0.1.updatedAt > $1.1.updatedAt }
    }

    /// Update backups whose undo record is there but can't be read: an update that can't be undone,
    /// which a list of what can be undone must say rather than leave out.
    public nonisolated func unreadableUpdateManifests() -> [URL] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var unreadable: [URL] = []
        for skill in (try? fm.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)) ?? [] {
            for run in (try? fm.contentsOfDirectory(at: skill, includingPropertiesForKeys: nil)) ?? [] {
                let file = run.appending(path: UpdateManifest.fileName)
                guard fm.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
                if (try? Data(contentsOf: file)).flatMap({ try? decoder.decode(UpdateManifest.self, from: $0) }) == nil {
                    unreadable.append(run)
                }
            }
        }
        return unreadable.sorted { $0.path < $1.path }
    }

    /// Puts a skill back as it was before an update: removes the files the update added, restores
    /// the ones it replaced or removed (with their modes) from the backup, and restores the update
    /// record it replaced. All or nothing, and only if every file is still exactly as the update
    /// left it and every backup is intact: otherwise nothing is touched. If the record can't be
    /// saved after the files went back, the update's files go back too, so the skill never sits
    /// restored under records that say it is updated.
    public func undoUpdate(at backup: URL, now: Date = .now) throws {
        try locked {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // The backup is one of Skill Health's own, and the skill folder it names is inside the skills
            // folder, the same rule as writing an update: a manifest can't send an undo elsewhere.
            let backups = paths.backups.resolvingSymlinksInPath().pathComponents
            let resolvedBackup = backup.resolvingSymlinksInPath().pathComponents
            guard resolvedBackup.count == backups.count + 2, Array(resolvedBackup.prefix(backups.count)) == backups else {
                throw SkillHealthError.backupMissing(backup.lastPathComponent)
            }
            let manifest = try decoder.decode(UpdateManifest.self, from: Data(contentsOf: backup.appending(path: UpdateManifest.fileName)))
            let folder = URL(filePath: manifest.folder)
            let root = paths.skills.resolvingSymlinksInPath().pathComponents
            let resolvedFolder = folder.resolvingSymlinksInPath().pathComponents
            guard resolvedFolder.count > root.count, Array(resolvedFolder.prefix(root.count)) == root else {
                throw SkillHealthError.notInsideSkills(folder)
            }
            // And it is that skill's own folder, skills/<skill>: not another skill's, not one inside it.
            guard folder.lastPathComponent == manifest.skill,
                  folder.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents == root else {
                throw SkillHealthError.undoRecordInvalid("the folder it names isn't \(manifest.skill)'s own")
            }
            let fm = FileManager.default
            // Check everything first.
            var restores: [(file: URL, data: Data, mode: Int?)] = []
            var deletions: [URL] = []
            var current: [(file: URL, data: Data, mode: Int?)] = []
            for entry in manifest.files {
                guard entry.kind == FileChange.Kind(before: entry.before, after: entry.after) else {
                    throw SkillHealthError.undoRecordInvalid("\(entry.path) is listed as \(entry.kind.rawValue), which its copies before and after don't say")
                }
                let file = try Self.inside(folder, entry.path)
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: file.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue {
                    throw SkillHealthError.changedSinceUpdate(manifest.skill)
                }
                let onDisk = try? Data(contentsOf: file)
                guard onDisk.map(GitBlob.id(of:)) == entry.after else { throw SkillHealthError.changedSinceUpdate(manifest.skill) }
                if let onDisk {
                    let mode = (try? fm.attributesOfItem(atPath: file.path(percentEncoded: false)))?[.posixPermissions] as? Int
                    current.append((file, onDisk, mode))
                }
                if let before = entry.before {
                    let saved = entry.path.split(separator: "/").reduce(backup) { $0.appending(path: String($1)) }
                    guard let data = try? Data(contentsOf: saved), GitBlob.id(of: data) == before else {
                        throw SkillHealthError.backupMissing(entry.path)
                    }
                    restores.append((file, data, entry.beforeMode))
                } else {
                    deletions.append(file)
                }
            }
            /// The update's own files again, as they were; false if any couldn't be.
            func putUpdateBack() -> Bool {
                var whole = true
                for (file, data, mode) in current {
                    do {
                        try data.write(to: file, options: .atomic)
                        if let mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path(percentEncoded: false)) }
                    } catch { whole = false }
                }
                for restore in restores where !current.contains(where: { $0.file == restore.file }) {
                    if fm.fileExists(atPath: restore.file.path(percentEncoded: false)) {
                        do { try fm.removeItem(at: restore.file) } catch { whole = false }
                    }
                }
                return whole
            }
            // Then write, putting the update's files back if anything fails part way.
            do {
                for file in deletions { try fm.removeItem(at: file) }
                for restore in restores {
                    try fm.createDirectory(at: restore.file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try restore.data.write(to: restore.file, options: .atomic)
                    if let mode = restore.mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: restore.file.path(percentEncoded: false)) }
                }
            } catch {
                _ = putUpdateBack()
                throw error
            }
            var records = loadUpdateRecords()
            records.records[manifest.skill] = manifest.previousRecord
            do { try write(records, to: paths.updateRecords) } catch {
                let why = (error as? SkillHealthError)?.plainDescription ?? error.localizedDescription
                throw putUpdateBack() ? SkillHealthError.undoNotRecorded(skill: manifest.skill, why: why)
                    : SkillHealthError.undoChangedNotRecorded(skill: manifest.skill, why: why)
            }
            var compare = loadCompare()
            if var copy = compare.copies[manifest.skill] {
                copy.installedFrom = manifest.previousInstalledFrom ?? manifest.previousRecord?.commit ?? copy.installedFrom
                copy.installed = LocalCopy.files(in: folder)
                compare.copies[manifest.skill] = copy
                try? write(compare, to: paths.compare)
            }
            // Not offered again.
            try? fm.moveItem(at: backup.appending(path: UpdateManifest.fileName), to: backup.appending(path: ".manifest-undone.json"))
        }
    }

    // MARK: Deciding a finding (flow F, M4)

    /// No file is no decisions. A file that can't be read throws, so nothing writes over it: it
    /// holds every set-aside date and every patch's undo record.
    public func loadDecisions() throws(SkillHealthError) -> DecisionsFile {
        do { return try read(DecisionsFile.self, from: paths.decisions) ?? DecisionsFile() } catch {
            throw .decisionsUnreadable(ProblemText.reason(error))
        }
    }

    /// Records the person's decision on a finding. Read, change, write in one step on the actor.
    public func record(_ decision: Decision?, for finding: Finding.ID) throws {
        try locked {
            var file = try loadDecisions()
            file[finding] = decision
            try write(file, to: paths.decisions)
        }
    }

    /// The change that replaces the finding's quote with the audit's suggested text, or with
    /// `replacement` (a line Claude proposed for a finding that has none). The quote must appear
    /// exactly once in its file: otherwise there's no telling which one is meant. Nothing is
    /// written; the person sees `diff` and approves it first.
    public func proposePatch(for finding: Finding, in skill: Skill, replacement: String? = nil) throws(SkillHealthError) -> ProposedWrite {
        guard let suggested = replacement ?? finding.suggestedText else { throw .noSuggestedText }
        // The same rules whichever way the text arrived, and the same ones apply checks again.
        try QuotePatch.check(suggested, quote: finding.skillSays)
        let file = try Self.inside(skill.folder, finding.filePath)
        // The same guards as writing, before a diff is shown that could never be written.
        do { _ = try writable(file) } catch let error as SkillHealthError { throw error } catch {
            throw .fileUnreadable(finding.filePath)
        }
        guard let data = try? Data(contentsOf: file), let text = SkillText.exact(data) else {
            throw .fileUnreadable(finding.filePath)
        }
        let range = try QuotePatch.locate(finding.skillSays, in: text, file: finding.filePath)
        return ProposedWrite(file: file, before: text, after: QuotePatch.replacing(range, in: text, with: suggested))
    }

    /// Writes an approved patch (backed up first, through `apply`) and records it, with what undo
    /// needs to put the file back byte for byte.
    @discardableResult
    public func patch(_ write: ReviewedWrite, finding: Finding, now: Date = .now) throws -> Decision {
        try locked {
            // Decisions are read before the skill is touched: if that file can't be read, nothing is
            // written, rather than a patched skill with no record to undo it by.
            let reportedAt = try loadDecisions()[finding.id]?.reportedAt
            let backup = try apply(write, now: now)
            let record = PatchRecord(file: write.proposal.file.path(percentEncoded: false), backup: backup.path(percentEncoded: false),
                                     original: GitBlob.id(of: Data(write.proposal.before.utf8)),
                                     written: GitBlob.id(of: Data(write.proposal.after.utf8)))
            let decision = Decision(status: .patched(on: now), decidedAt: now, patch: record, reportedAt: reportedAt)
            // A fix with no record can't be undone or seen as done, so if the record can't be saved
            // the file goes back as it was, and the person hears which of the two happened.
            do { try self.record(decision, for: finding.id) } catch let recordError {
                let why = (recordError as? SkillHealthError)?.plainDescription ?? recordError.localizedDescription
                let file = write.proposal.file
                do { try Data(write.proposal.before.utf8).write(to: file, options: .atomic) } catch {
                    throw SkillHealthError.changedNotRecorded(file: file.lastPathComponent, backup: backup.path(percentEncoded: false), why: why)
                }
                throw SkillHealthError.notRecorded(file: file.lastPathComponent, why: why)
            }
            return decision
        }
    }

    /// Puts a patched file back exactly as it was, and reopens the finding. Refuses if the file
    /// changed after the patch, since restoring would lose that change.
    public func undoPatch(of finding: Finding) throws {
        try undoPatch(finding: finding.id)
    }

    /// The same, from the decision record alone: the finding itself may be gone, replaced when
    /// its skill was checked again, and its fix can still be put back.
    public func undoPatch(finding id: Finding.ID) throws {
        try locked { try undoPatchLocked(id) }
    }

    private func undoPatchLocked(_ id: Finding.ID) throws {
        guard let decision = try loadDecisions()[id], let patch = decision.patch else { throw SkillHealthError.nothingToUndo }
        let file = URL(filePath: patch.file)
        // The recorded path is checked like any write: inside the skills folder, never a link.
        _ = try writable(file)
        let current = try Data(contentsOf: file)
        guard GitBlob.id(of: current) == patch.written else { throw SkillHealthError.changedSincePatch(file.lastPathComponent) }
        guard let original = try? Data(contentsOf: URL(filePath: patch.backup)), GitBlob.id(of: original) == patch.original else {
            throw SkillHealthError.backupMissing(file.lastPathComponent)
        }
        try original.write(to: file, options: .atomic)
        do { try record(Decision(status: .open, decidedAt: .now, reportedAt: decision.reportedAt), for: id) } catch let recordError {
            let why = (recordError as? SkillHealthError)?.plainDescription ?? recordError.localizedDescription
            do { try current.write(to: file, options: .atomic) } catch {
                throw SkillHealthError.changedNotRecorded(file: file.lastPathComponent, backup: patch.backup, why: why)
            }
            throw SkillHealthError.notRecorded(file: file.lastPathComponent, why: why)
        }
    }

    // MARK: Audits (M5)

    /// What /skill-health:audit offers to check, for the skill in Claude Code to ask with. Rewritten
    /// with status.json, so its usage and sizes are as current as the app's.
    public func writeAuditPlan(skills: [Skill], audited: [String: Date], now: Date = .now) throws {
        try write(AuditPlanFile.make(skills: skills, audited: audited, skillsFolder: paths.skills, now: now), to: paths.auditPlan)
    }

    /// Saves an audit run from the app, under the same rules as the plugin's save script. A broken
    /// findings.json is left alone, never written over. So is one with entries this version can't
    /// read: they decode to nothing, so writing back what was read would drop other skills' findings
    /// (the shell script keeps them as raw JSON; this can't).
    public func save(_ results: AuditResults, now: Date = .now) throws {
        if let problem = results.problem { throw SkillHealthError.auditRejected(problem) }
        try locked {
            let previous: FindingsFile
            do { previous = try loadFindings() } catch {
                throw SkillHealthError.findingsUnreadable((error as? SkillHealthError)?.plainDescription ?? error.localizedDescription)
            }
            if previous.unreadable > 0 { throw SkillHealthError.auditRejected(AuditResults.unreadableEntriesProblem(previous.unreadable)) }
            try write(results.merged(into: previous, now: now, trees: trees(of: results.audited)), to: paths.findings)
        }
    }

    /// The fingerprint of each named skill's files as they are now, for a check being saved: the
    /// files the auditor just read. Skills whose folder isn't found get none.
    func trees(of names: [String]) -> [String: String] {
        let folders = Dictionary(((try? discoverSkills()) ?? []).map { ($0.name, $0.folder) }, uniquingKeysWith: { first, _ in first })
        var trees: [String: String] = [:]
        for name in Set(names) {
            guard let folder = folders[name] else { continue }
            trees[name] = SharedCorrections.tree(of: LocalCopy.files(in: folder))
        }
        return trees
    }

    /// When findings.json was last written, to notice an audit's results arriving.
    public nonisolated func findingsWrittenAt() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: paths.findings.path(percentEncoded: false)))?[.modificationDate] as? Date
    }

    // MARK: Helpers

    /// Runs `body` holding the cross-process write lock (FileLock), so the app and the plugin's
    /// command-line tool never lose each other's read-modify-write of findings, decisions, update
    /// records or the compare file.
    func locked<T>(_ body: () throws -> T) throws -> T {
        if lockDepth > 0 {
            lockDepth += 1
            defer { lockDepth -= 1 }
            return try body()
        }
        let lock = FileLock(directory: paths.lock)
        try lock.acquire()
        lockDepth = 1
        defer {
            lockDepth = 0
            lock.release()
        }
        return try body()
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
