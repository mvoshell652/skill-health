import Foundation

/// "Tell the author" (flow F): an issue drafted from the evidence, for the person to read, edit
/// and post themselves on GitHub. Skill Health sends nothing; the browser page is the second yes.
public struct IssueDraft: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(finding: Finding) {
        let quote = finding.skillSays.split(whereSeparator: \.isNewline).first.map(String.init) ?? finding.skillSays
        title = "\(finding.skillName): \(quote.count > 60 ? String(quote.prefix(59)) + "…" : quote) is no longer true"
        var lines = [
            "The skill says:", "", "> \(finding.skillSays.replacing("\n", with: "\n> "))", "",
            "True now: \(finding.trueNow)", "",
            "Source: \(finding.source.absoluteString)",
        ]
        if let suggested = finding.suggestedText {
            lines += ["", "Suggested text:", "", "> \(suggested.replacing("\n", with: "\n> "))"]
        }
        lines += ["", "Checked on \(finding.foundOn.formatted(date: .abbreviated, time: .omitted))."]
        body = lines.joined(separator: "\n")
    }

    /// GitHub's new-issue page with the draft filled in. Nil for a repository name that isn't one.
    public func newIssueURL(repo: String) -> URL? {
        guard GitHubSource.isValidRepo(repo), var url = URL(string: "https://github.com/\(repo)/issues/new") else { return nil }
        url.append(queryItems: [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)])
        return url
    }
}
