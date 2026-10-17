import Accessibility
import SwiftUI
import SkillHealthCore

/// What Skill Health needs from the person, in one short window: what it is for and the next step, then
/// what is wrong, the Claude folder and plugin, the comparison, and the switches for this Mac. It
/// is never a report: what Skill Health found lives in the menu, and a skill's evidence opens in its own
/// window. Fixing, checking and updating happen in Claude Code, so there is nothing to decide here.
/// Every word is decided in `SettingsText`; this lays them out.
struct SettingsForm: View {
    @Environment(Library.self) private var library
    @Environment(FolderAccess.self) private var folderAccess
    @Environment(LoginItem.self) private var loginItem
    @Environment(WindowActivation.self) private var windows
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The switch is here, not only in the menu: when the icon is hidden this window is the
    // way back to it (HIG: don't rely on a menu bar extra being present).
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    /// Counted up to move focus to the plugin row's control (see `PluginRow`).
    @State private var pluginFocusRequest = 0
    /// Whether the person has answered the one-time Launch at login offer (either way).
    @AppStorage("loginOfferAnswered") private var loginOfferAnswered = false

    private var folder: SettingsText.Folder { library.folderStage }

    var body: some View {
        // Above the form, not in it: a grouped form gives every section a card or restyles it as a
        // heading, and this is what the window is saying, not a setting. 30 pt is the form's card
        // inset plus its row inset, so the text lines up with the rows' text.
        VStack(spacing: 0) {
            TopLine(lines: SettingsText.topLines(folder: folder, plugin: library.pluginState, menuBarShown: showInMenuBar))
                .padding(.horizontal, 30)
                .padding(.top, 20)
            settings
        }
    }

    private var settings: some View {
        ScrollViewReader { proxy in
            Form {
                attention
                Section("Claude Code") {
                    FolderRow()
                    if SettingsText.showsPluginRow(folder: folder) {
                        PluginRow(focusRequest: pluginFocusRequest)
                        if SettingsText.showsOpenIn(plugin: library.pluginState, available: library.destinations) {
                            OpenInRow()
                        }
                    }
                }
                if showsLoginOffer {
                    Section {
                        LoginOfferRow(answered: $loginOfferAnswered)
                    }
                }
                if SettingsText.showsCompare(folder: folder) {
                    Section("Newer copies") {
                        CompareRow()
                    }
                }
                Section {
                    NotedToggle("Show Skill Health in the menu bar",
                                note: SettingsText.menuBarNote(shown: showInMenuBar, launchesAtLogin: loginItem.isOn),
                                isOn: $showInMenuBar)
                    LoginItemRow()
                } header: {
                    Text("On this Mac")
                } footer: {
                    Text(SettingsText.comeBack)
                }
            }
            .formStyle(.grouped)
            .onAppear { arrive(at: proxy) }
            .onChange(of: windows.settingsTarget) { arrive(at: proxy) }
            .onChange(of: library.state) { old, new in
                // The folder panel and its button are gone; the next step is the plugin's.
                if old != .loaded, new == .loaded { pluginFocusRequest += 1 }
            }
            .onChange(of: library.pluginState) { old, new in
                if let words = SettingsText.pluginAnnouncement(from: old, to: new) {
                    AccessibilityNotification.Announcement(words).post()
                }
            }
            .onChange(of: showInMenuBar) { _, shown in
                // The icon was the way back to Skill Health; say what is now.
                if !shown {
                    AccessibilityNotification.Announcement(SettingsText.menuBarNote(shown: false, launchesAtLogin: loginItem.isOn)).post()
                }
            }
            .onChange(of: library.settings) {
                Task { await library.saveSettings() }
            }
            .onChange(of: loginItem.isOn || loginItem.needsApproval, initial: true) { _, acted in
                // Using the switch answers the offer too, here or in System Settings (and so does a switch
                // macOS wants approval for): the offer is never made again after that.
                if acted, !offerIsInert { loginOfferAnswered = true }
            }
            // Escape always closes, with or without the bar below.
            .onExitCommand(perform: close)
            // A bar, not a plain inset: when the form scrolls, the system softens the rows passing
            // under Not Now instead of letting them run behind the button.
            .safeAreaBar(edge: .bottom) {
                if SettingsText.showsNotNow(folder: folder) {
                    HStack {
                        Spacer()
                        Button("Not Now", action: close)
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
    }

    // MARK: Needs attention

    /// A debug launch that shows the offer (-debugShowLoginOffer YES) must not write the person's real answer.
    private var offerIsInert: Bool {
        #if DEBUG
        DebugSnapshot.showsLoginOffer
        #else
        false
        #endif
    }

    private var showsLoginOffer: Bool {
        #if DEBUG
        if DebugSnapshot.showsLoginOffer { return true }
        #endif
        return SettingsText.showsLoginOffer(folder: folder, loginOn: loginItem.isOn, answered: loginOfferAnswered)
    }

    @ViewBuilder private var attention: some View {
        let problems = SettingsText.problems([folderAccess.lastError, library.lastWriteError,
                                              library.findingsProblem, library.decisionsProblem])
        if !problems.isEmpty {
            Section("Needs attention") {
                ForEach(problems, id: \.self) { WarningLabel($0) }
            }
        }
    }

    // MARK: Arriving

    /// Where the menu sent the person ("Set Up Claude Code Plugin…"): scrolled to the plugin row, with
    /// focus on its control. The target is cleared once used, so the next visit starts at the top.
    private func arrive(at proxy: ScrollViewProxy) {
        guard let target = windows.settingsTarget else { return }
        windows.settingsTarget = nil
        // A window that was only just made hasn't laid out its rows yet.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            if reduceMotion {
                proxy.scrollTo(target, anchor: .top)
            } else {
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
            if target == .plugin { pluginFocusRequest += 1 }
        }
    }

    private func close() {
        dismissWindow(id: "main")
    }
}

#Preview("Not connected") {
    SettingsForm()
        .environment(Library())
        .environment(FolderAccess())
        .environment(LoginItem())
        .environment(WindowActivation())
}
