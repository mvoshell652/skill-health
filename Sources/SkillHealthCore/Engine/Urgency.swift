import Foundation

/// The one rule behind the menu bar icon, the panel's first section and the session note:
/// an open Breaks or Deprecated finding in a skill used in the last 90 days. Written once,
/// so the three can't disagree.
public enum Urgency {
    /// Most severe first, then from the skills used most, so the five corrections Claude gets are the
    /// ones it's most likely to need. A skill's own findings keep their order.
    public static func findings(_ findings: [Finding], skills: [Skill], now: Date = .now) -> [Finding] {
        let uses = Dictionary(skills.filter(\.isUsed).map { ($0.name, $0.usesLast90Days) }, uniquingKeysWith: max)
        return findings.enumerated()
            .filter { _, finding in finding.isOpen(at: now) && finding.severity.isUrgent && uses[finding.skillName] != nil }
            .sorted { a, b in
                if a.element.severity != b.element.severity { return a.element.severity < b.element.severity }
                let (usesA, usesB) = (uses[a.element.skillName] ?? 0, uses[b.element.skillName] ?? 0)
                if usesA != usesB { return usesA > usesB }
                if a.element.skillName != b.element.skillName { return a.element.skillName < b.element.skillName }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}
