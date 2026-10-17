import Foundation
import Testing
@testable import SkillHealthCore

/// The menu says what the spec says, word for word. Each test builds one state or one plural or
/// edge rule from a `MenuInput` and asserts the exact strings, since the words are the design.
@Suite("The menu, state by state")
struct MenuStateTests {
    static func day(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
    static let now = day("2026-10-04T19:00:00Z")

    static func make(_ configure: (inout MenuInput) -> Void = { _ in }) -> MenuModel {
        var input = MenuInput(now: now, timeZone: .gmt)
        configure(&input)
        return MenuModel(input)
    }

    static let gcp = MenuInput.SkillIssues(name: "gcp-cloud-run", failing: 1, deprecated: 2, loads: 175)
    static let supabase = MenuInput.SkillIssues(name: "supabase", failing: 2, deprecated: 0, loads: 188)
    static let tailwind = MenuInput.SkillIssues(name: "tailwindcss", failing: 0, deprecated: 1, loads: 300)
    static let vite = MenuInput.SkillIssues(name: "vite", failing: 0, deprecated: 1, loads: 21)

    /// Every command the menu would open in Claude Code, submenus included.
    func handOffs(_ menu: MenuModel) -> [String] {
        menu.groups.flatMap(\.items).flatMap { [$0] + $0.children }.compactMap { item in
            if case .openClaudeCode(let command) = item.action { command } else { nil }
        }
    }

    /// The "Open in Claude Code" submenu's items, by title.
    func submenu(_ menu: MenuModel) -> [String] {
        menu.groups.flatMap(\.items).first { $0.action == .submenu }?.children.map(\.title) ?? []
    }

    // MARK: A to D

    @Test func aNoFolderAsksForTheFolderDirectly() {
        let menu = Self.make { $0.load = .needsFolder }
        #expect(menu.groups.map(\.header) == ["Skill Health can't see your skills yet"])
        #expect(menu.groups[0].items == [.init(id: "state", title: "Choose Claude Folder…", action: .chooseFolder)])
        #expect(menu.iconLabel == "Skill Health")
        #expect(!menu.showsDot)
    }

    @Test func bReadingIsAHeaderAloneSoSettingsSitsDirectlyUnderIt() {
        for configure in [{ (i: inout MenuInput) in i.load = .loading }, { (i: inout MenuInput) in i.usage = .reading }] {
            let menu = Self.make(configure)
            #expect(menu.groups.map(\.header) == ["Reading your skills…"])
            #expect(menu.groups[0].items.isEmpty)
        }
    }

    @Test func cFolderUnreadableOffersTheFolderAgain() {
        let menu = Self.make { $0.load = .failed }
        #expect(menu.groups.map(\.header) == ["Skill Health couldn't read your Claude folder"])
        #expect(menu.groups[0].items == [.init(id: "state", title: "Choose Claude Folder Again…", action: .chooseFolder)])
    }

    @Test func dUsageUnreadableReadsAtOnceSoItHasNoEllipsis() {
        let menu = Self.make { $0.usage = .failed; $0.skills = [Self.gcp] }
        #expect(menu.groups.map(\.header) == ["Skill Health couldn't read which skills you use"])
        #expect(menu.groups[0].items == [.init(id: "state", title: "Read Skills Again", action: .readUsageAgain)])
        // Nothing is counted until usage is read, so the icon stays plain.
        #expect(menu.iconLabel == "Skill Health")
        #expect(!menu.showsDot)
    }

    // MARK: G, the normal menu

    @Test func gNormalSaysWhatIsTrueAndHandsOffFromOneSubmenu() {
        let menu = Self.make {
            $0.skills = [Self.vite, Self.gcp, Self.tailwind, Self.supabase]
            $0.usedCount = 79
            $0.checkedUsedCount = 5
            $0.newerCopies = 23
            $0.newer = [.init(name: "react", loads: 40)]
        }
        #expect(menu.groups.map(\.header) == ["4 skills need fixing", "23 skills you use have newer copies", "5 of 79 skills you use checked"])
        // Each skill is a row with its name, failing first, then most used, and opens its page in Skill Health.
        #expect(menu.groups[0].items.map(\.title) == ["supabase", "gcp-cloud-run", "tailwindcss", "vite"])
        #expect(menu.groups[0].items.map(\.action) == [.openEvidence(skill: "supabase"), .openEvidence(skill: "gcp-cloud-run"),
                                                       .openEvidence(skill: "tailwindcss"), .openEvidence(skill: "vite")])
        #expect(menu.groups[1].items.map(\.title) == ["react"])
        #expect(menu.groups[1].items.map(\.action) == [.openEvidence(skill: "react")])
        // Every hand-off in one submenu; "in Claude Code" said once, by it.
        #expect(menu.groups[2].items.map(\.title) == ["Open in Claude Code"])
        #expect(submenu(menu) == ["Fix All 4 Skills…", "Check Skills…", "Update 23 Skills…"])
        #expect(handOffs(menu) == ["/skill-health:fix", "/skill-health:check", "/skill-health:update"])
        #expect(menu.iconLabel == "Skill Health, 3 failing instructions, 4 deprecated")
        #expect(menu.showsDot)
    }

    @Test func gAnInstalledPluginThatHasntConnectedYetStillHandsOff() {
        let menu = Self.make { $0.plugin = .installedNotConnected; $0.skills = [Self.gcp]; $0.usedCount = 3 }
        #expect(submenu(menu) == ["Fix gcp-cloud-run…", "Check Skills…"])
    }

    @Test func gWithNothingToFixHasNoFixGroupAndNoDot() {
        let menu = Self.make { $0.usedCount = 79; $0.checkedUsedCount = 5 }
        #expect(menu.groups.map(\.header) == ["5 of 79 skills you use checked, none failing in those"])
        #expect(submenu(menu) == ["Check Skills…"])
        #expect(menu.iconLabel == "Skill Health")
        #expect(!menu.showsDot)
    }

    @Test func updateGroupIsAbsentWithoutNewerCopies() {
        let menu = Self.make { $0.usedCount = 4; $0.checkedUsedCount = 4; $0.oldestCheck = Self.day("2026-09-26T00:00:00Z") }
        #expect(menu.groups.map(\.id) == ["claude-code"])
        #expect(!submenu(menu).contains { $0.hasPrefix("Update") })
    }

    // MARK: Fix header and rows

    @Test(arguments: [
        (3, 4, "3 failing instructions, 4 deprecated"), (1, 1, "1 failing instruction, 1 deprecated"),
        (3, 0, "3 failing instructions"), (1, 0, "1 failing instruction"),
        (0, 4, "4 deprecated instructions"), (0, 1, "1 deprecated instruction"),
    ])
    func theIconCountsInstructions(failing: Int, deprecated: Int, label: String) {
        let menu = Self.make { $0.skills = [.init(name: "one", failing: failing, deprecated: deprecated, loads: 9)] }
        #expect(menu.groups[0].header == "1 skill needs fixing")
        #expect(menu.iconLabel == "Skill Health, \(label)")
    }

    @Test func aSingleSkillIsFixedByNameNotFixAll() {
        let menu = Self.make { $0.skills = [Self.gcp] }
        #expect(submenu(menu).first == "Fix gcp-cloud-run…")
        #expect(handOffs(menu).first == "/skill-health:fix gcp-cloud-run")
    }

    @Test func rowsAreCappedAtFiveButHeaderAndFixAllCountEverySkill() {
        let many = (1...7).map { MenuInput.SkillIssues(name: "skill-\($0)", failing: 1, deprecated: 0, loads: 100 - $0) }
        let menu = Self.make { $0.skills = many }
        #expect(menu.groups[0].header == "7 skills need fixing")
        #expect(menu.groups[0].items.map(\.title) == ["skill-1", "skill-2", "skill-3", "skill-4", "skill-5"])
        #expect(submenu(menu).first == "Fix All 7 Skills…")
    }

    @Test func rowsAreSortedFailingFirstThenByUseThenName() {
        let menu = Self.make {
            $0.skills = [.init(name: "b", failing: 0, deprecated: 1, loads: 9), .init(name: "a", failing: 0, deprecated: 1, loads: 9),
                         .init(name: "z", failing: 1, deprecated: 0, loads: 1), .init(name: "y", failing: 1, deprecated: 0, loads: 2),
                         .init(name: "rare", failing: 21, deprecated: 0, loads: 1)]
        }
        // Use leads over the number failing: 21 failing in a skill used once doesn't outrank one used twice.
        #expect(menu.groups[0].items.map(\.title) == ["y", "rare", "z", "a", "b"])
    }

    @Test func aSkillWithNothingOpenIsNotListed() {
        let menu = Self.make { $0.skills = [.init(name: "clean", failing: 0, deprecated: 0, loads: 50)] }
        #expect(menu.groups.map(\.id) == ["claude-code"])
    }

    @Test func aRowsSecondLineSaysItsCountsAndUse() {
        let menu = Self.make {
            $0.skills = [Self.gcp, .init(name: "once", failing: 1, deprecated: 0, loads: 1),
                         .init(name: "dep", failing: 0, deprecated: 3, loads: 1_234)]
        }
        let rows = menu.groups[0].items
        #expect(rows.map(\.subtitle) == ["1 failing, 2 deprecated · used 175 times", "1 failing · used once", "3 deprecated · used 1,234 times"])
    }

    @Test func aNameThatIsNotPlainlyANameGetsAPageNeverACommand() {
        let odd = MenuInput.SkillIssues(name: "my skill; rm -rf ~", failing: 1, deprecated: 0, loads: 5)
        let menu = Self.make { $0.skills = [odd, Self.gcp] }
        #expect(menu.groups[0].items.map(\.action) == [.openEvidence(skill: "gcp-cloud-run"), .openEvidence(skill: "my skill; rm -rf ~")]
                || menu.groups[0].items.map(\.action) == [.openEvidence(skill: "my skill; rm -rf ~"), .openEvidence(skill: "gcp-cloud-run")])
        // Whatever the name holds, no command in the menu carries it.
        #expect(handOffs(menu) == ["/skill-health:fix", "/skill-health:check"])
        // Alone, it has no fix command of its own.
        #expect(handOffs(Self.make { $0.skills = [odd] }) == ["/skill-health:check"])
    }

    // MARK: Due for a check

    @Test func skillsDueForACheckAreRowsSayingWhy() {
        let menu = Self.make {
            $0.usedCount = 81; $0.checkedUsedCount = 79
            $0.due = [.init(name: "eslint", loads: 1, reason: .neverChecked),
                      .init(name: "vite", loads: 21, reason: .changedSince(Self.day("2026-10-01T18:00:00Z"))),
                      .init(name: "old", loads: 4, reason: .checkedLongAgo(Self.day("2026-07-01T18:00:00Z")))]
        }
        let check = menu.groups.first { $0.id == "check" }
        #expect(check?.header == "3 skills you use are due for a check")
        #expect(check?.items.map(\.title) == ["eslint", "vite", "old"])
        #expect(check?.items.map(\.subtitle) == ["Never checked · used once", "Changed since its check on Oct 1 · used 21 times",
                                                 "Last checked Jul 1 · used 4 times"])
        #expect(check?.items.map(\.action) == [.openEvidence(skill: "eslint"), .openEvidence(skill: "vite"), .openEvidence(skill: "old")])
        #expect(submenu(menu) == ["Check 3 Skills…"])
        #expect(Self.make { $0.usedCount = 2; $0.checkedUsedCount = 1; $0.due = [.init(name: "a", loads: 1, reason: .neverChecked)] }
            .groups.first { $0.id == "check" }?.header == "1 skill you use is due for a check")
    }

    @Test func withNothingDueTheCheckSentenceHeadsTheClaudeCodeGroup() {
        let menu = Self.make { $0.usedCount = 4; $0.checkedUsedCount = 4; $0.oldestCheck = Self.day("2026-09-26T00:00:00Z") }
        #expect(menu.groups.map(\.header) == ["All 4 skills you use checked since Sep 26, none failing"])
        #expect(menu.groups[0].items.map(\.title) == ["Open in Claude Code"])
    }

    // MARK: Check header

    /// What the menu says about checks: the check group's header, or, with nothing due, the header of
    /// the group it moved to.
    func check(_ configure: (inout MenuInput) -> Void) -> String? {
        let groups = Self.make(configure).groups
        return (groups.first { $0.id == "check" } ?? groups.first { $0.id == "claude-code" })?.header
    }

    @Test func usageThatDoesntCoverNinetyDaysNeverSaysAll() {
        #expect(check { $0.usageCoversWindow = false; $0.usedCount = 79; $0.checkedUsedCount = 5 }
                == "5 of 79 skills you use checked, none failing in those")
        // With every skill counted checked it still can't say "all": more may have been used.
        #expect(check { $0.usageCoversWindow = false; $0.usedCount = 79; $0.checkedUsedCount = 79 }
                == "79 skills you use checked, none failing")
        #expect(check { $0.usageCoversWindow = false; $0.usedCount = 1; $0.checkedUsedCount = 0 }
                == "The skill you use isn't checked yet")
    }

    @Test func noSkillsUsed() {
        #expect(check { $0.usedCount = 0 } == "No skills used in the last 90 days")
        // Even when usage doesn't cover the window: there is nothing to count "at least" of.
        #expect(check { $0.usedCount = 0; $0.usageCoversWindow = false } == "No skills used in the last 90 days")
    }

    @Test func noneChecked() {
        #expect(check { $0.usedCount = 79 } == "None of the 79 skills you use checked yet")
        #expect(check { $0.usedCount = 1 } == "The skill you use isn't checked yet")
        // Failing instructions from shared corrections don't change what was checked.
        #expect(check { $0.usedCount = 79; $0.skills = [Self.gcp] } == "None of the 79 skills you use checked yet")
    }

    @Test func someChecked() {
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 5 } == "5 of 79 skills you use checked, none failing in those")
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 5; $0.skills = [Self.gcp] } == "5 of 79 skills you use checked")
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 5; $0.setAsideFailing = 2 }
                == "5 of 79 skills you use checked, 2 failing instructions set aside")
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 5; $0.setAsideFailing = 1 }
                == "5 of 79 skills you use checked, 1 failing instruction set aside")
        // Counts print with a thousands separator.
        #expect(check { $0.usedCount = 1_639; $0.checkedUsedCount = 1_200; $0.skills = [Self.gcp] } == "1,200 of 1,639 skills you use checked")
    }

    @Test func allChecked() {
        let oldest = Self.day("2026-09-26T00:00:00Z")
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 79; $0.oldestCheck = oldest }
                == "All 79 skills you use checked since Sep 26, none failing")
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 79; $0.oldestCheck = oldest; $0.skills = [Self.gcp] }
                == "All 79 skills you use checked since Sep 26")
        #expect(check { $0.usedCount = 79; $0.checkedUsedCount = 79; $0.oldestCheck = oldest; $0.setAsideFailing = 3 }
                == "All 79 skills you use checked since Sep 26, 3 failing instructions set aside")
        #expect(check { $0.usedCount = 1; $0.checkedUsedCount = 1; $0.oldestCheck = oldest }
                == "The skill you use was checked on Sep 26, none failing")
    }

    @Test func theOldestCheckKeepsItsYearWhenItIsNotThisOne() {
        #expect(check { $0.usedCount = 2; $0.checkedUsedCount = 2; $0.oldestCheck = Self.day("2025-12-31T00:00:00Z"); $0.skills = [Self.gcp] }
                == "All 2 skills you use checked since Dec 31, 2025")
    }

    @Test func aCheckThatRanAtNightIsTheDayItRanForThePerson() {
        // 9:41 pm in Los Angeles on Sep 26 is Sep 27 in UTC; a real moment is the person's own day.
        let moment = Self.day("2026-09-27T04:41:00Z")
        let menu = Self.make { $0.timeZone = TimeZone(identifier: "America/Los_Angeles")!; $0.usedCount = 2; $0.checkedUsedCount = 2; $0.oldestCheck = moment; $0.skills = [Self.gcp] }
        #expect(menu.groups.first { $0.id == "claude-code" }?.header == "All 2 skills you use checked since Sep 26")
    }

    @Test func findingsThatCantBeReadSaySoInsteadOfCountingChecks() {
        #expect(check { $0.findingsUnreadable = true; $0.usedCount = 79; $0.checkedUsedCount = 5 }
                == "Skill Health couldn't read the results of earlier checks")
    }

    // MARK: An unreadable results file is always said, once

    static let unreadable = "Skill Health couldn't read the results of earlier checks"

    /// How often the menu says it, across every header.
    func timesSaid(_ menu: MenuModel) -> Int { menu.groups.count { $0.header == Self.unreadable } }

    @Test func anOpenedCheckDoesNotHideAnUnreadableResultsFile() {
        // The check was opened a moment ago, and the file it would save into can't be read.
        let menu = Self.make {
            $0.findingsUnreadable = true; $0.usedCount = 79; $0.checkedUsedCount = 5; $0.plugin = .connected
            $0.checkOpenedAt = Self.now.addingTimeInterval(-12 * 60)
        }
        #expect(menu.groups.first { $0.id == "claude-code" }?.header == Self.unreadable)
        #expect(timesSaid(menu) == 1)
    }

    @Test func withoutACheckGroupTheUnreadableResultsAreSaidByAGroupOfTheirOwn() {
        // Usage couldn't be read, so there is no check group to say it.
        let usage = Self.make { $0.usage = .failed; $0.findingsUnreadable = true }
        #expect(usage.groups.map(\.header) == ["Skill Health couldn't read which skills you use", Self.unreadable])
        #expect(usage.groups[1].items == [.init(id: "problem-results", title: "Open Settings…", action: .openSettings)])
        // Sample skills show no check group either.
        let sample = Self.make { $0.sampleMode = true; $0.findingsUnreadable = true; $0.skills = [Self.gcp]; $0.newerCopies = 1 }
        #expect(sample.groups.map(\.header) == ["These are sample skills", "1 sample skill has a newer copy", Self.unreadable])
        #expect(sample.groups.last?.items == [.init(id: "problem-results", title: "Open Settings…", action: .openSettings)])
        // The other problems follow it, each under its own header.
        let both = Self.make { $0.usage = .failed; $0.findingsUnreadable = true; $0.problems = ["Skill Health couldn't read what you fixed or set aside"] }
        #expect(both.groups.map(\.header) == ["Skill Health couldn't read which skills you use", Self.unreadable, "Skill Health couldn't read what you fixed or set aside"])
        // Group ids stay unique, since the menu lists groups by them.
        #expect(Set(both.groups.map(\.id)).count == both.groups.count)
    }

    @Test func withACheckGroupTheUnreadableResultsAreSaidOnlyThere() {
        for plugin in [PluginState.connected, .installedNotConnected, .notInstalled, .older] {
            let menu = Self.make { $0.findingsUnreadable = true; $0.usedCount = 4; $0.plugin = plugin }
            #expect(timesSaid(menu) == 1, "\(plugin)")
            // Said by the check sentence, wherever it sits: its own group, or the closing one.
            #expect(menu.groups.contains { ["check", "claude-code"].contains($0.id) && $0.header == Self.unreadable }, "\(plugin)")
            #expect(!menu.groups.contains { $0.id == "problem-results" })
        }
    }

    @Test func aReadableResultsFileSaysNothingOfTheKind() {
        #expect(timesSaid(Self.make { $0.usage = .failed }) == 0)
        #expect(timesSaid(Self.make { $0.sampleMode = true }) == 0)
        #expect(timesSaid(Self.make { $0.usedCount = 4 }) == 0)
    }

    // MARK: A check that was opened

    func opened(minutes: Double, changed: Bool = false, plugin: PluginState = .connected) -> String? {
        check {
            $0.usedCount = 79; $0.checkedUsedCount = 5; $0.skills = [Self.gcp]; $0.plugin = plugin
            $0.checkOpenedAt = Self.now.addingTimeInterval(-minutes * 60); $0.findingsChangedSinceCheck = changed
        }
    }

    @Test func aCheckOpenedFromTheMenuIsOpenedNeverRunning() {
        #expect(opened(minutes: 12) == "Check opened in Claude Code 12 minutes ago")
        #expect(opened(minutes: 0.4) == "Check opened in Claude Code just now")
        #expect(opened(minutes: 1) == "Check opened in Claude Code 1 minute ago")
        #expect(opened(minutes: 61) == "Check opened in Claude Code 1 hour ago")
        #expect(opened(minutes: 119) == "Check opened in Claude Code 1 hour ago")
    }

    @Test func theOpenedHeaderEndsWhenFindingsChangeOrTwoHoursPass() {
        #expect(opened(minutes: 12, changed: true) == "5 of 79 skills you use checked")
        #expect(opened(minutes: 120) == "5 of 79 skills you use checked")
        #expect(opened(minutes: 600) == "5 of 79 skills you use checked")
    }

    @Test func theOpenedHeaderNeedsAHandOffToHaveHappened() {
        #expect(opened(minutes: 12, plugin: .notInstalled) == "5 of 79 skills you use checked")
    }

    // MARK: Update

    @Test func newerCopiesPlural() {
        let react = MenuInput.Listed(name: "react", loads: 4)
        #expect(Self.make { $0.newerCopies = 23; $0.newer = [react] }.groups.first { $0.id == "update" }?.header == "23 skills you use have newer copies")
        #expect(Self.make { $0.newerCopies = 1; $0.newer = [react] }.groups.first { $0.id == "update" }?.header == "1 skill you use has a newer copy")
        #expect(MenuModel.newerCopiesHeader(1_024) == "1,024 skills you use have newer copies")
    }

    // MARK: E, the plugin isn't installed

    @Test func eSaysWhatIsTrueAndOffersOneSetUp() {
        let menu = Self.make {
            $0.plugin = .notInstalled; $0.skills = [Self.gcp, Self.supabase]; $0.usedCount = 79; $0.checkedUsedCount = 5
            $0.newerCopies = 23; $0.newer = [.init(name: "react", loads: 4)]
        }
        #expect(menu.groups.map(\.header) == ["2 skills need fixing", "23 skills you use have newer copies", "5 of 79 skills you use checked"])
        #expect(menu.groups[0].items.map(\.title) == ["supabase", "gcp-cloud-run"])
        #expect(menu.groups[0].items.map(\.action) == [.openEvidence(skill: "supabase"), .openEvidence(skill: "gcp-cloud-run")])
        // One way forward, said once, with why on its second line.
        #expect(menu.groups[2].items == [.init(id: "setup", title: "Set Up Claude Code Plugin…",
                                                subtitle: "Fixing, checking and updating happen in Claude Code", action: .openSetup)])
        // No hand-off anywhere: nothing can be opened in Claude Code.
        #expect(handOffs(menu).isEmpty)
    }

    @Test func eWithNothingToFixStillOffersSetUp() {
        let menu = Self.make { $0.plugin = .notInstalled; $0.usedCount = 79; $0.checkedUsedCount = 5; $0.newerCopies = 1 }
        #expect(menu.groups.flatMap(\.items).map(\.title) == ["Set Up Claude Code Plugin…"])
    }

    // MARK: F, the plugin is older

    @Test func fSaysThePluginIsOlderThenWhatIsTrue() {
        let menu = Self.make { $0.plugin = .older; $0.skills = [Self.gcp]; $0.usedCount = 3; $0.checkedUsedCount = 3 }
        #expect(menu.groups[0].header == "The Claude Code plugin is older than Skill Health")
        #expect(menu.groups[0].items == [.init(id: "setup", title: "Update Claude Code Plugin…", action: .openSetup)])
        #expect(menu.groups[1].header == "1 skill needs fixing")
        #expect(menu.groups[1].items.map(\.action) == [.openEvidence(skill: "gcp-cloud-run")])
        // With nothing due, the check sentence goes last, where the view draws it above Settings….
        #expect(menu.groups.last?.id == "check")
        #expect(menu.groups.last?.items.isEmpty == true)
        #expect(handOffs(menu).isEmpty)
    }

    // MARK: H, sample skills

    @Test func hSampleSkillsAreReviewedAndNeverHandedOff() {
        let menu = Self.make { $0.sampleMode = true; $0.skills = [.init(name: "supabase-basics", failing: 1, deprecated: 0, loads: 5)]; $0.usedCount = 2; $0.newerCopies = 1 }
        // What Compare Now found is said as a fact, with nothing to do about it.
        #expect(menu.groups.map(\.header) == ["These are sample skills", "1 sample skill has a newer copy"])
        #expect(menu.groups[1].items.isEmpty)
        #expect(Self.make { $0.sampleMode = true; $0.skills = [Self.gcp]; $0.newerCopies = 0 }.groups.map(\.header) == ["These are sample skills"])
        #expect(menu.groups[0].items.map(\.title) == ["supabase-basics", "Choose Claude Folder…"])
        #expect(menu.groups[0].items.map(\.action) == [.openEvidence(skill: "supabase-basics"), .chooseFolder])
        #expect(menu.groups[0].items[0].subtitle == "1 failing · used 5 times")
        // Even a connected plugin: a sample must not reach the person's own Claude Code.
        #expect(handOffs(Self.make { $0.sampleMode = true; $0.plugin = .connected; $0.skills = [Self.gcp] }).isEmpty)
    }

    // MARK: Problems

    @Test func aProblemWithAFileAddsAHeaderInWordsAndOpenSettings() {
        let menu = Self.make { $0.usedCount = 4; $0.checkedUsedCount = 4; $0.problems = ["Skill Health couldn't read your decisions: the data couldn't be read."] }
        let problem = menu.groups.last
        #expect(problem?.header == "Skill Health couldn't read your decisions: the data couldn't be read")
        #expect(problem?.items == [.init(id: "problem-0", title: "Open Settings…", action: .openSettings)])
    }

    @Test func eachProblemHasItsOwnHeader() {
        let menu = Self.make { $0.problems = ["one", "two"] }
        #expect(menu.groups.suffix(2).map(\.header) == ["one", "two"])
    }

    // MARK: Hand-off when nothing opens the link

    @Test func whenNothingCanOpenClaudeCodeEveryHandOffSaysItCopies() {
        let hint = "Copies the command to paste into Claude Code"
        let menu = Self.make { $0.canOpenClaudeCode = false; $0.skills = [Self.gcp, Self.supabase]; $0.usedCount = 9; $0.newerCopies = 2 }
        let commands = menu.groups.flatMap(\.items).first { $0.action == .submenu }?.children ?? []
        #expect(commands.map(\.subtitle) == [hint, hint, hint])
        let opens = Self.make { $0.skills = [Self.gcp, Self.supabase]; $0.usedCount = 9; $0.newerCopies = 2 }
        #expect(opens.groups.flatMap(\.items).first { $0.action == .submenu }?.children.allSatisfy { $0.subtitle == nil } == true)
    }
}
