import Foundation

/// Where the plugin lives in the checkout, and the plugin's real shell scripts run the way Claude
/// Code runs them: `sh`, a bare PATH, the hook's JSON on standard input.
enum PluginFiles {
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var plugin: URL { repo.appending(path: "plugin") }
    static var gate: URL { plugin.appending(path: "scripts/gate.sh") }
    static var sessionStart: URL { plugin.appending(path: "scripts/session-start.sh") }
    static var skills: URL { plugin.appending(path: "skills") }
}

extension URL {
    /// The path without percent-encoding, for environments and file-system calls.
    var plainPath: String { path(percentEncoded: false) }
}

struct PluginScriptRun {
    let status: Int32
    let output: String
    let error: String
}

/// Runs `script` with `sh` and `stdin` on its standard input. The environment is exactly what is
/// passed (plus a bare PATH unless `path` says otherwise), so nothing of the test machine leaks in.
func runPluginScript(_ script: URL, stdin: String, environment: [String: String], path: String = "/usr/bin:/bin") throws -> PluginScriptRun {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = [script.plainPath]
    process.environment = environment.merging(["PATH": path]) { mine, _ in mine }
    let input = Pipe(), output = Pipe(), error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
    input.fileHandleForWriting.write(Data(stdin.utf8))
    try input.fileHandleForWriting.close()
    let out = output.fileHandleForReading.readDataToEndOfFile()
    let err = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return PluginScriptRun(status: process.terminationStatus, output: String(decoding: out, as: UTF8.self), error: String(decoding: err, as: UTF8.self))
}
