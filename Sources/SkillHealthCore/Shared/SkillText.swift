import Foundation

/// A skill file as text, exactly: nothing dropped on the way in, so writing the text back gives the
/// same bytes. Foundation's UTF-8 decoding drops a leading byte-order mark (common from Windows
/// editors), and a file read that way could never match its own bytes when a fix is applied.
public enum SkillText {
    /// The file's text with every byte kept, or nil when it isn't UTF-8.
    public static func exact(_ data: Data) -> String? {
        guard String(data: data, encoding: .utf8) != nil else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return Data(text.utf8) == data ? text : nil
    }
}
