import Foundation

/// Plain-text count phrases for output that isn't rendered by SwiftUI (the hook prints
/// raw text, so SwiftUI's automatic grammar agreement isn't available there).
enum SkillCount {
    /// Subject and list kept apart so the list can follow the predicate, as in spec flow B:
    /// "4 skills you use have" ... "(supabase, gcp-cloud-run and 2 more)".
    static func parts(_ names: [String], verb: (singular: String, plural: String)) -> (subject: String, list: String) {
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        let count = unique.count
        let subject = count == 1 ? "1 skill you use \(verb.singular)" : "\(count) skills you use \(verb.plural)"
        let more = count > 2 ? " and \(count - 2) more" : ""
        return (subject, "(\(unique.prefix(2).joined(separator: ", "))\(more))")
    }
}
