import Foundation

/// This Mac's own checks, turned into shared corrections, so one check serves every identical copy:
/// a skill whose files match a shared "checked" entry counts as up to date and costs nobody tokens.
/// Only a skill whose files are exactly its public source's files is shared, so nothing edited on
/// this Mac, and nothing private, ever leaves it.
extension SharedCorrections {
    public init(updatedAt: Date, corrections: [Correction] = [], checked: [Checked] = []) {
        self.updatedAt = updatedAt
        self.corrections = corrections
        self.checked = checked
    }

    /// Why a skill's own check can't be shared.
    public enum ShareRefusal: String, Sendable, Equatable {
        /// Not installed from a GitHub repository (no receipt): its files may be private.
        case noSource
        /// The last comparison didn't read its source, so "the same as the source" can't be shown.
        case notCompared
        /// Its files differ from its source's: edited here, or behind.
        case differsFromSource
        /// Its files changed since the check, or the check was saved before Skill Health kept fingerprints.
        case changedSinceCheck
        /// No longer installed.
        case notInstalled
    }

    /// These checks added: for each skill checked here that may be shared, a "checked" entry for its
    /// files and a correction for each failing or deprecated instruction its check kept. Earlier
    /// entries for the same files are replaced, since the newer check read them again. Check dates are
    /// kept to the day.
    public func addingChecks(from own: FindingsFile, skills: [Skill], compare: CompareFile, now: Date = .now)
        -> (shared: SharedCorrections, added: [String], refused: [String: ShareRefusal]) {
        var result = self
        var added: [String] = []
        var refused: [String: ShareRefusal] = [:]
        let installed = Dictionary(skills.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for (name, checkedAt) in own.audited.sorted(by: { $0.key < $1.key }) {
            guard let skill = installed[name] else { refused[name] = .notInstalled; continue }
            guard let origin = skill.origin else { refused[name] = .noSource; continue }
            guard let copy = compare.copies[name], copy.repo == origin.repo, copy.subpath == origin.subpath,
                  let source = copy.source else { refused[name] = .notCompared; continue }
            let files = LocalCopy.files(in: skill.folder)
            guard files == source else { refused[name] = .differsFromSource; continue }
            let tree = Self.tree(of: files)
            guard own.trees[name] == tree else { refused[name] = .changedSinceCheck; continue }

            let day = Self.day(checkedAt)
            let blobs = Set(files.values)
            result.checked.removeAll { $0.tree == tree }
            result.checked.append(Checked(tree: tree, skill: name, checkedOn: day))
            result.corrections.removeAll { blobs.contains($0.blob) }
            for finding in own.findings where finding.skillName == name && finding.severity.isUrgent
                && finding.keptBySecondCheck == true && finding.sharedFrom == nil {
                guard let blob = files[finding.filePath] else { continue }
                result.corrections.append(Correction(
                    blob: blob, file: finding.filePath, skill: name, repo: origin.repo, severity: finding.severity,
                    skillSays: finding.skillSays, trueNow: finding.trueNow, source: finding.source,
                    wrongSince: finding.wrongSince.sharedLabel, suggestedText: finding.suggestedText,
                    checkedOn: day, keptBySecondCheck: true))
            }
            added.append(name)
        }
        if !added.isEmpty { result.updatedAt = Self.day(now) }
        result.checked.sort { ($0.skill, $0.tree) < ($1.skill, $1.tree) }
        result.corrections.sort { ($0.skill, $0.file, $0.skillSays) < ($1.skill, $1.file, $1.skillSays) }
        return (result, added, refused)
    }

    static func day(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }
}

extension WrongSince {
    /// The audit's label for this date: written:YYYY-MM-DD, installed:YYYY-MM-DD, since:YYYY-MM-DD or undated.
    public var label: String {
        let style = Date.ISO8601FormatStyle().year().month().day()
        return switch self {
        case .written(let on): "written:" + on.formatted(style)
        case .installed(let on): "installed:" + on.formatted(style)
        case .since(let date): "since:" + date.formatted(style)
        case .undated: "undated"
        }
    }

    /// The label a shared correction carries. An install day is one person's: on another Mac the
    /// same correction would read as when that person installed it, so it is shared undated.
    var sharedLabel: String {
        if case .installed = self { "undated" } else { label }
    }
}
