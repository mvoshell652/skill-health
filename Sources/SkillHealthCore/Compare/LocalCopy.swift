import Foundation

/// The files of one installed skill folder, by path inside it, as git blob ids.
enum LocalCopy {
    /// Never part of a skill: openskills' own receipt, Finder's folder settings, and a whole git
    /// checkout's history when a repository was installed as the skill folder itself.
    static let ignoredFiles: Set<String> = [".openskills.json", ".DS_Store"]
    static let ignoredFolders: Set<String> = [".git"]

    static func files(in folder: URL) -> [String: String] {
        var files: [String: String] = [:]
        walk(folder, prefix: "", into: &files)
        return files
    }

    /// Builds each path from the names it walks, never from enumerated URLs, so a folder reached
    /// through a symlink (/var and /private/var) still yields the same relative paths.
    private static func walk(_ folder: URL, prefix: String, into files: inout [String: String]) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for name in names {
            let item = folder.appending(path: name)
            let path = prefix + name
            let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values?.isSymbolicLink == true {
                // Git stores a link as a blob holding its target path.
                if let target = try? fm.destinationOfSymbolicLink(atPath: item.path(percentEncoded: false)) {
                    files[path] = GitBlob.id(of: Data(target.utf8))
                }
            } else if values?.isDirectory == true {
                guard !ignoredFolders.contains(name) else { continue }
                walk(item, prefix: path + "/", into: &files)
            } else if values?.isRegularFile == true, !ignoredFiles.contains(name),
                      let data = try? Data(contentsOf: item, options: .alwaysMapped) {
                files[path] = GitBlob.id(of: data)
            }
        }
    }
}
