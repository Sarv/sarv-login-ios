import Foundation

/// Reads a JWT's payload WITHOUT verifying the signature. Only safe for a
/// token that just came back from the token endpoint over TLS — never for a
/// token handed to the app by someone else.
enum JWT {

    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    /// nil when the ID token is fit to trust (signature aside — it came
    /// straight from the token endpoint over TLS), else why not: `iss`, `aud`,
    /// `exp` and, when this sign-in sent one, `nonce`.
    static func idTokenProblem(_ idToken: String?, issuer: String, clientId: String,
                               nonce: String?, now: Date = Date()) -> String? {
        guard let idToken else {
            return nonce == nil ? nil : "the token response has no id_token, but this sign-in asked for one."
        }
        guard let payload = payload(idToken) else {
            return "the id_token in the token response could not be decoded."
        }
        guard payload["iss"] as? String == issuer else {
            return "the id_token was issued by `\(payload["iss"] ?? "nobody")`, not \(issuer)."
        }
        let audience = (payload["aud"] as? [String]) ?? [(payload["aud"] as? String)].compactMap { $0 }
        guard audience.contains(clientId) else {
            return "the id_token is not for this app (`aud`)."
        }
        guard let exp = (payload["exp"] as? NSNumber)?.doubleValue,
              Date(timeIntervalSince1970: exp).addingTimeInterval(60) > now else {
            return "the id_token has expired."
        }
        if let nonce {
            guard let claim = payload["nonce"] as? String, !claim.isEmpty else {
                return "the id_token has no `nonce` claim, but this sign-in sent one."
            }
            guard claim == nonce else {
                return "the id_token's `nonce` does not match this sign-in. The token was minted for a different login."
            }
        }
        return nil
    }
}
