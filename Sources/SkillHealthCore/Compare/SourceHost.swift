import Foundation

/// Where skills came from. GitHub today; a protocol so the compare can be tested without the
/// network and so another host can be added without touching the comparison.
public protocol SourceHost: Sendable {
    func defaultBranch(of repo: String) async throws(SkillHealthError) -> String
    func headCommit(of repo: String, branch: String) async throws(SkillHealthError) -> String
    /// The latest commits on the branch dated at or before a moment, newest first: the candidates
    /// for the version an install took. Dates alone can't pick it in a repository that merges
    /// pull requests (a commit can be dated before it reached the branch), so the comparer
    /// chooses among them by content.
    func commits(of repo: String, branch: String, atOrBefore moment: Date, limit: Int) async throws(SkillHealthError) -> [String]
    /// Every file in the repository at a commit.
    func files(of repo: String, at commit: String) async throws(SkillHealthError) -> SourceTree
    /// One file's bytes at a commit. The caller checks them against the listed blob id.
    func contents(of repo: String, at commit: String, path: String) async throws(SkillHealthError) -> Data
}

/// A repository's files at one commit: git blob ids by path, and which of them are executable
/// (mode 100755), so an update keeps a skill's scripts runnable.
public struct SourceTree: Sendable, Equatable {
    public var blobs: [String: String]
    public var executables: Set<String>

    public init(blobs: [String: String], executables: Set<String> = []) {
        self.blobs = blobs
        self.executables = executables
    }
}

/// GitHub's REST API over URLSession: the only network access Skill Health has, and all it sends is
/// the names of the repositories skills came from, and when they were installed. No account is needed; GitHub allows 60
/// requests an hour without one, and a check costs about three per repository.
public struct GitHubSource: SourceHost {
    let session: URLSession
    let api = URL(string: "https://api.github.com")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func defaultBranch(of repo: String) async throws(SkillHealthError) -> String {
        struct Repository: Decodable { let default_branch: String }
        return try await get(Repository.self, repo: repo, path: "").default_branch
    }

    public func headCommit(of repo: String, branch: String) async throws(SkillHealthError) -> String {
        struct Commit: Decodable { let sha: String }
        return try await get(Commit.self, repo: repo, path: "/commits/\(try segment(branch))").sha
    }

    public func commits(of repo: String, branch: String, atOrBefore moment: Date, limit: Int) async throws(SkillHealthError) -> [String] {
        struct Commit: Decodable { let sha: String }
        let until = moment.formatted(.iso8601)
        let commits = try await get([Commit].self, repo: repo, path: "/commits",
                                    query: [URLQueryItem(name: "sha", value: branch),
                                            URLQueryItem(name: "until", value: until),
                                            URLQueryItem(name: "per_page", value: String(limit))])
        return commits.map(\.sha)
    }

    public func files(of repo: String, at commit: String) async throws(SkillHealthError) -> SourceTree {
        struct Tree: Decodable {
            struct Entry: Decodable { let path: String; let type: String; let sha: String; let mode: String }
            let tree: [Entry]
            let truncated: Bool
        }
        let tree = try await get(Tree.self, repo: repo, path: "/git/trees/\(try segment(commit))",
                                 query: [URLQueryItem(name: "recursive", value: "1")])
        // A truncated listing would read as files removed at the source. None of the measured
        // sources comes close (the largest is 12,434 entries); refuse rather than guess.
        guard !tree.truncated else { throw .sourceTooLarge(repo) }
        var files = SourceTree(blobs: [:])
        for entry in tree.tree where entry.type == "blob" {
            files.blobs[entry.path] = entry.sha
            if entry.mode == "100755" { files.executables.insert(entry.path) }
        }
        return files
    }

    /// From raw.githubusercontent.com, which serves a file at a commit without counting against
    /// the API's hourly limit.
    public func contents(of repo: String, at commit: String, path: String) async throws(SkillHealthError) -> Data {
        guard Self.isValidRepo(repo) else { throw .badSource(repo) }
        var segments = [try segment(commit)]
        for part in path.split(separator: "/", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part != ".", part != ".." else { throw .unsafePath(path) }
            segments.append(try segment(String(part)))
        }
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repo)/" + segments.joined(separator: "/")) else {
            throw .unsafePath(path)
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Skill Health", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .offline(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw .offline("no response") }
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw .sourceNotFound(repo)
        case 429: throw .rateLimited(resetAt: nil)
        default: throw .sourceFailed(repo, http.statusCode)
        }
    }

    // MARK: Requests

    /// Receipts are data from the skill folder, so a repository name is checked before it is
    /// put in a URL: owner/name, each part only the characters GitHub allows.
    public static func isValidRepo(_ repo: String) -> Bool {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.count <= 100 && part != "." && part != ".."
                && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
    }

    private func segment(_ value: String) throws(SkillHealthError) -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])),
              !encoded.isEmpty else { throw .badSource(value) }
        return encoded
    }

    private func get<T: Decodable>(_ type: T.Type, repo: String, path: String,
                                   query: [URLQueryItem] = []) async throws(SkillHealthError) -> T {
        guard Self.isValidRepo(repo), var url = URL(string: "\(api.absoluteString)/repos/\(repo)\(path)") else {
            throw .badSource(repo)
        }
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Skill Health", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .offline(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw .offline("no response") }
        switch http.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(type, from: data) } catch { throw .sourceFailed(repo, http.statusCode) }
        case 403, 429:
            // GitHub's hourly limit (remaining 0) and its short-term limit (Retry-After) both
            // mean "later"; any other 403 is a real refusal.
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
                .map { Date.now.addingTimeInterval($0) }
            guard http.statusCode == 429 || retryAfter != nil
                    || http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" else {
                throw .sourceFailed(repo, http.statusCode)
            }
            throw .rateLimited(resetAt: retryAfter ?? reset)
        case 404, 451:
            throw .sourceNotFound(repo)
        default:
            throw .sourceFailed(repo, http.statusCode)
        }
    }
}
