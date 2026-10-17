import Accessibility
import AppKit
import SkillHealthCore
import Observation

/// The one grant a sandboxed Skill Health needs: read-write access to the person's ~/.claude folder,
/// chosen once in an open panel and remembered as a security-scoped bookmark. Unsandboxed builds
/// use the same path, so there is one code path for both the Mac App Store and direct downloads.
@Observable
final class FolderAccess {
    private(set) var folder: URL?
    private(set) var lastError: String?
    /// True while Skill Health shows its sample library instead of the person's own folder.
    private(set) var usingSample = false
    private let defaults: UserDefaults
    private static let bookmarkKey = "claudeFolderBookmark"
    private static let sampleKey = "usingSampleLibrary"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Self.sampleKey), let sample = try? SampleLibrary.install() {
            folder = sample
            usingSample = true
        } else {
            folder = resolveBookmark()
        }
    }

    /// Shows the sample library: no grant needed, since it lives in the app's own container.
    @discardableResult
    func useSample() -> Bool {
        lastError = nil
        do {
            let sample = try SampleLibrary.install()
            if !usingSample { folder?.stopAccessingSecurityScopedResource() }
            folder = sample
            usingSample = true
            defaults.set(true, forKey: Self.sampleKey)
            return true
        } catch {
            lastError = "Skill Health couldn't set up its sample skills: \(error.localizedDescription)"
            return false
        }
    }

    /// The real ~/.claude, where the open panel starts.
    static var defaultClaudeFolder: URL { SkillHealthPaths.defaultClaudeHome }

    /// Asks the person to choose their .claude folder. Returns true once access is granted.
    @discardableResult
    func requestAccess() -> Bool {
        // A cancelled or repeated attempt never leaves an old error standing.
        lastError = nil
        let panel = NSOpenPanel()
        panel.message = "Choose your .claude folder so Skill Health can see which skills you use and tell you when one needs a fix."
        panel.prompt = "Allow"
        panel.directoryURL = Self.defaultClaudeFolder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        guard FileManager.default.fileExists(atPath: chosen.appending(path: "skills").path(percentEncoded: false)) else {
            lastError = "That folder has no skills folder inside it. Choose the .claude folder in your home folder."
            return false
        }
        do {
            let bookmark = try chosen.bookmarkData(options: .withSecurityScope)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            // A URL from the open panel is already accessible, and its grant is released by one
            // stop call, so no start here: one start per held URL keeps the count deliberate.
            if !usingSample { folder?.stopAccessingSecurityScopedResource() }
            folder = chosen
            usingSample = false
            defaults.set(false, forKey: Self.sampleKey)
            lastError = nil
            return true
        } catch {
            lastError = "Skill Health couldn't remember that folder: \(error.localizedDescription)"
            return false
        }
    }

    /// VoiceOver doesn't notice a line appearing after the open panel closes, so say it.
    /// Called from each place that asks for access, so a repeat of the same error is spoken too.
    func announceError() {
        guard let lastError else { return }
        AccessibilityNotification.Announcement(lastError).post()
    }

    private func resolveBookmark() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }
}
