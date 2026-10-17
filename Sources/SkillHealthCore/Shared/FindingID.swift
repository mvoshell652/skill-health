import CryptoKit
import Foundation

/// A finding's id, derived from where the wrong line is: the skill's folder name, the file inside
/// it, and the exact quote. The same wrong line gets the same id however it was found (the plugin's
/// save script, an audit in the app, the shared corrections), so the person's decision carries over
/// and nothing is listed twice. Must match plugin/scripts/save-findings.sh byte for byte: SHA-1 of
/// the compact JSON array [skill, file, quote] (jq -c), shaped like a UUID; a test runs both.
public enum FindingID {
    public static func make(skill: String, file: String, quote: String) -> UUID {
        let key = compactJSON([skill, file, quote])
        let hex = Insecure.SHA1.hash(data: Data(key.utf8)).map { byte in
            let digits = String(byte, radix: 16)
            return byte < 16 ? "0" + digits : digits
        }.joined()
        let h = Array(hex)
        let text = String(h[0..<8]) + "-" + String(h[8..<12]) + "-5" + String(h[13..<16]) + "-a" + String(h[17..<20]) + "-" + String(h[20..<32])
        return UUID(uuidString: text.uppercased())!
    }

    /// jq -c's rendering of an array of strings: no spaces, "/" left as is, control characters as
    /// \n, \t and \u00XX, quotes and backslashes escaped, everything else as UTF-8.
    static func compactJSON(_ strings: [String]) -> String {
        "[" + strings.map { string in
            var out = "\""
            for scalar in string.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                case let c where c.value < 0x20 || c.value == 0x7F:
                    out += String(format: "\\u%04x", c.value)
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out + "\""
        }.joined(separator: ",") + "]"
    }
}
