import Foundation

/// Holds an AsyncStream continuation behind a C context pointer (see FolderWatcher).
final class ContinuationBox: Sendable {
    let continuation: AsyncStream<Void>.Continuation
    init(_ continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    deinit { continuation.finish() }
}
