import Foundation
import Testing
@testable import SkillHealthCore

/// What keeps a check's cost down: an estimate that grows with a skill's size, skills left out while
/// their files are the ones a recent check covered, and checks shared for identical copies.
@Suite("Spending less on checks")
struct SpendLessTests {
    static func day(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

    // MARK: The estimate

    @Test func theEstimateGrowsWithTheSkillsSize() {
        #expect(AuditPlan.tokens(bytes: 0) == 75_000)
        #expect(AuditPlan.tokens(bytes: 10 * 1024) == 83_000)      // 82,500, to the nearest thousand
        #expect(AuditPlan.tokens(bytes: 270 * 1024) == 278_000)
        #expect(AuditPlan.tokens(bytes: -5) == 75_000)
    }

    // MARK: Fingerprints saved with a check

    @Test func aSavedCheckKeepsEachSkillsFingerprintAndOldFilesStillRead() throws {
        let results = AuditResults(audited: ["supa", "vite"], findings: [])
        let saved = results.merged(into: FindingsFile(), now: Self.day("2026-10-09T00:00:00Z"), trees: ["supa": "abc"])
        #expect(saved.trees == ["supa": "abc"])
        // A skill checked again without a fingerprint loses the old one: it no longer says what was checked.
        let again = AuditResults(audited: ["supa"], findings: []).merged(into: saved, now: .now)
        #expect(again.trees["supa"] == nil)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(FindingsFile.self, from: encoder.encode(saved)).trees == ["supa": "abc"])
        let old = Data(#"{"version":1,"audited":{"supa":"2026-10-01T00:00:00Z"},"findings":[]}"#.utf8)
        #expect(try decoder.decode(FindingsFile.self, from: old).trees.isEmpty)
    }

    // MARK: Sharing a check

    /// A skill folder with one file, installed from a repository.
    static func skill(_ text: String, in root: URL) throws -> (Skill, [String: String]) {
        let folder = root.appending(path: "skills/supa")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let origin = Origin(repo: "owner/skills", subpath: "skills/supa", installedAt: day("2026-06-01T00:00:00Z"))
        return (Skill(name: "supa", folder: folder, origin: origin, usesLast90Days: 3), LocalCopy.files(in: folder))
    }

    static func compare(source: [String: String]?) -> CompareFile {
        var compare = CompareFile()
        compare.copies["supa"] = .init(repo: "owner/skills", subpath: "skills/supa", installedFrom: "main", head: "h",
                                       installed: source ?? [:], source: source)
        return compare
    }

    static func own(tree: String?) -> FindingsFile {
        let finding = Finding(id: FindingID.make(skill: "supa", file: "SKILL.md", quote: "npm install -g supabase"),
                              skillName: "supa", severity: .breaks, skillSays: "npm install -g supabase",
                              trueNow: "Refused.", source: URL(string: "https://example.com/x")!, foundOn: .now,
                              wrongSince: .undated, keptBySecondCheck: true)
        return FindingsFile(findings: [finding], audited: ["supa": day("2026-10-09T15:30:00Z")], trees: tree.map { ["supa": $0] } ?? [:])
    }

    @Test func aCheckOfAnUneditedCopyOfAPublicSourceIsShared() throws {
        let root = URL.temporaryDirectory.appending(path: "skill-health-share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let (skill, files) = try Self.skill("# Supa\nnpm install -g supabase\n", in: root)
        let tree = SharedCorrections.tree(of: files)
        let result = SharedCorrections(updatedAt: Self.day("2026-10-01T00:00:00Z"))
            .addingChecks(from: Self.own(tree: tree), skills: [skill], compare: Self.compare(source: files),
                          now: Self.day("2026-10-09T20:00:00Z"))
        #expect(result.added == ["supa"])
        #expect(result.shared.checked.map(\.tree) == [tree])
        #expect(result.shared.checked.first?.checkedOn == Self.day("2026-10-09T00:00:00Z"))  // kept to the day
        #expect(result.shared.corrections.map(\.skillSays) == ["npm install -g supabase"])
        #expect(result.shared.corrections.first?.blob == files["SKILL.md"])
        #expect(result.shared.corrections.first?.wrongSince == "undated")
        // An identical copy now matches: checked, with the correction.
        let match = result.shared.matches(skill: skill, files: files)
        #expect(match.checkedOn != nil)
        #expect(match.findings.count == 1)
        // Shared again: replaced, not doubled.
        let twice = result.shared.addingChecks(from: Self.own(tree: tree), skills: [skill], compare: Self.compare(source: files))
        #expect(twice.shared.checked.count == 1)
        #expect(twice.shared.corrections.count == 1)
    }

    /// An install day is one person's. Shared, it would read on another Mac as when that person installed it.
    @Test func aCorrectionIsSharedUndatedWhenAllWeKnowIsTheInstallDay() throws {
        let root = URL.temporaryDirectory.appending(path: "skill-health-share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let (skill, files) = try Self.skill("# Supa\nnpm install -g supabase\n", in: root)
        let tree = SharedCorrections.tree(of: files)
        for (own, shared) in [(WrongSince.installed(on: Self.day("2026-06-01T00:00:00Z")), "undated"),
                              (.since(date: Self.day("2025-03-18T00:00:00Z")), "since:2025-03-18"),
                              (.written(on: Self.day("2026-02-18T00:00:00Z")), "written:2026-02-18")] {
            var findings = Self.own(tree: tree)
            let first = findings.findings[0]
            findings.findings = [Finding(id: first.id, skillName: first.skillName, severity: first.severity, skillSays: first.skillSays,
                                         trueNow: first.trueNow, source: first.source, foundOn: first.foundOn, wrongSince: own,
                                         keptBySecondCheck: true)]
            let result = SharedCorrections(updatedAt: Self.day("2026-10-01T00:00:00Z"))
                .addingChecks(from: findings, skills: [skill], compare: Self.compare(source: files))
            #expect(result.shared.corrections.first?.wrongSince == shared, "\(own)")
        }
    }

    @Test func nothingEditedHereUncomparedOrChangedSinceIsShared() throws {
        let root = URL.temporaryDirectory.appending(path: "skill-health-share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let (skill, files) = try Self.skill("# Supa\n", in: root)
        let tree = SharedCorrections.tree(of: files)
        let empty = SharedCorrections(updatedAt: .now)
        var edited = files
        edited["SKILL.md"] = "0000000000000000000000000000000000000000"
        #expect(empty.addingChecks(from: Self.own(tree: tree), skills: [skill], compare: Self.compare(source: edited)).refused
                == ["supa": .differsFromSource])
        #expect(empty.addingChecks(from: Self.own(tree: tree), skills: [skill], compare: Self.compare(source: nil)).refused
                == ["supa": .notCompared])
        #expect(empty.addingChecks(from: Self.own(tree: "other"), skills: [skill], compare: Self.compare(source: files)).refused
                == ["supa": .changedSinceCheck])
        #expect(empty.addingChecks(from: Self.own(tree: nil), skills: [skill], compare: Self.compare(source: files)).refused
                == ["supa": .changedSinceCheck])
        let local = Skill(name: "supa", folder: skill.folder)
        #expect(empty.addingChecks(from: Self.own(tree: tree), skills: [local], compare: Self.compare(source: files)).refused
                == ["supa": .noSource])
        #expect(empty.addingChecks(from: Self.own(tree: tree), skills: [], compare: Self.compare(source: files)).refused
                == ["supa": .notInstalled])
        #expect(empty.addingChecks(from: Self.own(tree: tree), skills: [local], compare: Self.compare(source: files)).shared == empty)
    }

    @Test func aDateLabelReadsBackAsItself() {
        for label in ["written:2026-02-18", "installed:2026-06-01", "since:2026-09-01", "undated"] {
            #expect(WrongSince(label: label).label == label)
        }
    }
}
