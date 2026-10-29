import CryptoKit
import Foundation
import Security

/// PKCE primitives (RFC 7636), S256 only — `plain` is deliberately absent.
/// Sizes match the web SDK: 32-byte verifier (43 chars), 16-byte state/nonce.
enum PKCE {

    static func verifier() -> String { base64url(randomBytes(32)) }
    static func state() -> String { base64url(randomBytes(16)) }
    static func nonce() -> String { base64url(randomBytes(16)) }

    /// base64url(SHA-256(verifier)).
    static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// RFC 4648 §5: no padding, `-` and `_` for `+` and `/`.
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed (\(status))")
        return Data(bytes)
    }
}
