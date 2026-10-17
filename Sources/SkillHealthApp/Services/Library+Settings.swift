import SkillHealthCore

/// What the settings window needs to know that isn't the library's own business.
extension Library {
    /// Where the Claude folder stands, in the settings window's terms. Sample skills are a state of
    /// their own: a folder that is ready, but isn't the person's.
    var folderStage: SettingsText.Folder {
        switch state {
        case .needsFolder: .notChosen
        case .loading: .reading
        case .failed: .failed
        case .loaded: isSample ? .sample : .ready
        }
    }

    /// What reading which skills are used has made of the folder, for the lines under its path.
    var usageLine: SettingsText.UsageLine {
        switch usage {
        case .notRead, .reading:
            return .reading
        case .read:
            let phrase = usageReport?.usedPhrase(count: usedCount) ?? ""
            return .read(usedPhrase: phrase, caveat: usageReport.flatMap { SettingsText.coverageCaveat($0) })
        case .failed(let why):
            return .failed(why)
        }
    }
}
