import Foundation

/// ~/.claude/skill-health/compare.json: what each skill's source held when last checked. Keeping the
/// installed and current file lists per skill lets Skill Health classify every copy again on each
/// refresh without the network, so an edit made on this Mac shows at once.
public struct CompareFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public struct Source: Codable, Sendable, Equatable {
        public var branch: String?
        /// The commit compared against at the last successful check.
        public var head: String?
        public var checkedAt: Date?
        /// Why the last attempt couldn't read this source, in words; nil when it could.
        public var problem: String?
        /// Install time (ISO 8601, the start of a batch of installs) to the commit that install
        /// took. Found once and kept: history before a date doesn't change.
        public var installs: [String: String] = [:]

        public init() {}
    }

    /// One skill's copy as of the last check: exactly which version was installed, and both file
    /// lists, path to git blob id.
    public struct Copy: Codable, Sendable, Equatable {
        public var repo: String
        public var subpath: String
        public var installedFrom: String
        public var head: String
        public var installed: [String: String]
        /// Nil when the source no longer has the skill.
        public var source: [String: String]?
        /// Which of the source's files are executable, so an update keeps scripts runnable. Nil in
        /// a file written before modes were kept: an update then leaves each file's mode as it is.
        public var sourceExecutables: Set<String>?

        public init(repo: String, subpath: String, installedFrom: String, head: String,
                    installed: [String: String], source: [String: String]?, sourceExecutables: Set<String>? = nil) {
            self.repo = repo
            self.subpath = subpath
            self.installedFrom = installedFrom
            self.head = head
            self.installed = installed
            self.source = source
            self.sourceExecutables = sourceExecutables
        }

        /// The source's history for this skill's folder, for a person to read what changed.
        public var historyURL: URL? {
            let path = subpath.isEmpty ? "" : "/" + subpath
            return URL(string: "https://github.com/\(repo)/commits/\(head)\(path)")
        }

        /// How the copy on disk relates to the source, from its files now.
        public func state(local: [String: String]) -> CopyState {
            guard let source else { return .removedAtSource }
            if local == source { return .current }
            if local == installed { return .behind }
            if source == installed { return .changedHere }
            return .changedBoth
        }
    }

    public var version = CompareFile.currentVersion
    /// When the last check finished, even partly.
    public var checkedAt: Date?
    /// Set when a check stopped early, for example at GitHub's hourly limit.
    public var stopped: String?
    public var sources: [String: Source] = [:]
    public var copies: [String: Copy] = [:]

    public init() {}
}
