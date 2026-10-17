import Observation
import ServiceManagement
import SkillHealthCore

/// Launch at login through SMAppService. Works from a bundled .app, not from `swift run`.
/// One instance for the app, so the setup window and Settings never disagree; it re-reads the
/// real status whenever Skill Health becomes active, since the person can change it in System Settings.
@Observable
final class LoginItem {
    private(set) var status = SMAppService.Status.notRegistered
    private(set) var lastError: String?
    /// Moves on every attempt to change it, so a switch macOS refused is drawn again from the real
    /// status instead of staying where the person put it.
    private(set) var attempts = 0

    var isOn: Bool {
        _ = attempts
        return status == .enabled
    }
    var needsApproval: Bool { status == .requiresApproval }

    /// Reads the real status first: the window's switch is drawn from this, and must be right in
    /// its first frame.
    init() {
        reload()
    }

    func reload() {
        let current = SMAppService.mainApp.status
        // A change made in System Settings settles any earlier error.
        if current != status { lastError = nil }
        status = current
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = SettingsText.launchAtLoginFailed(turningOn: on, error.localizedDescription)
        }
        attempts += 1
        reload()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
