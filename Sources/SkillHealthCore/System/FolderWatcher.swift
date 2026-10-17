import Foundation
#if canImport(CoreServices)
import CoreServices

/// Tells the app that something under a folder changed, so it can refresh. FSEvents is a
/// C API that requires a Dispatch queue to deliver on; that queue only forwards a signal
/// into an AsyncStream. It is the one place Skill Health touches Dispatch.
///
/// `@unchecked Sendable`: the stream reference is only touched in `init` and `deinit`,
/// which can't run concurrently with anything else on the same instance.
public final class FolderWatcher: @unchecked Sendable {
    /// One element per batch of changes. Bursts coalesce: the app refreshes everything anyway.
    public let changes: AsyncStream<Void>
    private let stream: FSEventStreamRef

    /// Returns nil if FSEvents won't watch the folder, so the caller can say so.
    public init?(watching folder: URL, latency: TimeInterval = 2) {
        let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // FSEvents retains this box for as long as the stream exists (the retain/release
        // callbacks below), so a callback can never outlive what it writes to.
        let box = Unmanaged.passRetained(ContinuationBox(continuation))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<ContinuationBox>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<ContinuationBox>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ContinuationBox>.fromOpaque(info).takeUnretainedValue().continuation.yield()
        }
        let created = FSEventStreamCreate(nil, callback, &context, [folder.path(percentEncoded: false)] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        box.release()   // the stream holds its own reference now, or creation failed
        guard let created else { continuation.finish(); return nil }
        FSEventStreamSetDispatchQueue(created, DispatchQueue(label: "skillHealth.fsevents"))
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            continuation.finish()
            return nil
        }
        self.changes = changes
        self.stream = created
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
#endif
