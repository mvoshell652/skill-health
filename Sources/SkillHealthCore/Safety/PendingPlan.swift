import Foundation

/// A change the plugin's tool has prepared and shown, waiting for the person's approval:
/// ~/.claude/skill-health/pending/<id>.json, plus pending/<id>/ for an update's downloaded files.
/// `summary` is what the plugin's gate hook puts in Claude Code's permission prompt, so the
/// person approves the exact change, not the model's say-so. A plan is used once, and only
/// within 15 minutes of being prepared; apply re-checks that nothing changed since.
public struct PendingPlan: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case fix, update, undo }

    public struct Fix: Codable, Sendable, Equatable {
        public let finding: UUID
        public let skill: String
        /// Absolute path of the file, and its git blob id when previewed.
        public let file: String
        public let before: String
        public let after: String

        public init(finding: UUID, skill: String, file: String, before: String, after: String) {
            self.finding = finding
            self.skill = skill
            self.file = file
            self.before = before
            self.after = after
        }
    }

    public struct Update: Codable, Sendable, Equatable {
        public struct Change: Codable, Sendable, Equatable {
            public let path: String
            public let kind: FileChange.Kind
            /// The blob id this Mac's copy had when previewed; nil for a file the update adds.
            public let before: String?
            /// The blob id the source lists, which the staged download was checked against; nil when removed.
            public let after: String?
            /// Where the downloaded file is staged, relative to pending/<id>/; nil when removed.
            public let staged: String?
            public let executable: Bool?

            public init(path: String, kind: FileChange.Kind, before: String?, after: String?, staged: String?, executable: Bool?) {
                self.path = path
                self.kind = kind
                self.before = before
                self.after = after
                self.staged = staged
                self.executable = executable
            }
        }
        public struct Skill: Codable, Sendable, Equatable {
            public let skill: String
            public let folder: String
            public let origin: Origin
            public let repo: String
            public let commit: String
            public let historyURL: URL?
            public let changes: [Change]

            public init(skill: String, folder: String, origin: Origin, repo: String, commit: String, historyURL: URL?, changes: [Change]) {
                self.skill = skill
                self.folder = folder
                self.origin = origin
                self.repo = repo
                self.commit = commit
                self.historyURL = historyURL
                self.changes = changes
            }
        }
        public let skills: [Skill]

        public init(skills: [Skill]) { self.skills = skills }
    }

    public struct Undo: Codable, Sendable, Equatable {
        /// Undo a fix: the finding whose patch is put back.
        public let finding: UUID?
        /// Undo an update: the backup folder holding its manifest.
        public let backup: String?
        public let skill: String

        public init(finding: UUID?, backup: String?, skill: String) {
            self.finding = finding
            self.backup = backup
            self.skill = skill
        }
    }

    public var schema = 1
    public let id: UUID
    public let kind: Kind
    public let createdAt: Date
    public let expiresAt: Date
    public var used = false
    public let summary: String
    public var fix: Fix?
    public var update: Update?
    public var undo: Undo?

    public static let lifetime: TimeInterval = 15 * 60
    /// The approval prompt's text stays readable: anything longer is cut, and says so. Counted in
    /// unicode scalars, because that is how the gate hook (jq) cuts the summary: a plan over this
    /// many would be cut there, behind the person's back.
    public static let summaryLimit = 3_000

    private static let cutNote = "\n… (cut short here; the full change was shown above)"

    /// The summary as the prompt shows it. Apply rebuilds the summary from what it is about to
    /// write and compares the two, so a plan whose data was changed after the preview is refused.
    public static func fitted(_ summary: String) -> String {
        let scalars = summary.unicodeScalars
        guard scalars.count > summaryLimit else { return summary }
        return String(String.UnicodeScalarView(scalars.prefix(summaryLimit - cutNote.unicodeScalars.count))) + cutNote
    }

    public init(id: UUID = UUID(), kind: Kind, createdAt: Date = .now, summary: String,
                fix: Fix? = nil, update: Update? = nil, undo: Undo? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(Self.lifetime)
        self.summary = Self.fitted(summary)
        self.fix = fix
        self.update = update
        self.undo = undo
    }
}

/// Reading and writing plans. Old plans (a day past their expiry) are swept when a new one is made.
public struct PlanStore: Sendable {
    public let folder: URL
    /// How a plan's bytes reach the disk; a test swaps it to make saving fail.
    let writer: @Sendable (Data, URL) throws -> Void

    public init(paths: SkillHealthPaths) {
        self.init(folder: paths.pending) { try $0.write(to: $1, options: .atomic) }
    }

    init(folder: URL, writer: @escaping @Sendable (Data, URL) throws -> Void) {
        self.folder = folder
        self.writer = writer
    }

    public func url(for id: UUID) -> URL { folder.appending(path: "\(id.uuidString).json") }
    public func staging(for id: UUID) -> URL { folder.appending(path: id.uuidString) }

    public func save(_ plan: PendingPlan) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sweep(now: plan.createdAt)
        try writer(Self.encoder.encode(plan), url(for: plan.id))
    }

    /// The plan, if it can still be applied now. The file must be exactly what the tool writes
    /// (sorted keys, pretty printed): a file with a key twice, say, is read one way by the gate
    /// (jq takes the last) and another by this decoder (the first), so what the prompt shows
    /// wouldn't be what is applied. And it must be the plan it is filed under.
    public func ready(_ id: UUID, kind: PendingPlan.Kind, now: Date = .now) throws(SkillHealthError) -> PendingPlan {
        guard let data = try? Data(contentsOf: url(for: id)), let plan = try? Self.decoder.decode(PendingPlan.self, from: data),
              plan.kind == kind else { throw .planNotFound }
        guard plan.id == id, (try? Self.encoder.encode(plan)) == data else { throw .planAltered }
        guard !plan.used else { throw .planUsed }
        guard now < plan.expiresAt else { throw .planExpired }
        return plan
    }

    /// Marked used once the change is written, so a failed or refused apply can run again. A plan
    /// can't write twice either way: every apply first checks the bytes it replaces.
    public func markUsed(_ plan: PendingPlan) throws {
        var used = plan
        used.used = true
        try writer(Self.encoder.encode(used), url(for: plan.id))
    }

    /// Ends a plan whose change was written: marked used, or, when that can't be saved, deleted,
    /// since a plan left usable could write the same change again after an undo. False when
    /// neither worked, and the caller says so.
    @discardableResult
    public func retire(_ plan: PendingPlan) -> Bool {
        do { try markUsed(plan) } catch {
            do { try FileManager.default.removeItem(at: url(for: plan.id)) } catch { return false }
            try? FileManager.default.removeItem(at: staging(for: plan.id))
        }
        return true
    }

    func sweep(now: Date) {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let plan = try? Self.decoder.decode(PendingPlan.self, from: data),
                  now.timeIntervalSince(plan.expiresAt) > 24 * 60 * 60 else { continue }
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: staging(for: plan.id))
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
