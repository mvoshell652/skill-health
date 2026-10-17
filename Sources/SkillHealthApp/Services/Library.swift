import Accessibility
import AppKit
import Observation
import SkillHealthCore

/// The app's single source of truth for skills, findings and settings. Views read it;
/// only its methods change it. MainActor by the target's default isolation.
///
/// Skill Health watches and says when. It never writes a skill: fixes, checks and updates run in Claude
/// Code through the plugin, and the files they leave in ~/.claude/skill-health are what the library reads.
@Observable
final class Library {
    private var engine: Engine?
    private var loop: Task<Void, Never>?
    private var notes: Task<Void, Never>?
    private var onActivation: Task<Void, Never>?
    private var hourly: Task<Void, Never>?
    /// Bumped whenever the folder changes. Every pass checks it after each await, so work begun
    /// for an earlier folder can never write its results over the current one.
    private var generation = 0
    private var usageRead: (generation: Int, task: Task<Void, Never>)?

    private(set) var state = LoadState.needsFolder
    private(set) var skills: [Skill] = []
    /// The checks' findings with the person's decisions joined in.
    private(set) var findingsFile = FindingsFile()
    /// findings.json as read, and the decisions, kept apart as they are on disk. The plugin writes both.
    private(set) var savedFindings = FindingsFile()
    private(set) var decisions = DecisionsFile()
    /// Why findings.json couldn't be read, in words. Said in the menu, never shown as "no findings",
    /// and never mistaken for the folder being unreadable.
    private(set) var findingsProblem: String?
    /// findings.json exists but couldn't be read: nothing about what's been checked is known.
    private(set) var findingsUnreadable = false
    /// decisions.json exists but couldn't be read, in words.
    private(set) var decisionsProblem: String?
    /// Bound directly by the setup window; `saveSettings()` persists it.
    var settings = Settings()
    /// Derived once per refresh, not on every read: the icon, the menu and the session note all use
    /// these values, computed by the one rule in SkillHealthCore.
    private(set) var urgentFindings: [Finding] = []
    private(set) var safeUpdateCount = 0
    private(set) var usage = UsageState.notRead
    /// The last usage read. Newly discovered skills are credited from it straight away, so a
    /// refresh never shows "0 used" while the next read runs.
    private(set) var usageReport: UsageReport?
    /// What the last comparison with GitHub found, and each copy's state from disk against it.
    private(set) var compare = CompareFile()
    private var copyStates: [String: CopyState] = [:]
    /// Shared corrections (the snapshot shipped in the app), and what they matched on this Mac.
    private let shared: SharedCorrections? = SharedCorrectionsFile.bundled()
    private var sharedFindings: [Finding] = []
    private(set) var sharedChecked: [String: Date] = [:]
    /// Each skill's fingerprint as last read, so the menu can say which skills a check still covers.
    private(set) var trees: [String: String] = [:]
    /// A comparison with GitHub is running.
    private(set) var comparing = false

    /// Where the Claude Code plugin stands, from the handshake its SessionStart hook writes.
    private(set) var pluginState = PluginState.notInstalled
    /// When Claude Code last read Skill Health's notes: the handshake's time, or the older hook-read file's.
    private(set) var pluginLastRead: Date?
    /// Where a command can open in Claude Code on this Mac: the Claude app, a terminal, both or
    /// neither. Read again with every refresh and before every open.
    private(set) var destinations: Set<ClaudeCodeCommand.Destination> = []
    /// Whether a menu item can open Claude Code at all, or copies its command instead.
    var canOpenClaudeCode: Bool { !destinations.isEmpty }
    /// Where the person chose to open commands, in Settings (`openCommandsIn`). The Claude app
    /// until they choose: it opens with no permission prompt.
    var preferredDestination: ClaudeCodeCommand.Destination {
        UserDefaults.standard.string(forKey: Self.openInKey).flatMap(ClaudeCodeCommand.Destination.init) ?? .claudeApp
    }
    static let openInKey = "openCommandsIn"
    /// When a check was last opened in Claude Code from the menu. Forgotten once findings.json changes
    /// (its results landed) or two hours pass. "Opened", never "running".
    private(set) var checkOpenedAt: Date?
    private var findingsStampAtCheck: Date?
    /// Moves once a minute while a check is shown as opened, so "12 minutes ago" is re-read and the
    /// two hours it lasts end on time. The menu reads it; nothing else does.
    private(set) var clock = Date.now
    private var ticker: Task<Void, Never>?
    /// The plugin's files as they were when last read. A change to any of them is a refresh.
    private var seenStamps: PluginFileStamps?

    /// True while the sample library is what's shown. Samples are never handed to Claude Code.
    private(set) var isSample = false
    /// The person chose a folder: say what happened to VoiceOver when it's known.
    private var announcesConnection = false
    /// A failure to save Skill Health's own files. Kept apart from `state`, which says only whether
    /// the folder could be read: choosing the folder again can't fix a full disk.
    private(set) var lastWriteError: String?
    /// False when FSEvents won't watch the folder; Skill Health then re-reads only when it becomes
    /// active and once an hour, and says so.
    private(set) var watchesFolder = true

    /// Starts with no folder: in the sandbox nothing under ~/.claude is reachable until the
    /// person grants it (FolderAccess). `use(claudeFolder:)` is called once they have.
    init() {
        // Checks ran in the app with the person's own API key until 2026-10-04; they run in Claude
        // Code now. A key saved then is removed from the keychain rather than left behind.
        LegacyAPIKey.remove()
    }

    /// Points the library at a granted folder and starts its loops. They live here, not in a
    /// view, so they keep running when the menu bar icon is hidden and every window is closed.
    /// Everything shown about the previous folder is cleared first.
    func use(claudeFolder: URL, isSample: Bool = false, announcing: Bool = false) {
        generation += 1
        let paths = SkillHealthPaths(claudeHome: claudeFolder)
        let engine = Engine(paths: paths)
        self.engine = engine
        self.isSample = isSample
        announcesConnection = announcing
        skills = []
        findingsFile = FindingsFile()
        savedFindings = FindingsFile()
        decisions = DecisionsFile()
        findingsProblem = nil
        findingsUnreadable = false
        decisionsProblem = nil
        urgentFindings = []
        safeUpdateCount = 0
        usage = .notRead
        usageReport = nil
        usageRead = nil
        compare = CompareFile()
        copyStates = [:]
        sharedFindings = []
        sharedChecked = [:]
        trees = [:]
        pluginState = .notInstalled
        pluginLastRead = nil
        checkOpenedAt = nil
        findingsStampAtCheck = nil
        ticker?.cancel()
        seenStamps = nil
        comparing = false
        lastWriteError = nil
        watchesFolder = true
        state = .loading
        loop?.cancel()
        notes?.cancel()
        onActivation?.cancel()
        hourly?.cancel()
        let mine = generation
        loop = Task { await watch(engine: engine, generation: mine) }
        // Usage and the 90-day window move while Skill Health runs for days, so read again when the
        // person comes back to Skill Health and once an hour. The per-file cache keeps both cheap.
        onActivation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await self?.refresh()
            }
        }
        hourly = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 * 60))
                guard !Task.isCancelled else { return }
                await self?.refresh()
                await self?.compareIfDue()
            }
        }
    }

    /// Skill Health's own folder inside the Claude folder: where its files live. Claude Code is opened in
    /// the empty `workspace` inside it, never in this folder (see `ClaudeCodeLauncher.open`).
    var skillHealthFolder: URL? { engine?.paths.home }
    /// True while any skills shown are samples: the sample library, or findings a debug launch injected.
    var showsSamples: Bool { isSample || DebugSnapshot.injectsSamples }
    /// True once findings.json has changed since a check was opened from the menu.
    var findingsChangedSinceCheck: Bool { checkOpenedAt != nil && seenStamps?.findings != findingsStampAtCheck }
    var lastCompared: Date? { compare.checkedAt }

    /// A skill's open failing and deprecated instructions, failing first: what its evidence window shows.
    func openFindings(for skillName: String) -> [Finding] {
        findingsFile.findings
            .filter { $0.skillName == skillName && $0.severity.isUrgent && $0.isOpen() }
            .sorted { ($0.severity, $0.skillSays) < ($1.severity, $1.skillSays) }
    }

    // MARK: Watching

    /// Refresh now, then whenever anything under the skills folder changes. The watchers start
    /// first, so a change made during the first (slow) refresh still triggers another.
    private func watch(engine: Engine, generation mine: Int) async {
        let watcher = FolderWatcher(watching: engine.paths.skills)
        if watcher == nil { watchesFolder = false }
        // What Claude Code writes lands in ~/.claude/skill-health: findings, decisions, updates, a
        // comparison, the plugin's handshake. Skill Health writes there too (status.json, the hook's files,
        // its settings and usage cache), so only a change to one of those five files refreshes.
        if let folder = FolderWatcher(watching: engine.paths.home) {
            notes = Task { [weak self] in
                for await _ in folder.changes {
                    guard let self, mine == self.generation else { return }
                    if PluginFileStamps(paths: engine.paths) != self.seenStamps { await self.refresh() }
                }
            }
        }
        await refresh()
        guard let watcher else { return }
        for await _ in watcher.changes {
            guard mine == generation else { return }
            await refresh()
        }
    }

    func refresh() async {
        guard let engine else { state = .needsFolder; return }
        let mine = generation
        let shown = settings
        // Taken before anything is read: a file that changes while this runs differs from these
        // stamps, so the next change event refreshes again instead of being taken for seen.
        let stamps = PluginFileStamps(paths: engine.paths)
        do {
            let settings = try await engine.loadSettings()
            let discovered = try await engine.discoverSkills()
            let findings: FindingsFile?
            var problem: String?
            do { findings = try await engine.loadFindings() } catch {
                findings = nil
                problem = ProblemText.resultsUnreadable(ProblemText.reason(error))
            }
            if let unreadable = findings?.unreadable, unreadable > 0 {
                problem = ProblemText.resultsPartlyUnreadable(unreadable)
            }
            let decisions: DecisionsFile?
            var decisionsProblem: String?
            do { decisions = try await engine.loadDecisions() } catch {
                decisions = nil
                decisionsProblem = error.plainDescription
            }
            let compare = await engine.loadCompare()
            let link = await engine.claudeCodeLink()
            let handshake = PluginHandshake.read(from: engine.paths.pluginHandshake)
            guard mine == generation else { return }
            pluginState = PluginState(installed: link.installed, lastRead: link.lastRead, handshake: handshake)
            pluginLastRead = handshake?.readAt ?? link.lastRead
            destinations = ClaudeCodeLauncher.available()
            // Unless the person changed a switch while this read ran: theirs wins, and is saved.
            if self.settings == shown { self.settings = settings }
            self.compare = compare
            // Credited from the last reads at once, so nothing flashes while they run again.
            skills = discovered.map { skill in
                var known = skill.crediting(usageReport?.loads ?? [:])
                known.copy = copyStates[skill.name]
                return known
            }
            savedFindings = findings ?? FindingsFile()
            findingsProblem = problem
            findingsUnreadable = findings == nil
            self.decisionsProblem = decisionsProblem
            if let decisions { self.decisions = decisions }
            seenStamps = stamps
            forgetCheckOpened(now: .now)
            recompute()
            state = .loaded
        } catch {
            guard mine == generation else { return }
            state = .failed(error.localizedDescription)
            if announcesConnection {
                announcesConnection = false
                AccessibilityNotification.Announcement("Skill Health couldn't read the folder. \(error.localizedDescription)").post()
            }
            return
        }
        await refreshCopies(engine: engine, generation: mine)
        await refreshUsage()
    }

    /// Each copy's state from its files on disk against the last comparison, and the shared
    /// corrections that match the files as they are now. One pass over the files; no network.
    private func refreshCopies(engine: Engine, generation mine: Int) async {
        let result = await engine.inspect(skills, compare: compare, shared: shared)
        guard mine == generation else { return }
        let states = result.states
        copyStates = states
        sharedFindings = result.sharedFindings
        sharedChecked = result.checked
        trees = result.trees
        skills = skills.map { skill in
            var known = skill
            known.copy = states[skill.name]
            return known
        }
        recompute()
    }

    // MARK: Comparing with GitHub

    /// Compares every recorded skill with its source on GitHub. The first comparison is the person's
    /// choice (it is the only time Skill Health reaches the network); after that, daily if they leave
    /// Compare daily on. The plugin's `/skill-health:update` reads what this finds. False when nothing was
    /// started: no folder is read yet, or a comparison is already running.
    @discardableResult
    func compareSources() async -> Bool {
        guard let engine, state == .loaded, !comparing else { return false }
        let mine = generation
        comparing = true
        defer { if mine == generation { comparing = false } }
        do {
            let file = try await engine.checkSources(skills)
            guard mine == generation else { return true }
            compare = file
            lastWriteError = nil
            // compare.json, and updates.json when stale records were pruned, are Skill Health's own writes
            // here: they must not set off a refresh of what was just read.
            let now = PluginFileStamps(paths: engine.paths)
            seenStamps?.compare = now.compare
            seenStamps?.updates = now.updates
        } catch {
            guard mine == generation else { return true }
            lastWriteError = "Skill Health couldn't save what it found: \(error.localizedDescription)"
            return true
        }
        await refreshCopies(engine: engine, generation: mine)
        await publishStatus(engine: engine, generation: mine)
        return true
    }

    /// The daily comparison, and finishing one that GitHub's hourly limit paused. Never the first:
    /// that one is the person's choice.
    private func compareIfDue(now: Date = .now) async {
        guard settings.dailyCheck, let last = compare.checkedAt else { return }
        if compare.stopped != nil || now.timeIntervalSince(last) >= 24 * 60 * 60 {
            await compareSources()
        }
    }

    // MARK: Usage

    /// Reads usage once for this folder, joining a read already under way rather than starting
    /// a second, then credits the skills and publishes status.json.
    private func refreshUsage() async {
        if let running = usageRead, running.generation == generation {
            await running.task.value
            return
        }
        let mine = generation
        let task = Task { await readUsage(generation: mine) }
        usageRead = (mine, task)
        await task.value
        if usageRead?.generation == mine { usageRead = nil }
    }

    /// "Read Skills Again", from the menu: whatever stopped the last read gets another try.
    func readUsageAgain() {
        guard engine != nil else { return }
        announcesConnection = true   // the button pressed is gone by the time the outcome is known
        Task { await refreshUsage() }
    }

    private func readUsage(generation mine: Int) async {
        guard let engine else { return }
        if usageReport == nil { usage = .reading }
        do {
            let report = try await engine.readUsage()
            guard mine == generation else { return }
            usageReport = report
            skills = skills.map { $0.crediting(report.loads) }
            usage = .read
            recompute()
            announceConnected(report)
            await publishStatus(engine: engine, generation: mine)
        } catch {
            guard mine == generation else { return }
            usage = .failed(error.localizedDescription)
            announceUsageFailed(error.localizedDescription)
        }
    }

    /// The failed counterpart of `announceConnected`, for a read the person asked for. It disarms the flag
    /// too, so a later background success doesn't announce "Connected" nobody asked about.
    private func announceUsageFailed(_ why: String) {
        guard announcesConnection, state == .loaded else { return }
        announcesConnection = false
        AccessibilityNotification.Announcement(SettingsText.usageFailed(why)).post()
    }

    /// Spoken once the folder's result is known, when the person chose it: the button they pressed
    /// is gone by then, so nothing else would say it worked.
    private func announceConnected(_ report: UsageReport) {
        guard announcesConnection, state == .loaded else { return }
        announcesConnection = false
        let count = skills.count == 1 ? "1 skill" : "\(skills.count.formatted()) skills"
        AccessibilityNotification.Announcement("Connected. \(count), \(report.usedPhrase(count: usedCount)).").post()
    }

    // MARK: Claude Code

    /// Opens `command` in Claude Code, typed in and waiting for Return, or copies it and says so
    /// when Claude Code can't be opened from here. Where: the place the person chose in Settings
    /// when it's on this Mac, otherwise the Claude app, then a terminal (see `ClaudeCodeCommand`).
    /// True when it opened. Never for samples: nothing in the menu or the evidence window offers
    /// it, and this refuses it too.
    @discardableResult
    func open(command: String) -> Bool {
        guard !showsSamples, let engine else { return false }
        destinations = ClaudeCodeLauncher.available()
        guard let destination = ClaudeCodeCommand.destination(preferring: preferredDestination, available: destinations) else {
            ClaudeCodeLauncher.copyAndExplain(command)
            return false
        }
        // The person chose Cancel in the note before the first terminal window: nothing opens,
        // and nothing is copied either, since they didn't ask for that.
        if destination == .terminal, !ClaudeCodeLauncher.confirmTerminal(for: command) { return false }
        guard ClaudeCodeLauncher.open(command, in: destination, skillHealthFolder: engine.paths.home) else {
            ClaudeCodeLauncher.copyAndExplain(command)
            return false
        }
        if destination == .terminal { ClaudeCodeLauncher.rememberTerminalNoteShown() }
        if ClaudeCodeCommand.isCheck(command) {
            checkOpenedAt = .now
            findingsStampAtCheck = PluginFileStamps(paths: engine.paths).findings
            tickWhileCheckIsOpened()
        }
        return true
    }

    private func tickWhileCheckIsOpened() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, self.checkOpenedAt != nil else { return }
                self.forgetCheckOpened(now: .now)
                self.clock = .now
            }
        }
    }

    /// A check opened from the menu is forgotten once its results landed or two hours have passed.
    private func forgetCheckOpened(now: Date) {
        guard let opened = checkOpenedAt else { return }
        if findingsChangedSinceCheck || now.timeIntervalSince(opened) >= 2 * 60 * 60 {
            checkOpenedAt = nil
            findingsStampAtCheck = nil
        }
    }

    // MARK: Settings and status

    /// Saves the settings. Only the daily comparison is the app's to change now; the other two
    /// switches in the file are kept as they were, for older readers.
    func saveSettings() async {
        guard let engine, state == .loaded else { return }
        let mine = generation
        do {
            try await engine.saveSettings(settings)
            guard mine == generation else { return }
            lastWriteError = nil
        } catch {
            guard mine == generation else { return }
            lastWriteError = "Skill Health couldn't save your settings: \(error.localizedDescription)"
        }
    }

    private func recompute() {
        // The checks' findings, the known corrections and the person's decisions, joined by the same
        // function the plugin's tool uses, so the menu and /skill-health:fix never disagree.
        findingsFile = FindingsJoin.join(audit: savedFindings, shared: sharedFindings, sharedChecked: sharedChecked, trees: trees,
                                         decisions: decisions, compare: compare, skills: skills)
        urgentFindings = Urgency.findings(findingsFile.findings, skills: skills)
        safeUpdateCount = skills.count(where: \.isSafeUpdate)
        #if DEBUG
        // -debugShowFinding YES: the sample finding, so its window can be checked before any check runs.
        if DebugSnapshot.showsFinding, !findingsFile.findings.contains(where: { $0.id == Finding.sample.id }) {
            findingsFile.findings.append(Finding.sample)
        }
        let samples = UserDefaults.standard.integer(forKey: "debugSampleFindings")
        if samples > 0 { urgentFindings = Finding.samples(samples) }
        #endif
    }

    /// Writes status.json for the folder this pass started with, never a newer one.
    private func publishStatus(engine: Engine, generation mine: Int) async {
        // A debug launch's sample findings stay on screen: they never reach status.json or the
        // plugin's files, which Claude Code reads.
        let real = findingsFile.findings.filter { !$0.isSample }
        let snapshot = StatusSnapshot.make(findings: real, skills: skills)
        do {
            try await engine.writeStatus(snapshot)
            // For the one release /skill-health:audit stays as an alias of /skill-health:check. Not while the
            // results can't be read: the plan would say nothing was ever checked.
            if !findingsUnreadable { try await engine.writeAuditPlan(skills: skills, audited: savedFindings.audited) }
            guard mine == generation else { return }
            lastWriteError = nil
        } catch {
            guard mine == generation else { return }
            lastWriteError = "Skill Health couldn't save its notes for Claude Code: \(error.localizedDescription)"
        }
    }
}
