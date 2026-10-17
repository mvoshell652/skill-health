import Foundation
import Testing
@testable import SkillHealthCore

@Suite("The session note follows the same rule as the icon")
struct StatusSnapshotTests {
    let source = URL(string: "https://github.com/supabase/cli/issues/4496")!
    let supabase = Skill(name: "supabase", folder: URL(filePath: "/x"), usesLast90Days: 72)

    func finding(_ status: FindingStatus = .open, skill: String = "supabase", severity: Severity = .breaks) -> Finding {
        Finding(skillName: skill, severity: severity, skillSays: "npm install -g \(skill)",
                trueNow: "npx \(skill)", source: source, foundOn: .now, wrongSince: .undated, status: status)
    }

    func used(_ names: String...) -> [Skill] {
        names.map { Skill(name: $0, folder: URL(filePath: "/x/\($0)"), usesLast90Days: 5) }
    }

    @Test func silentWhenNothingUrgentInUsedSkills() {
        let unused = Skill(name: "supabase", folder: URL(filePath: "/x"), usesLast90Days: 0)
        #expect(StatusSnapshot.make(findings: [finding()], skills: [unused]).sessionNote == nil)
    }

    @Test func namesFailingSkillsSaysWhereToFixThemAndMentionsCorrections() {
        let snapshot = StatusSnapshot.make(findings: [finding()], skills: [supabase])
        #expect(snapshot.sessionNote == "skill-health: 1 skill you use has instructions that now fail (supabase). Run /skill-health:fix to go through them. Claude gets the corrections at the start of every session.")
        #expect(snapshot.corrections.count == 1)
    }

    @Test func twoFailingSkillsListBothInAlphabeticalOrder() {
        // The file's order doesn't decide the order of the names.
        let findings = [finding(skill: "supabase"), finding(skill: "gcp-cloud-run")]
        let snapshot = StatusSnapshot.make(findings: findings, skills: used("supabase", "gcp-cloud-run"))
        #expect(snapshot.sessionNote == "skill-health: 2 skills you use have instructions that now fail (gcp-cloud-run, supabase). Run /skill-health:fix to go through them. Claude gets the corrections at the start of every session.")
    }

    @Test func moreThanTwoFailingSkillsSayHowManyMore() {
        let findings = ["vite", "supabase", "gcp-cloud-run"].map { finding(skill: $0) }
        let snapshot = StatusSnapshot.make(findings: findings, skills: used("vite", "supabase", "gcp-cloud-run"))
        #expect(snapshot.sessionNote == "skill-health: 3 skills you use have instructions that now fail (gcp-cloud-run, supabase and 1 more). Run /skill-health:fix to go through them. Claude gets the corrections at the start of every session.")
    }

    @Test func deprecatedOnlyHasNoCorrectionsLine() {
        let snapshot = StatusSnapshot.make(findings: [finding(skill: "tailwindcss", severity: .deprecated)], skills: used("tailwindcss"))
        #expect(snapshot.sessionNote == "skill-health: 1 skill you use has deprecated instructions (tailwindcss). Run /skill-health:fix to go through them.")
        // Only failing instructions are corrections.
        #expect(snapshot.corrections.isEmpty)
    }

    @Test func failingTakesTheNoteAndDeprecatedIsLeftToTheMenu() {
        let findings = [finding(skill: "tailwindcss", severity: .deprecated), finding(skill: "supabase")]
        let snapshot = StatusSnapshot.make(findings: findings, skills: used("tailwindcss", "supabase"))
        #expect(snapshot.sessionNote?.contains("tailwindcss") == false)
        #expect(snapshot.corrections.map(\.skillName) == ["supabase"])
    }

    @Test func theNoteAndTheCorrectionsAreRenderedWhateverTheOldSettingsSay() {
        // A settings.json from before the plugin's options turned both switches off. They are kept
        // for old files and ignored: the plugin decides what is printed.
        let off = Settings(sessionNote: false, correctionsForClaude: false)
        let snapshot = StatusSnapshot.make(findings: [finding()], skills: [supabase], settings: off)
        #expect(snapshot.sessionNote != nil)
        #expect(snapshot.corrections.count == 1)
        #expect(snapshot == StatusSnapshot.make(findings: [finding()], skills: [supabase], now: snapshot.writtenAt))
    }

    @Test func theFiveCorrectionsComeFromTheSkillsUsedMost() {
        // Six failing instructions, in file order: two in a skill used once, four in one used 191 times.
        let rare = Skill(name: "oxlint", folder: URL(filePath: "/x/oxlint"), usesLast90Days: 1)
        let daily = Skill(name: "gcp-cloud-run", folder: URL(filePath: "/x/gcp"), usesLast90Days: 191)
        let findings = [finding(skill: "oxlint"), finding(skill: "oxlint")]
            + (1...4).map { n in
                Finding(skillName: "gcp-cloud-run", severity: .breaks, skillSays: "line \(n)", trueNow: "now",
                        source: source, foundOn: .now, wrongSince: .undated, status: .open)
            }
        let snapshot = StatusSnapshot.make(findings: findings, skills: [rare, daily])
        #expect(snapshot.corrections.map(\.skillName) == ["gcp-cloud-run", "gcp-cloud-run", "gcp-cloud-run", "gcp-cloud-run", "oxlint"])
        // A skill's own findings keep their order.
        #expect(snapshot.corrections.prefix(4).map(\.skillSays) == ["line 1", "line 2", "line 3", "line 4"])
    }

    @Test func theSameWrongLineFromTwoFilesIsOneCorrection() {
        let daily = Skill(name: "gcp-cloud-run", folder: URL(filePath: "/x/gcp"), usesLast90Days: 191)
        let line = "gcloud builds submit --tag gcr.io/MY_PROJECT_ID/my-app:latest"
        let findings = [nil, "references/cloud-run-deployment-with-gcloud-cli.md"].map { file in
            Finding(skillName: "gcp-cloud-run", severity: .breaks, skillSays: line, trueNow: "now", source: source,
                    foundOn: .now, wrongSince: .undated, file: file)
        } + [Finding(skillName: "gcp-cloud-run", severity: .breaks, skillSays: "docker push gcr.io/x", trueNow: "now",
                     source: source, foundOn: .now, wrongSince: .undated)]
        let snapshot = StatusSnapshot.make(findings: findings, skills: [daily])
        #expect(snapshot.corrections.map(\.skillSays) == [line, "docker push gcr.io/x"])
    }

    @Test func anExpiredSetAsideComesBack() {
        let now = Date.now
        let expired = finding(.setAside(until: now.addingTimeInterval(-60)))
        let current = finding(.setAside(until: now.addingTimeInterval(3600)))
        #expect(Urgency.findings([expired], skills: [supabase], now: now).count == 1)
        #expect(Urgency.findings([current], skills: [supabase], now: now).isEmpty)
    }

    @Test func noSetAsideLastsLongerThan180Days() {
        let now = Date.now
        guard case .setAside(let until) = FindingStatus.cappedSetAside(until: .distantFuture, now: now) else {
            Issue.record("expected a set-aside"); return
        }
        #expect(until == now.addingTimeInterval(FindingStatus.longestSetAside))
    }
}
