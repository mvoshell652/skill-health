import AppKit

/// Choosing the Claude folder, from the menu or the setup window. Both end in the same two steps:
/// the person grants the folder, then the library reads it.
extension Library {
    /// Opens the folder panel. On a grant, points the library at the folder; the result is spoken
    /// when it's known, since the button that was pressed is gone by then.
    func chooseFolder(using access: FolderAccess) {
        NSApplication.shared.activate()
        guard access.requestAccess(), let folder = access.folder else {
            access.announceError()
            return
        }
        use(claudeFolder: folder, isSample: false, announcing: true)
    }

    /// "Try with Sample Skills": the app's own sample folder, which needs no grant.
    func trySample(using access: FolderAccess) {
        guard access.useSample(), let folder = access.folder else {
            access.announceError()
            return
        }
        use(claudeFolder: folder, isSample: true, announcing: true)
    }
}
