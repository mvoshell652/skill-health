import Foundation

/// Whether a skill's folder name may go into a command typed into Claude Code. A folder name comes
/// from the file system, so it can hold spaces, quotes or shell characters; the command is typed in
/// for the person to send, and a name that isn't plainly a name must never ride inside one. The same
/// pattern the plugin's save script and `AuditResults` hold skill names to.
public enum SkillName {
    public static func isValid(_ name: String) -> Bool {
        name.wholeMatch(of: pattern) != nil
    }

    /// A computed property: a `Regex` isn't `Sendable`, so a stored one couldn't be shared.
    private static var pattern: Regex<Substring> { /[A-Za-z0-9][A-Za-z0-9._-]{0,127}/ }
}
