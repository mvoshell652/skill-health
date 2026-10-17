import Foundation
import SkillHealthCore

// The commands that only read: version, status, findings, plan, usage, and save-findings (which
// writes only Skill Health's own results file, under the same rules as the plugin's save script).

extension Tool {
    /// "Skill Health 0.4.0 (abc1234)": the commit is the one plugin/bin/BUILT_FROM records beside the
    /// binary. A build from source has none.
    func version() {
        let beside = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().appending(path: "BUILT_FROM")
        let commit = beside.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .split(whereSeparator: \.isWhitespace).first.map { String($0.prefix(7)) }
        print("Skill Health \(Self.version)" + (commit.map { " (\($0))" } ?? ""))
    }

    // MARK: status

    func status() async {
        requireSkillsFolder()
        let view = await overview()
        let used = view.used
        let urgent = view.urgent
        var bySkill: [String: (failing: Int, deprecated: Int)] = [:]
        for finding in urgent {
            var entry = bySkill[finding.skillName] ?? (0, 0)
            if finding.severity == .breaks { entry.failing += 1 } else { entry.deprecated += 1 }
            bySkill[finding.skillName] = entry
        }
        let loads = Dictionary(view.skills.map { ($0.name, $0.usesLast90Days) }, uniquingKeysWith: { a, _ in a })
        let ordered = bySkill.sorted { lhs, rhs in
            (lhs.value.failing, loads[lhs.key] ?? 0, rhs.key) > (rhs.value.failing, loads[rhs.key] ?? 0, lhs.key)
        }
        let failing = urgent.count { $0.severity == .breaks }
        let deprecated = urgent.count - failing
        let checked = used.count { view.checkedOn($0.name) != nil }
        let newer = view.skills.count(where: \.isSafeUpdate)
        let lowerBound = !(view.usage?.coversWindow ?? false)
        let aside = view.setAside()
        let compared = view.compareProblems
        let usageProblem = view.usageProblem.map { "Skill Health couldn't read which skills you use: \($0)" }
        let now = Date.now
        let due = inPlanOrder(view, now: now).filter { !view.isUpToDate($0.name, now: now) }
        let correctionsProblem = sharedRead.problem
        let problems = [view.skillsProblem, view.findingsProblem, correctionsProblem, view.decisionsProblem, usageProblem, view.compareProblem]
            .compactMap(\.self)

        if json {
            printObject([
                "skills": view.skills.count, "used": used.count, "usedIsLowerBound": lowerBound,
                "checkedUsed": checked, "failing": failing, "deprecated": deprecated,
                "setAsideFailing": aside.failing, "setAsideDeprecated": aside.deprecated,
                "bySkill": ordered.map { ["skill": $0.key, "failing": $0.value.failing, "deprecated": $0.value.deprecated, "loads": loads[$0.key] ?? 0] },
                // The skills a check would offer first, so a skill can say what is due without the whole plan.
                "due": due.count,
                "dueSkills": due.prefix(8).map { skill -> [String: Any?] in
                    ["skill": skill.name, "checkedOn": view.checkedOn(skill.name), "checkedDay": view.checkedOn(skill.name).map(Self.dayOf)]
                },
                "newerCopies": newer, "withSource": view.skills.count { $0.origin != nil },
                "comparedAt": view.compare.checkedAt, "comparedProblems": compared.count,
                "compareStopped": view.compare.stopped,
                // One field per file, so a skill can tell which answer it can't trust.
                "skillsProblem": view.skillsProblem, "findingsProblem": view.findingsProblem, "correctionsProblem": correctionsProblem,
                "decisionsProblem": view.decisionsProblem, "usageProblem": usageProblem, "compareProblem": view.compareProblem,
            ])
            return
        }
        let skillCount = Self.plural(view.skills.count, "skill", "skills")
        if let usage = view.usage {
            print("\(skillCount), \(usage.usedPhrase(count: used.count)).")
        } else {
            print("\(skillCount). Which of them you use isn't known.")
        }
        if let note = view.usage?.coverageNote { print(note) }
        // What was checked, and what was found, can't be said while the results can't be read.
        if !view.findingsUnreadable {
            if !used.isEmpty { print(Self.checkedLine(checked: checked, used: used.count, lowerBound: lowerBound)) }
            if !urgent.isEmpty {
                print("\(Self.counts(failing: failing, deprecated: deprecated)) in \(Self.plural(bySkill.count, "skill", "skills")) you use:")
                for (skill, entry) in ordered {
                    print("  \(Self.shown(skill)): \(Self.counts(failing: entry.failing, deprecated: entry.deprecated))")
                }
            } else if checked > 0, view.findingsProblem == nil, correctionsProblem == nil {
                // Never an all-clear while an entry couldn't be read; "open" while some are set aside.
                let open = aside.failing + aside.deprecated > 0 ? "open " : ""
                print("No \(open)failing or deprecated instructions in the \(checked == 1 ? "skill" : "skills") you use that \(checked == 1 ? "is" : "are") checked.")
            }
            if let line = Self.setAsideLine(failing: aside.failing, deprecated: aside.deprecated) { print(line) }
        }
        if newer > 0 { print(newer == 1 ? "1 skill you use has a newer copy at its source." : "\(newer) skills you use have newer copies at their sources.") }
        if let at = view.compare.checkedAt { print("Last compared with GitHub \(Self.ago(at)).") }
        if let sentence = compared.sentence { print(sentence) }
        if let paused = Self.pausedLine(view.compare) { print(paused) }
        for problem in problems { print(problem) }
    }

    // MARK: findings

    func findings() async throws {
        requireSkillsFolder()
        let view = await overview()
        // Without the results or the decisions, "nothing to fix" could be untrue.
        if let problem = view.blockingProblem { Self.fail(problem) }
        let named = operands(after: 1).first
        var list: [Finding]
        if let named {
            guard view.skill(named: named) != nil else { Self.fail("There's no skill called \(named) in \(paths.skills.path(percentEncoded: false)).") }
            list = view.findings.findings.filter { $0.skillName == named && $0.isOpen() }
        } else {
            list = view.urgent
        }
        let loads = Dictionary(view.skills.map { ($0.name, $0.usesLast90Days) }, uniquingKeysWith: { a, _ in a })
        list.sort { ($0.severity.rank, -(loads[$0.skillName] ?? 0), $0.skillName) < ($1.severity.rank, -(loads[$1.skillName] ?? 0), $1.skillName) }
        let failing = list.count { $0.severity == .breaks }
        let deprecated = list.count { $0.severity == .deprecated }
        let aside = view.setAside(skill: named)
        // Results that couldn't be read, or known corrections that couldn't: either may have held an
        // open instruction, so neither allows an all-clear.
        let resultsProblem = [view.findingsProblem, sharedRead.problem].compactMap(\.self).joined(separator: " ").nilIfEmpty

        if json {
            var object: [String: Any?] = [
                "findings": list.map { describe($0, in: view) }, "failing": failing, "deprecated": deprecated,
                // Old-version and cosmetic findings, which only a named skill lists.
                "other": list.count - failing - deprecated, "skills": Set(list.map(\.skillName)).count,
                "setAsideFailing": aside.failing, "setAsideDeprecated": aside.deprecated,
                "problem": resultsProblem,
            ]
            // Null when the skill was never checked; a skill's own "nothing to fix" depends on it.
            if let named { object.updateValue(view.checkedOn(named), forKey: "checkedOn") }
            printObject(object)
            return
        }
        guard !list.isEmpty else {
            let setAsideLine = Self.setAsideLine(failing: aside.failing, deprecated: aside.deprecated)
            // An entry that couldn't be read might have been the open one: no all-clear, only what is known.
            if let problem = resultsProblem {
                if let setAsideLine { print(setAsideLine) }
                print(problem)
                return
            }
            let checked = view.used.count { view.checkedOn($0.name) != nil }
            let unchecked = view.used.count - checked
            if let named {
                if let on = view.checkedOn(named) {
                    print(setAsideLine.map { "Nothing open to fix in \(named). \($0)" } ?? "Nothing to fix in \(named). It was last checked \(Self.dayOf(on)).")
                } else if let setAsideLine {
                    // A known correction can be set aside before the skill was ever checked.
                    print("Nothing open to fix in \(named). \(setAsideLine)")
                } else if view.skill(named: named)?.isUsed == true {
                    print("\(named) hasn't been checked yet. Run /skill-health:check \(named).")
                } else {
                    print("\(named) isn't one of the skills you use, so /skill-health:check doesn't cover it.")
                }
            } else if view.used.isEmpty {
                print("\(Self.noneUsedLine(view.usage)), so there's nothing to fix.")
            } else if checked == 0, setAsideLine == nil {
                print("Nothing is checked yet, so there's nothing to fix. Run /skill-health:check.")
            } else {
                if let setAsideLine {
                    print("Nothing open to fix. \(setAsideLine)")
                } else {
                    print("Nothing to fix. No failing or deprecated instructions in the \(Self.plural(checked, "skill", "skills")) you use that \(checked == 1 ? "is" : "are") checked.")
                }
                if unchecked > 0 {
                    print("\(Self.uncheckedLine(unchecked, lowerBound: !(view.usage?.coversWindow ?? false))) Run /skill-health:check.")
                }
            }
            return
        }
        for finding in list {
            let item = describe(finding, in: view)
            print("[\(finding.id.uuidString)] \(Self.shown(finding.skillName)) · \(Self.shown(finding.filePath)) · \(Self.severityWord(finding.severity))")
            print("  The skill says: \(finding.skillSays)")
            print("  True now: \(finding.trueNow)")
            print("  Evidence: \(finding.source.absoluteString)")
            print("  \(Self.wrongSince(finding.wrongSince)). \(Self.provenance(finding)).")
            if let suggested = finding.suggestedText { print("  Suggested: \(suggested)") }
            print("  Choices: \((item["choices"] as? [String] ?? []).joined(separator: ", "))")
            print("")
        }
        if let problem = resultsProblem { print(problem) }
    }

    /// One finding as the plugin's commands read it (the JSON contract in the spec).
    func describe(_ finding: Finding, in view: Overview) -> [String: Any?] {
        let skill = view.skill(named: finding.skillName)
        var choices: [String] = []
        let file = skill.map { $0.folder.appending(path: finding.filePath) }
        let canWrite = file.map { FileManager.default.isWritableFile(atPath: $0.path(percentEncoded: false)) } ?? false
        choices.append(finding.suggestedText != nil && canWrite ? "fix" : "write")
        choices.append("set-aside")
        if let repo = skill?.origin?.repo, GitHubSource.isValidRepo(repo) { choices.append("issue") }
        choices.append("another")
        let decision = view.decisions[finding.id]
        let lapsed = view.lapse(of: finding)?.rawValue
        return [
            "id": finding.id.uuidString, "skill": finding.skillName, "severity": finding.severity.rawValue,
            "file": finding.filePath, "says": finding.skillSays, "trueNow": finding.trueNow,
            "evidence": finding.source.absoluteString, "wrongSince": Self.wrongSince(finding.wrongSince),
            "provenance": Self.provenance(finding), "loads": skill?.usesLast90Days ?? 0,
            "suggested": finding.suggestedText,
            "alternative": finding.alternative.flatMap { view.skill(named: $0) == nil ? nil : $0 },
            "choices": choices, "upstream": upstream(finding, in: view),
            "decision": decision.flatMap { decision -> [String: Any?]? in
                switch decision.status {
                case .open: nil
                case .patched(let on): ["status": "patched", "on": on, "until": nil, "skill": nil, "lapsed": lapsed]
                case .setAside(let until): ["status": "setAside", "on": decision.decidedAt, "until": until, "skill": nil, "lapsed": lapsed]
                case .usingAnotherSkill(let name): ["status": "usingAnotherSkill", "on": decision.decidedAt, "until": nil, "skill": name, "lapsed": lapsed]
                case .notForThisProject: ["status": "setAside", "on": decision.decidedAt, "until": nil, "skill": nil, "lapsed": lapsed]
                }
            },
        ]
    }

    /// Whether the skill's source still has the same file, for what an update could do about a line:
    /// "same" means it can't fix it, "differs" means it might, "fileRemoved" means the source dropped
    /// this file (and "skillRemoved" the whole skill), and "unknown" means Skill Health has no comparison.
    func upstream(_ finding: Finding, in view: Overview) -> String {
        guard let skill = view.skill(named: finding.skillName), let origin = skill.origin,
              let copy = view.compare.copies[finding.skillName],
              copy.repo == origin.repo, copy.subpath == origin.subpath else { return "unknown" }
        guard let source = copy.source else { return "skillRemoved" }
        guard let theirs = source[finding.filePath] else { return "fileRemoved" }
        let ours = (try? Data(contentsOf: skill.folder.appending(path: finding.filePath))).map(GitBlob.id(of:))
        return ours == theirs ? "same" : "differs"
    }

    // MARK: plan

    /// The skills you use in the order a check offers them. Due first: never checked (most loaded
    /// first), then checked longest ago, including skills that changed since. Then the up-to-date
    /// ones a check leaves out, soonest due first.
    func inPlanOrder(_ view: Overview, now: Date) -> [Skill] {
        view.used.sorted { lhs, rhs in
            let (lhsDue, rhsDue) = (view.isUpToDate(lhs.name, now: now) ? view.recheckDue(lhs.name) : nil,
                                    view.isUpToDate(rhs.name, now: now) ? view.recheckDue(rhs.name) : nil)
            switch (lhsDue, rhsDue) {
            case (nil, _?): return true
            case (_?, nil): return false
            case (let a?, let b?): return (a, lhs.name) < (b, rhs.name)
            case (nil, nil): break
            }
            switch (view.checkedOn(lhs.name), view.checkedOn(rhs.name)) {
            case (nil, nil): return (lhs.usesLast90Days, rhs.name) > (rhs.usesLast90Days, lhs.name)
            case (nil, _): return true
            case (_, nil): return false
            case (let a?, let b?): return a < b
            }
        }
    }

    func plan() async {
        requireSkillsFolder()
        let view = await overview()
        // A check saves into the results file: stop before it spends anything if that would be refused.
        // Unreadable decisions don't stop it, since a check never writes them.
        if let problem = view.checkBlockingProblem { Self.fail(problem) }
        let now = Date.now
        let skills = inPlanOrder(view, now: now)
        let entries: [[String: Any?]] = skills.map { skill in
            let size = AuditPlanFile.sizes(of: skill.folder)
            return ["name": skill.name, "loads": skill.usesLast90Days, "checkedOn": view.checkedOn(skill.name),
                    "upToDate": view.isUpToDate(skill.name, now: now), "recheckDue": view.recheckDue(skill.name),
                    "tokens": AuditPlan.tokens(bytes: size.bytes),
                    "files": size.files, "bytes": size.bytes, "folder": skill.folder.standardizedFileURL.path(percentEncoded: false),
                    "repo": skill.origin?.repo, "installedAt": skill.origin?.installedAt]
        }
        if json {
            printObject(["skills": entries])
            return
        }
        let unchecked = skills.count { view.checkedOn($0.name) == nil }
        let upToDate = skills.count { view.isUpToDate($0.name, now: now) }
        let lowerBound = !(view.usage?.coversWindow ?? false)
        guard !skills.isEmpty else {
            print("\(Self.noneUsedLine(view.usage)).")
            return
        }
        let line = Self.checkedLine(checked: skills.count - unchecked, used: skills.count, lowerBound: lowerBound)
        let unchanged = upToDate == 0 ? "" : " \(upToDate == 1 ? "1 hasn't" : "\(upToDate.formatted()) haven't") changed since a check in the last 90 days, so a check leaves \(upToDate == 1 ? "it" : "them") out."
        print(line + unchanged + " A check costs about \(AuditPlan.tokens(bytes: 0).formatted(.number.locale(Self.english))) tokens a skill, more for large ones.")
        for skill in skills.prefix(12) {
            let checked = view.checkedOn(skill.name).map { "checked \(Self.dayOf($0))" + (view.isUpToDate(skill.name, now: now) ? ", unchanged since" : "") } ?? "never checked"
            let tokens = AuditPlan.tokens(bytes: AuditPlanFile.sizes(of: skill.folder).bytes)
            print("  \(Self.shown(skill.name)): loaded \(skill.usesLast90Days == 1 ? "once" : "\(skill.usesLast90Days) times"), \(checked), about \(tokens.formatted(.number.locale(Self.english))) tokens")
        }
        if skills.count > 12 { print("  and \((skills.count - 12).formatted()) more") }
    }

    // MARK: save-findings

    /// The results of /skill-health:check, as JSON on stdin, in the shape save-findings.sh takes. Every
    /// refusal begins "Nothing saved" and names the rule broken, with the JSON field's name, so
    /// Claude can fix that one thing and run it again.
    func saveFindings() async throws {
        guard operands(after: 1).first == "-" else { Self.usageError("Pass the results as JSON on standard input: skill-health save-findings -") }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        struct Input: Decodable {
            struct Finding: Decodable {
                let skillName: String, severity: String, skillSays: String, trueNow: String, source: URL
                let wrongSince: String?, file: String?, suggestedText: String?, alternative: String?
                let keptBySecondCheck: Bool?
            }
            let audited: [String]
            let findings: [Finding]
        }
        let input: Input
        do { input = try JSONDecoder().decode(Input.self, from: data) } catch let error as DecodingError {
            Self.fail("Nothing saved: \(Self.explain(error)).")
        } catch {
            Self.fail("Nothing saved: the results aren't JSON (\(error.localizedDescription)).")
        }
        // A skill that isn't installed, or a quote that isn't in its file, can't be fixed; refusing the
        // whole save would lose an expensive check, so those are left out and named.
        let view = await overview()
        var notes: [String] = []
        var audited: [String] = []
        for name in input.audited {
            if view.skill(named: name) != nil { audited.append(name) } else {
                notes.append("\(Self.shown(name)) isn't installed, so it wasn't saved as checked.")
            }
        }
        var kept: [AuditResults.Kept] = []
        for (index, finding) in input.findings.enumerated() {
            guard let severity = Severity(rawValue: finding.severity) else {
                Self.fail("Nothing saved: finding \(index): \(AuditResults.severityRule).")
            }
            guard finding.keptBySecondCheck == true else {
                Self.fail("Nothing saved: finding \(index): \(AuditResults.keptRule).")
            }
            kept.append(.init(skillName: finding.skillName, severity: severity, skillSays: finding.skillSays, trueNow: finding.trueNow,
                              source: finding.source, wrongSince: finding.wrongSince,
                              file: finding.file == "SKILL.md" ? nil : finding.file,
                              suggestedText: finding.suggestedText, alternative: finding.alternative))
        }
        // The shape rules first, so a malformed result is refused with the rule it broke.
        if let problem = AuditResults(audited: input.audited, findings: kept).problem { Self.fail("Nothing saved: \(problem).") }
        guard !audited.isEmpty else { Self.fail("Nothing saved: none of the skills in audited is installed.") }
        kept = kept.enumerated().compactMap { index, finding in
            var finding = finding
            let file = finding.file ?? "SKILL.md"
            guard let skill = view.skill(named: finding.skillName), audited.contains(finding.skillName) else {
                notes.append("Finding \(index) wasn't saved: \(Self.shown(finding.skillName)) isn't installed.")
                return nil
            }
            guard let data = try? Data(contentsOf: skill.folder.appending(path: file)), let text = SkillText.exact(data),
                  text.contains(finding.skillSays) else {
                notes.append("Finding \(index) wasn't saved: its quote isn't in \(Self.shown(finding.skillName))/\(Self.shown(file)).")
                return nil
            }
            // "Already wrong when installed" shows the install day as fact, so it has to be the day this
            // copy was installed. Any other day is dropped rather than shown.
            if let label = finding.wrongSince, label.hasPrefix("installed:") {
                let day = String(label.dropFirst("installed:".count))
                let installed = skill.origin.map { $0.installedAt.formatted(Date.ISO8601FormatStyle().year().month().day()) }
                if day != installed {
                    let name = Self.shown(finding.skillName)
                    let why = installed.map { "\(name) was installed on \($0), not \(day)." } ?? "\(name) has no install date."
                    notes.append("Finding \(index) was saved without a date: \(why)")
                    finding.wrongSince = nil
                }
            }
            return finding
        }
        let results = AuditResults(audited: audited, findings: kept)
        do { try await engine.save(results) } catch let error as SkillHealthError {
            switch error {
            case .auditRejected(let problem): Self.fail("Nothing saved: \(problem).")
            default: Self.fail("Nothing saved. \(error.plainDescription)")
            }
        } catch {
            Self.fail("Nothing saved. \(error.localizedDescription)")
        }
        // What was kept: the same line reported twice is one finding.
        let counts = results.savedCounts
        print("Saved \(Self.plural(counts.findings, "finding", "findings")) for \(Self.plural(counts.skills, "checked skill", "checked skills")).")
        for note in notes { print(note) }
    }

    /// Which part of the results JSON is wrong, by its place in it: "findings[2] has no skillName".
    static func explain(_ error: DecodingError) -> String {
        func place(_ path: [any CodingKey]) -> String {
            path.reduce("") { text, key in key.intValue.map { "\(text)[\($0)]" } ?? (text.isEmpty ? key.stringValue : "\(text).\(key.stringValue)") }
        }
        // What the results are made of, at the top: a list or a number there is not it.
        let shape = "the results must be a JSON object with audited and findings"
        func kind(_ type: any Any.Type) -> String {
            switch type {
            case is String.Type: "text"
            case is Bool.Type: "true or false"
            case is Array<Any>.Type: "a list"
            case is Dictionary<String, Any>.Type: "an object"
            default: "a different kind of value"
            }
        }
        switch error {
        case .keyNotFound(let key, let context):
            let at = place(context.codingPath)
            return at.isEmpty ? "the results have no \(key.stringValue)" : "\(at) has no \(key.stringValue)"
        case .typeMismatch(let type, let context):
            return context.codingPath.isEmpty ? shape : "\(place(context.codingPath)) must be \(kind(type))"
        case .valueNotFound(_, let context):
            return context.codingPath.isEmpty ? shape : "\(place(context.codingPath)) can't be null"
        case .dataCorrupted(let context):
            guard let last = context.codingPath.last else { return "the results aren't valid JSON" }
            return last.stringValue == "source" ? "\(place(context.codingPath)) must be an https link" : "\(place(context.codingPath)) isn't a value Skill Health takes"
        @unknown default:
            return "the results aren't the expected JSON"
        }
    }

    // MARK: usage (a check of the engine against this Mac)

    func usage() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let report = try await engine.readUsage()
        let installed = Set(try await engine.discoverSkills().map(\.name))
        let used = report.loads.keys.filter(installed.contains).count
        print("\(report.usedPhrase(count: used)), \(report.loads.values.reduce(0, +)) loads (read in \(clock.now - started)).")
        if let note = report.coverageNote { print(note) }
        for (name, count) in report.loads.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(10) {
            print("  \(count)\t\(name)")
        }
    }

    // MARK: JSON with explicit nulls

    /// The contract spells out null for a missing value, so a skill can tell "none" from "absent".
    func printObject(_ object: [String: Any?]) {
        guard let data = try? JSONSerialization.data(withJSONObject: Self.plain(object) as Any,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            Self.fail("couldn't write the JSON output.")
        }
        print(String(decoding: data, as: UTF8.self))
    }

    static func plain(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        switch value {
        case let date as Date: return date.formatted(.iso8601)
        case let dict as [String: Any?]: return dict.mapValues { plain($0) }
        case let dict as [String: Any]: return dict.mapValues { plain($0) }
        case let list as [[String: Any?]]: return list.map { plain($0) }
        case let list as [Any?]: return list.map { plain($0) }
        case let list as [Any]: return list.map { plain($0) }
        default: return value
        }
    }
}
