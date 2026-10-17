import Foundation

/// What Skill Health knows about which skills the person loads.
public struct UsageReport: Sendable, Equatable {
    /// Skill folder name to loads within the window, each load counted once.
    public let loads: [String: Int]
    public let windowStart: Date
    /// From when the kept sessions are complete: the last write of the oldest session Claude
    /// Code still keeps. Earlier loads survive only inside sessions that were continued later.
    /// Nil when there are no sessions at all.
    public let completeSince: Date?

    public init(loads: [String: Int], windowStart: Date, completeSince: Date?) {
        self.loads = loads
        self.windowStart = windowStart
        self.completeSince = completeSince
    }

    /// True when the kept sessions reach back over the whole window, so a skill with no loads
    /// really went unused in it. Otherwise the count is a lower bound.
    public var coversWindow: Bool {
        completeSince.map { $0 <= windowStart } ?? false
    }

    public var usedCount: Int { loads.count }

    /// "59 used in the last 90 days", or "at least 59…" when the kept sessions don't reach back
    /// that far; "none used…" for zero, since "at least 0" says nothing. The app and the command
    /// say the same thing. The count is the caller's: the app passes installed skills that were
    /// used, since loads also name skills deleted since.
    public func usedPhrase(count: Int) -> String {
        guard count > 0 else {
            guard let completeSince else { return "none used yet" }
            // Sessions kept for less than 90 days can't say nothing was used before them.
            return coversWindow ? "none used in the last 90 days" : "none used since \(Self.day(completeSince))"
        }
        return "\(coversWindow ? "" : "at least ")\(count.formatted(.number.locale(Self.english))) used in the last 90 days"
    }

    /// In English whatever the Mac's region, like the sentences around it.
    static let english = Locale(identifier: "en_US")
    public static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).day().locale(english))
    }

    /// Why the count is a lower bound, when it is. Dates are local, as people read them.
    public var coverageNote: String? {
        guard !coversWindow else { return nil }
        guard let completeSince else { return "There are no Claude Code sessions in this folder yet." }
        return "Claude Code has kept sessions only since \(Self.day(completeSince)), so earlier use may be missing."
    }
}

/// Counts which skills the person actually loads, from Claude Code's own session files in
/// <claude>/projects, including subagent sessions. Only skill names, line ids and times are
/// kept, on this Mac; nothing is sent. Each file's loads are cached by path, size and
/// modification date, so later reads only open sessions that changed.
///
/// A load is the line Claude Code writes when a skill's instructions enter the session: a
/// user line marked isMeta whose text block begins "Base directory for this skill: <folder>".
/// It is written for a Skill tool call and for a slash command alike, and never for a call
/// that failed. Only a folder directly inside this skills folder is credited, so a playlist
/// group (skills/playlist/skills/x) or a plugin's copy credits nothing on disk.
public struct UsageReader: Sendable {
    public let projects: URL
    public let skills: String
    public let cache: URL
    public let window: TimeInterval

    static let prefix = "Base directory for this skill: "
    static let marker = Data(prefix.utf8)
    /// The two places the marker starts a text block: an element of a content array, or the
    /// whole content string. Anything else (an attachment replaying a skill, a tool result
    /// quoting one) is not a load.
    static let anchors = [Data(#"{"type":"text","text":""#.utf8), Data(#""content":""#.utf8)]

    public init(paths: SkillHealthPaths, window: TimeInterval = 90 * 24 * 60 * 60) {
        projects = paths.claudeHome.appending(path: "projects")
        let skills = paths.skills.path(percentEncoded: false)
        self.skills = skills.hasSuffix("/") ? String(skills.dropLast()) : skills
        cache = paths.home.appending(path: "usage-cache.json")
        self.window = window
    }

    public func read(now: Date = .now) throws -> UsageReport {
        let windowStart = now.addingTimeInterval(-window)
        let fm = FileManager.default
        guard fm.fileExists(atPath: projects.path(percentEncoded: false)) else {
            return UsageReport(loads: [:], windowStart: windowStart, completeSince: nil)
        }
        var previous = (try? JSONDecoder().decode(UsageCache.self, from: Data(contentsOf: cache))) ?? UsageCache()
        if previous.version != UsageCache.currentVersion { previous = UsageCache() }
        var current = UsageCache()
        var oldestSession: Date?
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        // An enumerator over a folder that can't be listed just yields nothing, which would read as
        // "no sessions yet": list it once first, so a permissions problem is said as one.
        _ = try fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
        guard let files = fm.enumerator(at: projects, includingPropertiesForKeys: keys) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSURLErrorKey: projects])
        }
        for case let file as URL in files {
            guard file.pathExtension == "jsonl",
                  let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate else { continue }
            // A session is projects/<project>/<session>.jsonl; subagent sessions sit deeper. The
            // enumerator's own depth, because the path it reports may run through a symlink.
            if files.level == 2 {
                oldestSession = min(oldestSession ?? modified, modified)
            }
            // A file last written before the window can't hold a load inside it.
            guard modified >= windowStart else { continue }
            let key = file.path(percentEncoded: false)
            let size = values.fileSize ?? 0
            if let entry = previous.files.removeValue(forKey: key), entry.size == size, entry.modified == modified {
                current.files[key] = entry
            } else if let loads = loads(in: file) {
                current.files[key] = UsageCache.Entry(size: size, modified: modified, loads: loads.isEmpty ? nil : loads)
            }
            // A file that couldn't be opened isn't cached, so the next read tries it again rather
            // than remembering it as a session without loads.
        }
        try? fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(current).write(to: cache, options: .atomic)

        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for entry in current.files.values {
            for load in entry.loads ?? [] where load.at >= windowStart && seen.insert(load.id).inserted {
                counts[load.skill, default: 0] += 1
            }
        }
        return UsageReport(loads: counts, windowStart: windowStart, completeSince: oldestSession)
    }

    /// The loads in one session file. Scans the mapped bytes for the marker and parses only
    /// the lines that carry it, so a multi-gigabyte history is read once and cheaply.
    /// Nil when the file can't be read: not the same as a session with no loads.
    func loads(in file: URL) -> [UsageCache.Load]? {
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
        let newline = UInt8(ascii: "\n")
        var found: [UsageCache.Load] = []
        var searchFrom = data.startIndex
        while let hit = data.range(of: Self.marker, in: searchFrom..<data.endIndex) {
            searchFrom = hit.upperBound
            guard Self.anchors.contains(where: { anchor in
                hit.lowerBound - anchor.count >= data.startIndex
                    && data[(hit.lowerBound - anchor.count)..<hit.lowerBound].elementsEqual(anchor)
            }) else { continue }
            let lineStart = data[..<hit.lowerBound].lastIndex(of: newline).map { $0 + 1 } ?? data.startIndex
            let lineEnd = data[hit.upperBound...].firstIndex(of: newline) ?? data.endIndex
            if let load = load(fromLine: data[lineStart..<lineEnd]) { found.append(load) }
            // One load per line: carry on after it.
            searchFrom = lineEnd
        }
        return found
    }

    func load(fromLine line: Data) -> UsageCache.Load? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "user", object["isMeta"] as? Bool == true,
              let id = object["uuid"] as? String,
              let stamp = object["timestamp"] as? String, let at = Self.date(stamp),
              let message = object["message"] as? [String: Any],
              let text = Self.skillText(in: message["content"]),
              let skill = skillName(fromBaseDirectory: text) else { return nil }
        return UsageCache.Load(id: id, skill: skill, at: at)
    }

    /// The text block that begins with the marker: the whole string, or one element of the
    /// array (images attached to the same message come before it).
    static func skillText(in content: Any?) -> String? {
        if let string = content as? String { return string.hasPrefix(prefix) ? string : nil }
        guard let blocks = content as? [[String: Any]] else { return nil }
        return blocks.lazy.compactMap { block -> String? in
            guard block["type"] as? String == "text", let text = block["text"] as? String,
                  text.hasPrefix(prefix) else { return nil }
            return text
        }.first
    }

    /// "Base directory for this skill: <skills>/<name>\n…" gives <name>, and only when the folder
    /// sits directly inside this skills folder. Paths can hold spaces, so read to the line end.
    func skillName(fromBaseDirectory text: String) -> String? {
        let path = text.dropFirst(Self.prefix.count).prefix { $0 != "\n" }
        let folder = skills + "/"
        guard path.hasPrefix(folder) else { return nil }
        var name = path.dropFirst(folder.count)
        if name.hasSuffix("/") { name = name.dropLast() }
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return String(name)
    }

    static func date(_ stamp: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp))
            ?? (try? Date.ISO8601FormatStyle().parse(stamp))
    }
}
