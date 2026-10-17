import Foundation

/// The JSON a Claude Code SessionStart command hook prints. `systemMessage` is shown to
/// the person; `additionalContext` reaches Claude only. Printing nothing means silence.
public struct HookOutput: Codable, Sendable, Equatable {
    public struct SpecificOutput: Codable, Sendable, Equatable {
        public var hookEventName = "SessionStart"
        public let additionalContext: String
    }

    public let systemMessage: String?
    public let hookSpecificOutput: SpecificOutput?
}
