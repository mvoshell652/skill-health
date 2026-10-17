import Foundation

/// Turns one `MenuInput` into the menu's groups, state by state (A to H in the spec).
struct MenuLayout {
    let input: MenuInput
    /// Skills with something to fix: those with a failing instruction first, then the most used. Use
    /// leads over the number failing: measured on a real menu, sorting by count put a skill used
    /// twice in 90 days above one used 185 times.
    let skills: [MenuInput.SkillIssues]
    let failing: Int
    let deprecated: Int

    init(_ input: MenuInput) {
        self.input = input
        let listed = input.skills.filter { $0.failing + $0.deprecated > 0 }
        skills = listed.sorted {
            ($0.failing > 0 ? 0 : 1, -$0.loads, $0.name) < ($1.failing > 0 ? 0 : 1, -$1.loads, $1.name)
        }
        failing = listed.reduce(0) { $0 + $1.failing }
        deprecated = listed.reduce(0) { $0 + $1.deprecated }
    }

    // MARK: Icon

    /// Counts only mean something once the folder and usage are read.
    private var counted: Bool { input.load == .loaded && input.usage == .read }
    var showsDot: Bool { counted && failing + deprecated > 0 }
    var iconLabel: String {
        guard counted, let counts = instructionCounts else { return "Skill Health" }
        return "Skill Health, \(counts)"
    }

    // MARK: Which state

    var groups: [MenuModel.Group] {
        switch input.load {
        case .needsFolder:
            [state("Skill Health can't see your skills yet", item("Choose Claude Folder…", .chooseFolder))]
        case .loading:
            [reading]
        case .failed:
            [state("Skill Health couldn't read your Claude folder", item("Choose Claude Folder Again…", .chooseFolder))]
        case .loaded:
            switch input.usage {
            case .reading: [reading]
            case .failed: [usageUnreadable] + problemGroups(checkGroupShown: false)
            // Sample skills show no check group either, so they say an unreadable results file themselves.
            case .read: loaded + problemGroups(checkGroupShown: !input.sampleMode)
            }
        }
    }

    /// States A to D carry one header and at most one item.
    private func state(_ header: String, _ item: MenuModel.Item? = nil) -> MenuModel.Group {
        MenuModel.Group(id: "state", header: header, items: item.map { [$0] } ?? [])
    }

    private func item(_ title: String, _ action: MenuModel.Item.Action, id: String = "state", subtitle: String? = nil) -> MenuModel.Item {
        MenuModel.Item(id: id, title: title, subtitle: subtitle, action: action)
    }

    /// B: no item at all. The view puts "Settings…" directly under it.
    private var reading: MenuModel.Group { state("Reading your skills…") }

    /// D: Read Skills Again acts at once, so it has no ellipsis.
    private var usageUnreadable: MenuModel.Group {
        state("Skill Health couldn't read which skills you use", item("Read Skills Again", .readUsageAgain))
    }

    private var loaded: [MenuModel.Group] {
        if input.sampleMode { return [sample] + sampleNewerCopies }
        switch input.plugin {
        case .notInstalled:
            // E: what Skill Health knows, then the one step that fixing, checking and updating need.
            let setUp = item("Set Up Claude Code Plugin…", .openSetup, id: "setup",
                             subtitle: "Fixing, checking and updating happen in Claude Code")
            return withClosingGroup(informative, MenuModel.Group(id: "claude-code", header: nil, items: [setUp]))
        case .older:
            // F: the plugin's commands may not exist yet. Say so first, then what Skill Health knows.
            // A check group with no rows keeps its sentence by going last: the view draws the last
            // group without items directly above Settings….
            let update = item("Update Claude Code Plugin…", .openSetup, id: "setup")
            let groups = informative
            return [state("The Claude Code plugin is older than Skill Health", update)] + groups.filter { !$0.items.isEmpty }
                + groups.filter { $0.id == "check" && $0.items.isEmpty }
        case .connected, .installedNotConnected:
            // G.
            return withClosingGroup(informative, MenuModel.Group(id: "claude-code", header: nil, items: [claudeCodeMenu]))
        }
    }

    /// What Skill Health knows about the skills you use, each skill a row that opens its page: what needs
    /// fixing, what is due for a check, what has a newer copy.
    private var informative: [MenuModel.Group] {
        [fixGroup, checkGroup, updateGroup].compactMap { $0 }
    }

    /// The groups, then the closing one. A header with no items isn't drawn, so when nothing is due
    /// the check group's header (what is checked) heads the closing group instead.
    private func withClosingGroup(_ groups: [MenuModel.Group], _ closing: MenuModel.Group) -> [MenuModel.Group] {
        var kept = groups.filter { !$0.items.isEmpty }
        var last = closing
        if let check = groups.first(where: { $0.id == "check" }), check.items.isEmpty {
            last = MenuModel.Group(id: closing.id, header: check.header, items: closing.items)
        }
        kept.append(last)
        return kept
    }

    /// H: sample skills can be reviewed and nothing more. No hand-off, so nothing can reach the
    /// person's own Claude Code from a sample.
    private var sample: MenuModel.Group {
        MenuModel.Group(id: "sample", header: "These are sample skills",
                        items: skills.prefix(MenuModel.listedSkills).map(fixRow) + [item("Choose Claude Folder…", .chooseFolder)])
    }

    /// What Compare Now found for the samples, said as a fact only: an update is the plugin's,
    /// and a sample never reaches the person's Claude Code. With no item, the menu shows it
    /// directly above Settings…, where the comparison is.
    private var sampleNewerCopies: [MenuModel.Group] {
        guard input.newerCopies > 0 else { return [] }
        return [MenuModel.Group(id: "sample-update", header: MenuModel.sampleNewerCopiesHeader(input.newerCopies), items: [])]
    }

    /// An unreadable findings.json is said once, in one wording: by the check group's header when the
    /// menu has a check group, otherwise by a group of its own here. The long wording with the file
    /// and the system's reason stays in Settings, so it isn't also passed in `problems`.
    private func problemGroups(checkGroupShown: Bool) -> [MenuModel.Group] {
        var groups: [MenuModel.Group] = []
        if input.findingsUnreadable, !checkGroupShown {
            groups.append(MenuModel.Group(id: "problem-results", header: Self.resultsUnreadable,
                                          items: [item("Open Settings…", .openSettings, id: "problem-results")]))
        }
        return groups + input.problems.enumerated().map { index, problem in
            // A header has no final period.
            let header = problem.hasSuffix(".") ? String(problem.dropLast()) : problem
            return MenuModel.Group(id: "problem-\(index)", header: header,
                                   items: [item("Open Settings…", .openSettings, id: "problem-\(index)")])
        }
    }

    static let resultsUnreadable = "Skill Health couldn't read the results of earlier checks"

    // MARK: Fix

    /// "3 failing instructions, 4 deprecated" and its smaller forms, for the icon's label. Nil when
    /// there is nothing to fix.
    private var instructionCounts: String? {
        let failingText = failing == 1 ? "1 failing instruction" : "\(NumberText.count(failing)) failing instructions"
        let deprecatedText = deprecated == 1 ? "1 deprecated instruction" : "\(NumberText.count(deprecated)) deprecated instructions"
        return switch (failing, deprecated) {
        case (0, 0): nil
        case (_, 0): failingText
        case (0, _): deprecatedText
        default: "\(failingText), \(NumberText.count(deprecated)) deprecated"
        }
    }

    /// "35 skills need fixing": the thing a person acts on is a skill; each row says its instructions.
    private var fixGroup: MenuModel.Group? {
        guard !skills.isEmpty else { return nil }
        let header = skills.count == 1 ? "1 skill needs fixing" : "\(NumberText.count(skills.count)) skills need fixing"
        return MenuModel.Group(id: "fix", header: header, items: skills.prefix(MenuModel.listedSkills).map(fixRow))
    }

    /// "gcp-cloud-run", second line "14 failing, 3 deprecated · used 183 times". Opens its page.
    private func fixRow(_ skill: MenuInput.SkillIssues) -> MenuModel.Item {
        let counts = [skill.failing > 0 ? "\(NumberText.count(skill.failing)) failing" : nil,
                      skill.deprecated > 0 ? "\(NumberText.count(skill.deprecated)) deprecated" : nil]
            .compactMap(\.self).joined(separator: ", ")
        return skillRow(group: "fix", name: skill.name, facts: [counts, Self.used(skill.loads)])
    }

    /// One skill's row: its name, and the facts on its second line.
    private func skillRow(group: String, name: String, facts: [String?]) -> MenuModel.Item {
        let facts = facts.compactMap(\.self).filter { !$0.isEmpty }
        return MenuModel.Item(id: "\(group):\(name)", title: name,
                              subtitle: facts.isEmpty ? nil : facts.joined(separator: " · "),
                              action: .openEvidence(skill: name))
    }

    /// "used 195 times", "used once"; nil for a skill not used in the window.
    static func used(_ loads: Int) -> String? {
        switch loads {
        case ...0: nil
        case 1: "used once"
        default: "used \(NumberText.count(loads)) times"
        }
    }

    // MARK: Check

    /// What is checked, and the skills due for a check as rows. No rows when nothing is due.
    private var checkGroup: MenuModel.Group? {
        MenuModel.Group(id: "check", header: checkHeader, items: input.due.prefix(MenuModel.listedSkills).map(dueRow))
    }

    /// "eslint", second line "Never checked · used once" / "Changed since its check on Oct 9 · …" /
    /// "Last checked Jul 1 · …".
    private func dueRow(_ skill: MenuInput.Due) -> MenuModel.Item {
        let day = { (date: Date) in DayLabel.short(date, now: input.now, timeZone: input.timeZone) }
        let why = switch skill.reason {
        case .neverChecked: "Never checked"
        case .changedSince(let date): "Changed since its check on \(day(date))"
        case .checkedLongAgo(let date): "Last checked \(day(date))"
        }
        return skillRow(group: "due", name: skill.name, facts: [why, Self.used(skill.loads)])
    }

    private static let openedFor: TimeInterval = 2 * 60 * 60

    private var checkHeader: String {
        // First: a check opened while the results file is unreadable can't save into it, so
        // "opened" would hide the fault until the two hours pass.
        if input.findingsUnreadable { return Self.resultsUnreadable }
        // Opened, never "running": Skill Health can't see Claude Code work, only what it saves.
        if input.plugin.canHandOff, let opened = input.checkOpenedAt, !input.findingsChangedSinceCheck,
           input.now.timeIntervalSince(opened) < Self.openedFor {
            return "Check opened in Claude Code \(Self.ago(input.now.timeIntervalSince(opened)))"
        }
        let used = input.usedCount
        let checked = min(input.checkedUsedCount, used)
        if used == 0 { return "No skills used in the last 90 days" }
        let usedText = NumberText.count(used), checkedText = NumberText.count(checked)
        if checked == 0 { return used == 1 ? "The skill you use isn't checked yet" : "None of the \(usedText) skills you use checked yet" }
        // Some checked, some due: the rows under it are the due ones.
        let due = input.due.count
        if due > 0 { return due == 1 ? "1 skill you use is due for a check" : "\(NumberText.count(due)) skills you use are due for a check" }
        // Not every session is kept, so "used" is a lower bound: "all" can't be claimed. Settings says
        // since when sessions are kept.
        if !input.usageCoversWindow {
            return (checked < used ? "\(checkedText) of \(usedText) skills you use checked" : "\(checkedText) skills you use checked")
                + failingClause(partial: checked < used)
        }
        if checked < used { return "\(checkedText) of \(usedText) skills you use checked" + failingClause(partial: true) }
        let since = input.oldestCheck.map { DayLabel.short($0, now: input.now, timeZone: input.timeZone) }
        let all = used == 1
            ? "The skill you use was checked" + (since.map { " on \($0)" } ?? "")
            : "All \(usedText) skills you use checked" + (since.map { " since \($0)" } ?? "")
        return all + failingClause(partial: false)
    }

    /// Added only while nothing is failing or deprecated: what the checked skills hold. A failing
    /// instruction that was set aside is still failing, so it is said, never ", none failing".
    private func failingClause(partial: Bool) -> String {
        guard failing + deprecated == 0 else { return "" }
        let aside = input.setAsideFailing
        if aside > 0 { return aside == 1 ? ", 1 failing instruction set aside" : ", \(NumberText.count(aside)) failing instructions set aside" }
        return partial ? ", none failing in those" : ", none failing"
    }

    /// "12 minutes ago". Whole units, rounded down; the header is only shown for two hours.
    static func ago(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0) / 60)
        switch minutes {
        case 0: return "just now"
        case 1: return "1 minute ago"
        case 2..<60: return "\(minutes) minutes ago"
        default: return minutes < 120 ? "1 hour ago" : "\(minutes / 60) hours ago"
        }
    }

    // MARK: Update

    /// The skills with a newer copy, as rows.
    private var updateGroup: MenuModel.Group? {
        guard input.newerCopies > 0 else { return nil }
        return MenuModel.Group(id: "update", header: MenuModel.newerCopiesHeader(input.newerCopies),
                               items: input.newer.prefix(MenuModel.listedSkills).map { skillRow(group: "newer", name: $0.name, facts: [Self.used($0.loads)]) })
    }

    // MARK: Hand-offs

    /// G: every command that hands off to Claude Code, in one submenu, so "in Claude Code" is said once.
    private var claudeCodeMenu: MenuModel.Item {
        var commands: [MenuModel.Item] = []
        if skills.count == 1, let command = ClaudeCodeCommand.fix(skill: skills[0].name) {
            commands.append(handOffItem("Fix \(skills[0].name)…", command, id: "fix-one"))
        } else if skills.count >= 2 {
            commands.append(handOffItem("Fix All \(NumberText.count(skills.count)) Skills…", ClaudeCodeCommand.fixAll, id: "fix-all"))
        }
        let due = input.due.count
        commands.append(handOffItem(due == 0 ? "Check Skills…" : due == 1 ? "Check 1 Skill…" : "Check \(NumberText.count(due)) Skills…",
                                    ClaudeCodeCommand.check, id: "check"))
        if input.newerCopies > 0 {
            commands.append(handOffItem(input.newerCopies == 1 ? "Update 1 Skill…" : "Update \(NumberText.count(input.newerCopies)) Skills…",
                                        ClaudeCodeCommand.update, id: "update"))
        }
        return MenuModel.Item(id: "claude-code", title: "Open in Claude Code", action: .submenu, children: commands)
    }

    /// An item that opens Claude Code. When nothing is registered to open the link, it says it copies
    /// the command instead, so the alert that follows isn't a surprise.
    private func handOffItem(_ title: String, _ command: String, id: String) -> MenuModel.Item {
        MenuModel.Item(id: id, title: title,
                       subtitle: input.canOpenClaudeCode ? nil : "Copies the command to paste into Claude Code",
                       action: .openClaudeCode(command: command))
    }
}
