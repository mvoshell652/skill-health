import CryptoKit
import Foundation

/// Git's id for a file's contents: SHA-1 over "blob <size>\0" and the bytes. The same id GitHub's
/// tree API reports, so a local file and the source's file compare without downloading either.
/// SHA-1 here is git's content address, not a security measure.
public enum GitBlob {
    public static func id(of data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }
}
