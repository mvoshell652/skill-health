import Foundation
import Testing
@testable import SkillHealthCore

/// Whether the app sees the plugin as installed, from Claude Code's own record of installed plugins.
@Suite("Seeing the plugin in Claude Code's record")
struct ClaudeCodeLinkTests {
    let home = URL.temporaryDirectory.appending(path: "skill-health-link-\(UUID().uuidString)")
    var engine: Engine { Engine(paths: SkillHealthPaths(claudeHome: home)) }

    func record(_ names: [String]) throws {
        let folder = home.appending(path: "plugins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let plugins = Dictionary(uniqueKeysWithValues: names.map { ($0, [[String: String]()]) })
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "plugins": plugins])
        try data.write(to: folder.appending(path: "installed_plugins.json"))
    }

    @Test func theInstalledPluginIsFoundByItsName() async throws {
        try record(["claude-video-vision@claude-video-vision", "skill-health@skill-health"])
        #expect(await engine.claudeCodeLink().installed)
    }

    @Test func anyMarketplaceCounts() async throws {
        try record(["skill-health@someone-else"])
        #expect(await engine.claudeCodeLink().installed)
    }

    @Test func otherPluginsDont() async throws {
        try record(["other-plugin@other-marketplace", "skill-health-extras@x", "Skill Health@skill-health"])
        #expect(await !engine.claudeCodeLink().installed)
    }

    @Test func noRecordMeansNotInstalled() async {
        #expect(await !engine.claudeCodeLink().installed)
    }
}
