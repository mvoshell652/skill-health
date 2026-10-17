import Foundation

extension PluginHandshake {
    /// Reads ~/.claude/skill-health/plugin.json. Nil when it is missing or isn't the handshake, never an
    /// error: a missing handshake is a plugin that hasn't connected, not a failure. The time is
    /// read with or without fractional seconds, since the hook is a shell script and `date` has none.
    public static func read(from url: URL) -> PluginHandshake? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return try? decoder.decode(PluginHandshake.self, from: data)
    }
}
