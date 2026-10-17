import Accessibility
import SwiftUI
import SkillHealthCore

/// Comparing with GitHub. The first comparison is the person's choice: it is the only time Skill Health
/// reaches the network, and the line under the title says what it sends. After that, a daily
/// comparison runs while Skill Health does, unless they turn it off. The line says what the last comparison
/// actually established, in words decided by `SettingsText.compareSummary`; for the sample skills it
/// is the only place the result shows besides the menu.
struct CompareRow: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        LabeledContent {
            // Held in place and dimmed while comparing, rather than swapped for a spinner, so the
            // row doesn't reflow and the button is where the person left it when the comparison ends.
            Button(library.lastCompared == nil ? "Compare Now" : "Compare Again", action: startComparison)
                .disabled(library.comparing)
        } label: {
            Text("Compare with GitHub")
            status
        }
        if library.lastCompared != nil {
            NotedToggle("Compare daily", note: SettingsText.compareDailyNote, isOn: $library.settings.dailyCheck)
        }
    }

    // MARK: The status line

    @ViewBuilder private var status: some View {
        if library.comparing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(SettingsText.comparing)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else {
            // "Compared 5 minutes ago" is read against the clock, so it is drawn again every minute.
            TimelineView(.everyMinute) { context in
                lines(of: summary(at: context.date))
            }
        }
    }

    private func lines(of summary: SettingsText.CompareSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(summary.lines, id: \.self) { line in
                switch summary.tone {
                case .plain:
                    Text(line)
                        .foregroundStyle(.secondary)
                case .paused:
                    Label(line, systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                case .warning:
                    WarningLabel(line)
                }
            }
        }
        // Wraps, never cut off: what it says is the point.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(at now: Date) -> SettingsText.CompareSummary {
        SettingsText.compareSummary(compare: library.compare, skills: library.skills, usageKnown: library.usage == .read,
                                    dailyOn: library.settings.dailyCheck, samples: library.showsSamples, now: now)
    }

    // MARK: Comparing

    /// The first comparison, or any the person starts: said aloud when it starts, since the spinner
    /// and its line are silent, and again when it finishes, since the spinner just disappears.
    private func startComparison() {
        AccessibilityNotification.Announcement(SettingsText.comparing).post()
        Task {
            guard await library.compareSources() else { return }
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    /// The same sentence the line shows, or that what it found couldn't be saved.
    private var spoken: String {
        library.lastWriteError ?? summary(at: .now).spoken
    }
}

#Preview("Not compared yet") {
    Form {
        CompareRow()
    }
    .formStyle(.grouped)
    .environment(Library())
    .frame(width: 520)
}
