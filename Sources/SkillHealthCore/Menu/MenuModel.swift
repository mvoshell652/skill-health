import Foundation

/// The menu bar menu as words: ordered groups of a header and items, plus the icon's label and
/// whether it shows its dot. Everything the menu says is decided here, from a `MenuInput`; the view
/// only draws it. The conventions (reviewed with writing-for-interfaces, checked against the HIG):
///
/// - A header states a fact in sentence case with no final period. A disabled item is never used for
///   a fact: measured at 1.91:1 contrast.
/// - Knowing is free, doing costs tokens (owner decision 2026-10-09): a skill's row is its name, and
///   opens its page in Skill Health, read from what Skill Health already holds. Everything that hands a command
///   to Claude Code sits in one submenu, "Open in Claude Code", so the destination is said once.
/// - Any other item starts with a verb, in title case, without articles. Skill names keep their case.
/// - A second line only adds to its title. VoiceOver reads it after the title: measured 2026-10-09
///   on macOS 27, AppKit's accessibility label for a row is "gcp-cloud-run, 14 failing, 3 deprecated
///   · used 185 times" (SwiftUI's own accessibility label doesn't reach a menu item).
///
/// The footer ("Settings…" and "Quit Skill Health") belongs to the view, since every state ends with it. A
/// group with a header and no items (the "Reading your skills…" state) sits directly above it.
public struct MenuModel: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public enum Action: Equatable, Sendable {
            /// Open Claude Code with this command typed in (never sent), or copy it when Claude Code can't be opened.
            case openClaudeCode(command: String)
            /// Open the read-only evidence window for one skill.
            case openEvidence(skill: String)
            /// Open the setup window, at the plugin step.
            case openSetup
            /// Open the folder panel directly.
            case chooseFolder
            /// Read which skills are used again, now.
            case readUsageAgain
            /// Open the setup window, which says what went wrong.
            case openSettings
            /// Show `children` as a submenu.
            case submenu
        }

        public let id: String
        public let title: String
        public let subtitle: String?
        public let action: Action
        /// The submenu's items, for `.submenu`.
        public let children: [Item]

        public init(id: String, title: String, subtitle: String? = nil, action: Action, children: [Item] = []) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.action = action
            self.children = children
        }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        public let id: String
        public let header: String?
        public let items: [Item]

        public init(id: String, header: String?, items: [Item]) {
            self.id = id
            self.header = header
            self.items = items
        }
    }

    public let groups: [Group]
    /// What VoiceOver says for the menu bar icon.
    public let iconLabel: String
    /// Whether the dot shows on the icon: only while something is failing or deprecated.
    public let showsDot: Bool

    public init(_ input: MenuInput) {
        let layout = MenuLayout(input)
        groups = layout.groups
        iconLabel = layout.iconLabel
        showsDot = layout.showsDot
    }

    /// At most this many skills are listed under a header; the header counts all of them.
    public static let listedSkills = 5

    /// "23 skills you use have newer copies" / "1 skill you use has a newer copy".
    public static func newerCopiesHeader(_ count: Int) -> String {
        count == 1 ? "1 skill you use has a newer copy" : "\(NumberText.count(count)) skills you use have newer copies"
    }

    /// The same for the sample skills, which the person doesn't use: a fact with nothing to do.
    public static func sampleNewerCopiesHeader(_ count: Int) -> String {
        count == 1 ? "1 sample skill has a newer copy" : "\(NumberText.count(count)) sample skills have newer copies"
    }
}
