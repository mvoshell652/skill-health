import SwiftUI
import SkillHealthCore

@main
struct SkillHealthApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var library: Library
    @State private var folderAccess: FolderAccess
    @State private var windows = WindowActivation()
    /// The person decides whether Skill Health sits in the menu bar (HIG: The menu bar, menu bar extras).
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @State private var loginItem = LoginItem()

    init() {
        let library = Library()
        let folderAccess = FolderAccess()
        if let folder = folderAccess.folder { library.use(claudeFolder: folder, isSample: folderAccess.usingSample) }
        _library = State(initialValue: library)
        _folderAccess = State(initialValue: folderAccess)
        // Info.plist sets LSUIElement in the bundle; this covers an unbundled dev run too.
        NSApplication.shared.setActivationPolicy(.accessory)
        #if DEBUG
        DebugSnapshot.scheduleIfAsked()
        DebugSnapshot.dumpMenuIfAsked()
        #endif
    }

    var body: some Scene {
        // Skill Health's one window: setup, then settings. Opens on first launch, from Settings… (⌘,),
        // and whenever Skill Health is opened with no menu bar icon to reach it by, so it never depends
        // on that icon being shown.
        Window("Skill Health Settings", id: "main") {
            SettingsWindow()
                .environment(library)
                .environment(folderAccess)
                .environment(windows)
                .environment(loginItem)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) { SettingsCommand(windows: windows) }
        }
        .defaultLaunchBehavior(folderAccess.folder != nil && showInMenuBar && !DebugSnapshot.showsWindow ? .suppressed : .presented)

        MenuBarExtra(isInserted: $showInMenuBar) {
            // The modifier reads WindowActivation from the environment, so it goes inside the
            // views that receive it; outside them it finds nothing and SwiftUI stops the app.
            MenuContent()
                .remembersOpenWindow()
                .environment(library)
                .environment(folderAccess)
                .environment(windows)
        } label: {
            let menu = library.menu
            // The one view that is alive whenever the icon is, so Skill Health can open its window
            // when it is opened again with none showing (see AppDelegate).
            StatusIcon(showsDot: menu.showsDot, label: menu.iconLabel)
                .remembersOpenWindow()
                .environment(windows)
        }

        // A skill's page, read-only: what Skill Health knows about it and what a check found, opened from
        // its row in the menu. Fixing and checking happen in Claude Code.
        #if DEBUG
        WindowGroup("Evidence", for: String.self) { $skillName in
            EvidenceWindow(skillName: skillName)
                .environment(library)
                .environment(windows)
        } defaultValue: {
            // -debugEvidenceSkill <name> opens that skill's page instead of the sample's.
            UserDefaults.standard.string(forKey: "debugEvidenceSkill") ?? Finding.sample.skillName
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(DebugSnapshot.showsFinding ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        #else
        WindowGroup("Evidence", for: String.self) { $skillName in
            EvidenceWindow(skillName: skillName)
                .environment(library)
                .environment(windows)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}
