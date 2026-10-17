import Foundation

/// Counts the way the menu and windows print them: "1,639", in English whatever the Mac's region,
/// because the words around a count are English too.
enum NumberText {
    static func count(_ number: Int) -> String {
        number.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }
}
