import Foundation

/// Whether Skill Health knows which skills the person loads. Until it does, nothing it says about
/// "skills you use" can be true, so the views say so instead.
enum UsageState: Equatable {
    case notRead
    case reading
    case read
    /// The session files couldn't be read. The skills still show; urgency waits for usage.
    case failed(String)
}
