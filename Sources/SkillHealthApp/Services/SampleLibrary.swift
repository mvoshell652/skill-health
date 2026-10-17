import Foundation

/// "Try with Sample Skills": a small .claude folder inside the app's own container, so Skill Health can
/// be tried, including by App Review, without Claude Code or any folder grant. Three skills of
/// Skill Health's own writing (samples/ in its repository): one with a finding, so the menu and the
/// evidence window have something to show; one behind its source; one current. Usage comes from a
/// session history written at install time, since it has to name this copy's real path.
enum SampleLibrary {
    static var bundled: URL? { Bundle.main.url(forResource: "SampleClaude", withExtension: nil) }
    static var installed: URL { URL.applicationSupportDirectory.appending(path: "skill-health/SampleClaude") }

    /// A fresh copy every time, so nothing from an earlier visit sticks.
    static func install() throws -> URL {
        let fm = FileManager.default
        guard let bundled else { throw CocoaError(.fileNoSuchFile) }
        if fm.fileExists(atPath: installed.path(percentEncoded: false)) { try fm.removeItem(at: installed) }
        try fm.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: bundled, to: installed)
        try writeSessions(into: installed)
        return installed
    }

    /// One session that loaded supabase-basics five times and python-env twice, this week. Written in
    /// the exact shape Claude Code writes (key order included: the usage reader anchors on it), not
    /// through JSONSerialization, which doesn't keep key order.
    private static func writeSessions(into home: URL) throws {
        let skills = home.appending(path: "skills").path(percentEncoded: false)
            .replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        let stamp = Date.now.addingTimeInterval(-2 * 24 * 60 * 60).formatted(.iso8601)
        var lines: [String] = []
        for (index, name) in (Array(repeating: "supabase-basics", count: 5) + ["python-env", "python-env"]).enumerated() {
            lines.append(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: \#(skills)/\#(name)\n\n(sample)"}]},"isMeta":true,"uuid":"sample-load-\#(index)","timestamp":"\#(stamp)"}"#)
        }
        let session = home.appending(path: "projects/-sample/sample-session.jsonl")
        try FileManager.default.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)
    }
}
