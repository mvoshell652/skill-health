import Foundation

/// One writer at a time across processes: the app and the plugin's command-line tool both write
/// ~/.claude/skill-health, and an atomic rename keeps a file whole but doesn't stop one process's
/// read-modify-write from losing another's. The lock is a directory, because mkdir is atomic on
/// every file system and needs no flock(1), which macOS doesn't ship. Inside it, `owner` says who
/// holds it, so a refusal can name them.
///
/// A lock older than ten minutes is treated as left behind by a process that died: no write
/// Skill Health makes takes that long. Waiting is short; a busy lock is an error the caller reports
/// ("try again in a moment"), never a hang.
public struct FileLock: Sendable {
    public let directory: URL
    public let staleAfter: TimeInterval
    public let wait: Duration

    public init(directory: URL, staleAfter: TimeInterval = 600, wait: Duration = .seconds(5)) {
        self.directory = directory
        self.staleAfter = staleAfter
        self.wait = wait
    }

    struct Owner: Codable {
        let pid: Int32
        let process: String
        let since: Date
    }

    /// Takes the lock, waiting up to `wait`; throws `.busy` naming the holder if it can't. Only a
    /// lock that exists means someone else has it: any other reason mkdir fails (a folder Skill Health
    /// can't write to, say) is that reason, said as it is, since waiting never fixes it.
    public func acquire(now: () -> Date = Date.init) throws(SkillHealthError) {
        let fm = FileManager.default
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: wait)
        let folder = directory.deletingLastPathComponent()
        let named = folder.path   // the way a person writes it: no trailing slash
        while true {
            do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                throw .cantLock(folder: named, why: Self.lowercased(error.localizedDescription))
            }
            if mkdir(directory.path(percentEncoded: false), 0o755) == 0 {
                let owner = Owner(pid: getpid(), process: ProcessInfo.processInfo.processName, since: now())
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try? encoder.encode(owner).write(to: directory.appending(path: "owner"))
                return
            }
            let code = errno
            guard code == EEXIST else {
                throw .cantLock(folder: named, why: Self.lowercased(String(cString: strerror(code))))
            }
            // Someone holds it. Take it over only if it was left behind.
            if let since = heldSince(), now().timeIntervalSince(since) > staleAfter {
                try? fm.removeItem(at: directory)
                continue
            }
            guard clock.now < deadline else { throw .busy(holder() ?? "another Skill Health") }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// A system's reason in the middle of a sentence ("Permission denied" becomes "permission denied").
    private static func lowercased(_ reason: String) -> String { reason.prefix(1).lowercased() + reason.dropFirst() }

    public func release() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// When the current holder took it: from its owner file, or the directory's own date when
    /// a holder died before writing one.
    func heldSince() -> Date? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: directory.appending(path: "owner")),
           let owner = try? decoder.decode(Owner.self, from: data) { return owner.since }
        return (try? FileManager.default.attributesOfItem(atPath: directory.path(percentEncoded: false)))?[.creationDate] as? Date
    }

    func holder() -> String? {
        guard let data = try? Data(contentsOf: directory.appending(path: "owner")),
              let owner = try? JSONDecoder().decode(OwnerName.self, from: data) else { return nil }
        switch owner.process {
        case "skill-health": return "the Skill Health command in Claude Code"
        case "SkillHealth", "Skill Health": return "the Skill Health app"
        default: return owner.process
        }
    }

    private struct OwnerName: Decodable { let process: String }
}
