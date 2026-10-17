import SwiftUI
import SkillHealthCore

/// The menu bar extra is a standard menu, not a popover (HIG: "Display a menu — not a popover —
/// when people click your menu bar extra"). It draws what `MenuModel` says and nothing else: every
/// word, count and plural is decided there, where a test can read it.
struct MenuContent: View {
    @Environment(Library.self) private var library
    @Environment(FolderAccess.self) private var folderAccess
    @Environment(WindowActivation.self) private var windows
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let groups = library.menu.groups
        // Sections draw the separators; an explicit Divider next to one doubles the line.
        ForEach(groups.filter { !$0.items.isEmpty }) { group in
            MenuGroupSection(group: group, perform: perform)
        }
        // A header with no items (reading your skills) sits directly above Settings…, so it has
        // something to head; an empty Section may not draw at all.
        MenuFooter(leadingHeader: groups.last { $0.items.isEmpty }?.header, showSettings: { showSettings() }, quit: quit)
    }

    private func perform(_ action: MenuModel.Item.Action) {
        switch action {
        case .openClaudeCode(let command): library.open(command: command)
        case .openEvidence(let skill): showEvidence(of: skill)
        // Setting up or updating the plugin lands on its row; a problem with a file, at the top.
        case .openSetup: showSettings(.plugin)
        case .openSettings: showSettings()
        case .chooseFolder:
            library.chooseFolder(using: folderAccess)
            // A folder that was refused is explained under Needs attention in Settings, which is not open
            // on this path; a cancelled panel leaves no error, so nothing opens.
            if folderAccess.lastError != nil { showSettings() }
        case .readUsageAgain: library.readUsageAgain()
        case .submenu: break
        }
    }

    private func showEvidence(of skill: String) {
        NSApplication.shared.activate()
        openWindow(value: skill)
    }

    private func showSettings(_ target: SettingsTarget? = nil) {
        windows.showSettings(target, using: openWindow)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
