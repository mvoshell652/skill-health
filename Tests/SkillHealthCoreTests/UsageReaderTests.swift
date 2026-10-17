import Foundation
import Testing
@testable import SkillHealthCore

/// Lines in the shapes Claude Code writes them (measured in real sessions, 2026-10-03).
private enum Line {
    static func load(_ uuid: String, _ folder: String, at stamp: String) -> String {
        #"{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: \#(folder)\n\n# Title\n\nBody"}]},"isMeta":true,"uuid":"\#(uuid)","timestamp":"\#(stamp)"}"#
    }
    /// A slash command in a subagent writes the content as a plain string.
    static func loadAsString(_ uuid: String, _ folder: String, at stamp: String) -> String {
        #"{"isSidechain":true,"type":"user","message":{"role":"user","content":"Base directory for this skill: \#(folder)\n\nBody"},"isMeta":true,"uuid":"\#(uuid)","timestamp":"\#(stamp)"}"#
    }
    /// Images attached to the same message come before the skill's text block.
    static func loadAfterImage(_ uuid: String, _ folder: String, at stamp: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AAAA"}},{"type":"text","text":"Base directory for this skill: \#(folder)\n\nBody"}]},"isMeta":true,"uuid":"\#(uuid)","timestamp":"\#(stamp)"}"#
    }
    static func command(_ name: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"<command-name>/\#(name)</command-name>"},"uuid":"c-\#(name)","timestamp":"2026-10-01T10:00:00.000Z"}"#
    }
    /// After compaction Claude Code re-injects loaded skills as an attachment: not a new load.
    static func replayedAttachment(_ folder: String) -> String {
        #"{"type":"attachment","attachment":{"type":"invoked_skills","skills":[{"name":"x","content":"Base directory for this skill: \#(folder)\n\nBody"}]},"uuid":"att","timestamp":"2026-10-01T10:00:00.000Z"}"#
    }
    /// A tool result that quotes a load line (reading a transcript) is not a load either.
    static func quotedInToolResult(_ folder: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t","type":"tool_result","content":[{"type":"text","text":"Base directory for this skill: \#(folder)\n"}]}]},"uuid":"tr","timestamp":"2026-10-01T10:00:00.000Z"}"#
    }
}

@Suite("Usage comes from the lines Claude Code writes when a skill loads")
struct UsageReaderTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-usage-\(UUID().uuidString)")
    var skills: String { home.appending(path: "skills").path(percentEncoded: false) }
    let now = try! Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-10-03T12:00:00.000Z")

    func write(_ lines: [String], to relative: String, modified: Date? = nil) throws {
        let file = home.appending(path: "projects/" + relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified ?? now.addingTimeInterval(-60)],
                                              ofItemAtPath: file.path(percentEncoded: false))
    }

    var reader: UsageReader { UsageReader(paths: SkillHealthPaths(claudeHome: home)) }

    @Test func countsToolLoadsSlashLoadsAndSubagentLoadsOnceEach() throws {
        try write([
            Line.load("u1", "\(skills)/supabase", at: "2026-10-01T10:00:00.000Z"),
            Line.command("gcp-auth"),
            Line.load("u2", "\(skills)/gcp-auth", at: "2026-10-01T10:01:00.000Z"),
            Line.loadAfterImage("u3", "\(skills)/gcloud", at: "2026-10-01T10:02:00.000Z"),
        ], to: "-Users-x-repo/s1.jsonl")
        // A resumed session replays u1 with the same id: one load, not two.
        try write([Line.load("u1", "\(skills)/supabase", at: "2026-10-01T10:00:00.000Z")], to: "-Users-x-repo/s2.jsonl")
        // A subagent's own load is real use.
        try write([Line.loadAsString("u4", "\(skills)/code-simplification", at: "2026-10-02T09:00:00Z")],
                  to: "-Users-x-repo/s1/subagents/workflows/wf_1/agent-a.jsonl")

        let report = try reader.read(now: now)
        #expect(report.loads == ["supabase": 1, "gcp-auth": 1, "gcloud": 1, "code-simplification": 1])
        // A second read comes from the cache and agrees.
        #expect(try reader.read(now: now) == report)
    }

    @Test func creditsOnlyAFolderDirectlyInsideTheSkillsFolder() throws {
        try write([
            // A playlist group never credits its member skills (owner decision, 2026-10-03).
            Line.load("p1", "\(skills)/playlist/skills/db-ops", at: "2026-10-01T10:00:00.000Z"),
            // A plugin's copy, in a path with spaces, credits nothing on disk.
            Line.loadAsString("p2", "/Users/x/Library/Application Support/Claude/skills-plugin/skills/writing", at: "2026-10-01T10:00:00Z"),
            // A project's own skill lives elsewhere too.
            Line.load("p3", "/Users/x/repo/.claude/skills/release-checklist", at: "2026-10-01T10:00:00.000Z"),
            Line.load("p4", "\(skills)/vitest/", at: "2026-10-01T10:00:00.000Z"),
        ], to: "-Users-x-repo/s1.jsonl")
        #expect(try reader.read(now: now).loads == ["vitest": 1])
    }

    @Test func replayedAndQuotedSkillTextIsNotALoad() throws {
        try write([Line.replayedAttachment("\(skills)/framer"), Line.quotedInToolResult("\(skills)/framer")],
                  to: "-Users-x-repo/s1.jsonl")
        #expect(try reader.read(now: now).loads.isEmpty)
    }

    @Test func theWindowAppliesToEachLoadNotToTheFile() throws {
        // Continued last week, but the load in it is 94 days old.
        try write([Line.load("old", "\(skills)/stripe-billing", at: "2026-07-01T10:00:00.000Z"),
                   Line.load("new", "\(skills)/supabase", at: "2026-09-28T10:00:00.000Z")],
                  to: "-Users-x-repo/s1.jsonl", modified: now.addingTimeInterval(-7 * 86_400))
        #expect(try reader.read(now: now).loads == ["supabase": 1])
    }

    @Test func saysHowFarBackTheKeptSessionsReach() throws {
        let oldest = now.addingTimeInterval(-39 * 86_400)
        try write([Line.load("u1", "\(skills)/supabase", at: "2026-09-01T10:00:00.000Z")],
                  to: "-Users-x-repo/s1.jsonl", modified: oldest)
        // A subagent file can't speak for when its session was kept.
        try write([], to: "-Users-x-repo/s1/subagents/agent-a.jsonl", modified: now.addingTimeInterval(-200 * 86_400))
        let report = try reader.read(now: now)
        #expect(report.completeSince == oldest)
        #expect(!report.coversWindow)
        #expect(report.usedPhrase(count: 1) == "at least 1 used in the last 90 days")
        #expect(report.coverageNote != nil)

        try write([], to: "-Users-x-repo/s0.jsonl", modified: now.addingTimeInterval(-100 * 86_400))
        let covered = try reader.read(now: now)
        #expect(covered.coversWindow)
        #expect(covered.usedPhrase(count: 1) == "1 used in the last 90 days")
        #expect(covered.coverageNote == nil)
    }

    @Test func aCacheWrittenUnderOtherRulesIsDiscarded() throws {
        try write([Line.load("u1", "\(skills)/supabase", at: "2026-10-01T10:00:00.000Z")], to: "-Users-x-repo/s1.jsonl")
        let file = home.appending(path: "projects/-Users-x-repo/s1.jsonl")
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        // A version 1 entry for the same, unchanged file, with a count the old rules produced.
        let stale = #"{"version":1,"files":{"\#(file.path(percentEncoded: false))":{"size":\#(values.fileSize!),"modified":\#(values.contentModificationDate!.timeIntervalSinceReferenceDate),"counts":{"supabase":9}}}}"#
        try FileManager.default.createDirectory(at: reader.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try stale.write(to: reader.cache, atomically: true, encoding: .utf8)
        #expect(try reader.read(now: now).loads == ["supabase": 1])
    }
}

@Suite("Loads are credited by exact name")
struct UsageCreditTests {
    let swiftui = Skill(name: "swiftui", folder: URL(filePath: "/tmp/skills/swiftui"))

    @Test func playlistGroupsAndPluginCopiesCreditNothing() {
        let loads = ["playlist:swiftui": 3, "anthropic-skills:swiftui": 2]
        #expect(swiftui.crediting(loads).usesLast90Days == 0)
    }

    @Test func anExactNameIsCredited() {
        #expect(swiftui.crediting(["swiftui": 4, "playlist:swiftui": 3]).usesLast90Days == 4)
    }
}

@Suite("A session that can't be opened is tried again")
struct UnreadableSessionTests {
    @Test func notCachedAsEmpty() throws {
        let home = URL.temporaryDirectory.appending(path: "skill-health-unreadable-\(UUID().uuidString)")
        let file = home.appending(path: "projects/-Users-x/s1.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let skills = home.appending(path: "skills").path(percentEncoded: false)
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: \#(skills)/vite\n"}]},"isMeta":true,"uuid":"u1","timestamp":"2026-10-01T10:00:00.000Z"}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
        let reader = UsageReader(paths: SkillHealthPaths(claudeHome: home))
        let now = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-10-03T12:00:00.000Z")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path(percentEncoded: false))
        #expect(try reader.read(now: now).loads.isEmpty)
        // Readable again with the same size and date: counted, not remembered as empty.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path(percentEncoded: false))
        #expect(try reader.read(now: now).loads == ["vite": 1])
    }
}
