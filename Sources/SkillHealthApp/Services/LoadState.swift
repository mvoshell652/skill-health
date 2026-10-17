import Foundation

/// Where the library is. Kept apart from "nothing found", so a missing folder, a failed or an
/// unfinished load can never read as an all-clear.
enum LoadState: Equatable {
    case needsFolder
    case loading
    case loaded
    case failed(String)
}
