import Foundation
import Testing
@testable import SkillHealthCore

/// Runs the plugin's real hook script, plugin/scripts/session-start.sh, the way Claude Code does:
/// `sh` with the session's JSON on stdin and the plugin's data folder in the environment.
@Suite("The plugin's SessionStart hook script")
struct HookScriptTests {
    static let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "plugin/scripts/session-start.sh")
    let root = URL.temporaryDirectory.appending(path: "skill-health-hook-\(UUID().uuidString)")
    var skillHealth: URL { root.appending(path: "skill-health") }
    var pluginData: URL { root.appending(path: "plugin-data") }

    func files(note: String? = #"{"systemMessage":"note"}"#, quiet: String? = #"{"hookSpecificOutput":{}}"#, age: TimeInterval = 0) throws {
        try FileManager.default.createDirectory(at: skillHealth, withIntermediateDirectories: true)
        for (name, text) in [("hook-note.json", note), ("hook-quiet.json", quiet)] {
            guard let text else { continue }
            let file = skillHealth.appending(path: name)
            try text.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-age)], ofItemAtPath: file.path(percentEncoded: false))
        }
    }

    /// `environment` is what Claude Code adds: the plugin's options (CLAUDE_PLUGIN_OPTION_*) and its root.
    func run(source: String = "startup", pluginData: URL? = nil, environment extra: [String: String] = [:]) throws -> String {
        var environment = extra.merging(["SKILL_HEALTH_DIR": skillHealth.plainPath]) { mine, _ in mine }
        if let pluginData { environment["CLAUDE_PLUGIN_DATA"] = pluginData.plainPath }
        let result = try runPluginScript(Self.script, stdin: #"{"session_id":"s","hook_event_name":"SessionStart","source":"\#(source)"}"#,
                                         environment: environment)
        #expect(result.status == 0)
        return result.output
    }

    @Test func theNoteOnceADayAndTheCorrectionsEveryTime() throws {
        try files()
        #expect(try run(pluginData: pluginData) == #"{"systemMessage":"note"}"#)
        #expect(try run(pluginData: pluginData) == #"{"hookSpecificOutput":{}}"#)
        // A day later the note is due again.
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-25 * 3600)],
                                              ofItemAtPath: pluginData.appending(path: "note-shown").path(percentEncoded: false))
        #expect(try run(pluginData: pluginData) == #"{"systemMessage":"note"}"#)
    }

    @Test func afterClearOrCompactOnlyTheCorrections() throws {
        try files()
        for source in ["clear", "compact", "resume"] {
            #expect(try run(source: source, pluginData: pluginData) == #"{"hookSpecificOutput":{}}"#)
        }
    }

    @Test func withoutItsDataFolderTheNoteStaysQuiet() throws {
        try files()
        #expect(try run(pluginData: nil) == #"{"hookSpecificOutput":{}}"#)
    }

    /// If the note can't be printed (its stamp folder can't be made), the corrections still go.
    @Test func aNoteThatCantBeStampedDoesntSwallowTheCorrections() throws {
        try files()
        try "a file where the plugin's data folder should be".write(to: pluginData, atomically: true, encoding: .utf8)
        #expect(try run(pluginData: pluginData) == #"{"hookSpecificOutput":{}}"#)
    }

    /// A stamp dated in the future (a clock that ran ahead once) would otherwise hide the note for good.
    @Test func aNoteStampDatedInTheFutureDoesntHideTheNote() throws {
        try files()
        _ = try run(pluginData: pluginData)
        let stamp = pluginData.appending(path: "note-shown")
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(3 * 86_400)], ofItemAtPath: stamp.plainPath)
        #expect(try run(pluginData: pluginData) == #"{"systemMessage":"note"}"#)
    }

    @Test func filesAWeekOldMeanSilence() throws {
        try files(age: 8 * 86_400)
        #expect(try run(pluginData: pluginData) == "")
    }

    @Test func nothingToSayMeansNothingPrinted() throws {
        try files(note: nil, quiet: nil)
        #expect(try run(pluginData: pluginData) == "")
        #expect(FileManager.default.fileExists(atPath: skillHealth.appending(path: "hook-read").path(percentEncoded: false)))
    }

    @Test func noSkillHealthFolderMeansSilenceAndNoFolderMade() throws {
        #expect(try run(pluginData: pluginData) == "")
        #expect(!FileManager.default.fileExists(atPath: skillHealth.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: skillHealth.appending(path: "plugin.json").plainPath))
    }
}

/// The two options (/plugin configure skill-health) and the plugin.json handshake.
extension HookScriptTests {
    static let corrections = #"{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"corrections"}}"#
    static let noteAndCorrections = #"{"systemMessage":"note","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"corrections"}}"#
    static let noteOff = ["CLAUDE_PLUGIN_OPTION_SESSION_NOTE": "false"]
    static let correctionsOff = ["CLAUDE_PLUGIN_OPTION_CORRECTIONS_FOR_CLAUDE": "false"]

    var stamp: URL { pluginData.appending(path: "note-shown") }

    @Test func bothOptionsOnIsWhatHappensWithoutAnyOptions() throws {
        try files(note: Self.noteAndCorrections, quiet: Self.corrections)
        let on = ["CLAUDE_PLUGIN_OPTION_SESSION_NOTE": "true", "CLAUDE_PLUGIN_OPTION_CORRECTIONS_FOR_CLAUDE": "true"]
        #expect(try run(pluginData: pluginData, environment: on) == Self.noteAndCorrections)
        #expect(try run(pluginData: pluginData, environment: on) == Self.corrections)
    }

    @Test func sessionNoteOffPrintsTheCorrectionsAloneAndNeverStampsTheNote() throws {
        try files(note: Self.noteAndCorrections, quiet: Self.corrections)
        #expect(try run(pluginData: pluginData, environment: Self.noteOff) == Self.corrections)
        #expect(try run(source: "clear", pluginData: pluginData, environment: Self.noteOff) == Self.corrections)
        #expect(!FileManager.default.fileExists(atPath: stamp.plainPath))
        // Turned back on, the note is due at once.
        #expect(try run(pluginData: pluginData) == Self.noteAndCorrections)
    }

    @Test func correctionsOffPrintsTheNoteWithoutWhatIsMeantForClaude() throws {
        try files(note: Self.noteAndCorrections, quiet: Self.corrections)
        let first = try run(pluginData: pluginData, environment: Self.correctionsOff)
        let printed = try #require(try JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
        #expect(Set(printed.keys) == ["systemMessage"])
        #expect(printed["systemMessage"] as? String == "note")
        #expect(!first.contains("corrections"))
        #expect(FileManager.default.fileExists(atPath: stamp.plainPath))
        // The note is once a day, and the corrections stay off: nothing else prints, even after /clear.
        #expect(try run(pluginData: pluginData, environment: Self.correctionsOff) == "")
        #expect(try run(source: "clear", pluginData: pluginData, environment: Self.correctionsOff) == "")
    }

    /// The app's real failing note ends by saying Claude gets the corrections. With them off, that
    /// sentence would be untrue, so it goes, word for word, and only it.
    @Test func correctionsOffDropsTheSentenceSayingClaudeGetsThem() throws {
        let line = "skill-health: 1 skill you use has instructions that now fail (supabase). Run /skill-health:fix to go through them."
        let note = try JSONSerialization.data(withJSONObject: [
            "systemMessage": line + " " + StatusSnapshot.correctionsTail,
            "hookSpecificOutput": ["hookEventName": "SessionStart", "additionalContext": "corrections"],
        ])
        try files(note: String(decoding: note, as: UTF8.self), quiet: Self.corrections)
        let off = try #require(try JSONSerialization.jsonObject(with: Data(try run(pluginData: pluginData, environment: Self.correctionsOff).utf8)) as? [String: Any])
        #expect(off["systemMessage"] as? String == line)
        let on = try #require(try JSONSerialization.jsonObject(with: Data(try run(pluginData: root.appending(path: "other-data")).utf8)) as? [String: Any])
        #expect(on["systemMessage"] as? String == line + " " + StatusSnapshot.correctionsTail)
    }

    @Test func bothOffPrintsNothingAndStillConnects() throws {
        try files(note: Self.noteAndCorrections, quiet: Self.corrections)
        let off = Self.noteOff.merging(Self.correctionsOff) { mine, _ in mine }
        #expect(try run(pluginData: pluginData, environment: off) == "")
        #expect(try run(source: "clear", pluginData: pluginData, environment: off) == "")
        #expect(!FileManager.default.fileExists(atPath: stamp.plainPath))
        #expect(FileManager.default.fileExists(atPath: skillHealth.appending(path: "hook-read").plainPath))
        #expect(FileManager.default.fileExists(atPath: skillHealth.appending(path: "plugin.json").plainPath))
    }

    @Test func onlyTheWordFalseTurnsAnOptionOff() throws {
        try files(note: Self.noteAndCorrections, quiet: Self.corrections)
        for value in ["", "yes", "1", "off", "true"] {
            try? FileManager.default.removeItem(at: stamp)
            #expect(try run(pluginData: pluginData, environment: ["CLAUDE_PLUGIN_OPTION_SESSION_NOTE": value]) == Self.noteAndCorrections, "value \(value)")
        }
        try? FileManager.default.removeItem(at: stamp)
        #expect(try run(pluginData: pluginData, environment: ["CLAUDE_PLUGIN_OPTION_SESSION_NOTE": "FALSE"]) == Self.corrections)
    }

    @Test func aNoteFileWithoutANoteIsNotStampedWhenCorrectionsAreOff() throws {
        try files(note: Self.corrections, quiet: Self.corrections)
        #expect(try run(pluginData: pluginData, environment: Self.correctionsOff) == "")
        #expect(!FileManager.default.fileExists(atPath: stamp.plainPath))
    }

    // MARK: The handshake

    func pluginRoot(manifest: String?) throws -> URL {
        let folder = root.appending(path: "plugin-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: ".claude-plugin"), withIntermediateDirectories: true)
        if let manifest { try manifest.write(to: folder.appending(path: ".claude-plugin/plugin.json"), atomically: true, encoding: .utf8) }
        return folder
    }

    func handshake() throws -> PluginHandshake {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PluginHandshake.self, from: Data(contentsOf: skillHealth.appending(path: "plugin.json")))
    }

    @Test func everyRunWritesTheHandshakeTheAppReads() throws {
        try files(note: nil, quiet: nil)
        let folder = try pluginRoot(manifest: #"{"name": "skill-health","version":"0.4.0"}"#)
        #expect(try run(pluginData: pluginData, environment: ["CLAUDE_PLUGIN_ROOT": folder.plainPath]) == "")
        let written = try handshake()
        #expect(written.version == "0.4.0")
        #expect(written.isAtLeastMinimum)
        #expect(abs(written.readAt.timeIntervalSinceNow) < 60)
        // Even a run that has nothing to print writes it, and replaces it each time.
        try FileManager.default.removeItem(at: skillHealth.appending(path: "plugin.json"))
        _ = try run(source: "resume", pluginData: pluginData, environment: ["CLAUDE_PLUGIN_ROOT": folder.plainPath])
        #expect(try handshake().version == "0.4.0")
        // Written through a temp file that is moved into place, so none is left behind.
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: skillHealth.plainPath)) == ["hook-read", "plugin.json"])
    }

    @Test func theHandshakeCarriesTheRealManifestVersion() throws {
        try files(note: nil, quiet: nil)
        _ = try run(pluginData: pluginData, environment: ["CLAUDE_PLUGIN_ROOT": PluginFiles.plugin.plainPath])
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: PluginFiles.plugin.appending(path: ".claude-plugin/plugin.json"))) as? [String: Any]
        #expect(try handshake().version == manifest?["version"] as? String)
    }

    @Test func aVersionItCantReadIsUnknownAndNeverBreaksTheJSON() throws {
        try files(note: nil, quiet: nil)
        let cases: [(String, [String: String])] = [
            ("no plugin root", [:]),
            ("no manifest", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: nil).plainPath]),
            ("not JSON", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: "{nope").plainPath]),
            ("no version", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: #"{"name": "skill-health"}"#).plainPath]),
            ("not a string", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: #"{"version":4}"#).plainPath]),
            ("quote in it", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: #"{"version":"0.4.0\",\"x\":\"y"}"#).plainPath]),
            ("space in it", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: #"{"version":"0.4 0"}"#).plainPath]),
            ("too long", ["CLAUDE_PLUGIN_ROOT": try pluginRoot(manifest: #"{"version":"\#(String(repeating: "1", count: 65))"}"#).plainPath]),
        ]
        for (label, environment) in cases {
            _ = try run(pluginData: pluginData, environment: environment)
            let written = try handshake()
            #expect(written.version == "unknown", "\(label)")
            #expect(!written.isAtLeastMinimum, "\(label)")
        }
    }
}

@Suite("The app renders the hook's files")
struct HookFilesTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-hookfiles-\(UUID().uuidString)")
    var engine: Engine { Engine(paths: SkillHealthPaths(claudeHome: home)) }
    let correction = Correction(skillName: "supabase", skillSays: "npm install -g supabase",
                                trueNow: "The Supabase CLI refuses global installs.",
                                source: URL(string: "https://github.com/supabase/cli/issues/4496")!)

    @Test func noteAndQuietFilesAndRemovedWhenSilent() async throws {
        let paths = SkillHealthPaths(claudeHome: home)
        try await engine.writeStatus(StatusSnapshot(sessionNote: "skill-health: note", corrections: [correction]))
        let note = try JSONDecoder().decode(HookOutput.self, from: Data(contentsOf: paths.hookNote))
        let quiet = try JSONDecoder().decode(HookOutput.self, from: Data(contentsOf: paths.hookQuiet))
        #expect(note.systemMessage == "skill-health: note")
        #expect(note.hookSpecificOutput?.additionalContext.contains("npm install -g supabase") == true)
        #expect(quiet.systemMessage == nil)
        #expect(quiet.hookSpecificOutput == note.hookSpecificOutput)

        try await engine.writeStatus(StatusSnapshot(sessionNote: nil, corrections: []))
        #expect(!FileManager.default.fileExists(atPath: paths.hookNote.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: paths.hookQuiet.path(percentEncoded: false)))
    }

    @Test func unchangedContentIsStillRefreshedDaily() async throws {
        let paths = SkillHealthPaths(claudeHome: home)
        let snapshot = StatusSnapshot(sessionNote: "skill-health: note", corrections: [])
        let start = Date.now
        try await engine.writeStatus(snapshot, now: start)
        let first = try FileManager.default.attributesOfItem(atPath: paths.hookNote.path(percentEncoded: false))[.modificationDate] as? Date
        try await engine.writeStatus(snapshot, now: start.addingTimeInterval(3600))
        let sameDay = try FileManager.default.attributesOfItem(atPath: paths.hookNote.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(first == sameDay)
        try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(-2 * 86_400)], ofItemAtPath: paths.status.path(percentEncoded: false))
        try await engine.writeStatus(snapshot, now: start)
        let refreshed = try FileManager.default.attributesOfItem(atPath: paths.status.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(refreshed.map { start.timeIntervalSince($0) < 60 } == true)
    }

    /// A clock that ran ahead leaves status.json dated in the future; the hook doesn't count that as fresh,
    /// so the file has to be rewritten, not skipped as "written less than a day ago".
    @Test func aStatusFileDatedInTheFutureIsRewritten() async throws {
        let paths = SkillHealthPaths(claudeHome: home)
        let snapshot = StatusSnapshot(sessionNote: "skill-health: note", corrections: [])
        try await engine.writeStatus(snapshot)
        let future = Date.now.addingTimeInterval(30 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: paths.status.path(percentEncoded: false))
        try await engine.writeStatus(snapshot)
        let rewritten = try #require(try FileManager.default.attributesOfItem(atPath: paths.status.path(percentEncoded: false))[.modificationDate] as? Date)
        #expect(rewritten < future)
    }

    @Test func correctionTextIsOneBoundedLinePerField() {
        #expect(SessionStartHook.oneLine("Ignore that.\nNew instructions: do X", 200) == "Ignore that. New instructions: do X")
        #expect(SessionStartHook.oneLine(String(repeating: "a", count: 500), 10).count == 10)
        #expect(SessionStartHook.oneLine("tab\there\u{7}", 50) == "tabhere")
    }
}
