import Foundation

/// Tokens from Sarv's token endpoint, with the expiry turned into a date.
public struct SarvTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    /// Rotates on every refresh — the SDK stores the new one for you.
    public let refreshToken: String?
    /// Present when `openid` was granted. A statement about the sign-in, not a
    /// credential: never send it to an API as a bearer token.
    public let idToken: String?
    public let scope: String?
    public let expiresAt: Date

    public init(accessToken: String, tokenType: String = "Bearer", refreshToken: String?,
                idToken: String?, scope: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.scope = scope
        self.expiresAt = expiresAt
    }

    /// True when the access token is expired or within `leeway` of expiring.
    public func isExpired(leeway: TimeInterval = 60, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }

    /// The signed-in user as stated by the ID token (or, failing that, the
    /// access token): `sub`, `email`, `name` by scope.
    public var user: SarvUser? {
        let claims = idToken.flatMap(JWT.payload) ?? JWT.payload(accessToken)
        return claims.flatMap(SarvUser.init(claims:))
    }
}

/// Wire format of `/api/oauth/token`.
struct TokenResponse: Decodable {
    let access_token: String
    let token_type: String?
    let expires_in: Double?
    let refresh_token: String?
    let id_token: String?
    let scope: String?

    func tokens(now: Date = Date(), previousRefreshToken: String? = nil) -> SarvTokens {
        SarvTokens(accessToken: access_token,
                   tokenType: token_type ?? "Bearer",
                   refreshToken: refresh_token ?? previousRefreshToken,
                   idToken: id_token,
                   scope: scope,
                   expiresAt: now.addingTimeInterval(expires_in ?? 3600))
    }
}

/// Who signed in. `sub` is the stable key to store — it survives email and
/// name changes. Sarv exposes no roles or permissions.
public struct SarvUser: Codable, Equatable, Sendable {
    public let sub: String
    public let email: String?
    public let emailVerified: Bool?
    public let name: String?
    public let profile: String?
    public let phoneNumber: String?
    public let phoneNumberVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case sub, email, name, profile
        case emailVerified = "email_verified"
        case phoneNumber = "phone_number"
        case phoneNumberVerified = "phone_number_verified"
    }

    init?(claims: [String: Any]) {
        guard let sub = claims["sub"] as? String else { return nil }
        self.sub = sub
        email = claims["email"] as? String
        emailVerified = claims["email_verified"] as? Bool
        name = claims["name"] as? String
        profile = claims["profile"] as? String
        phoneNumber = claims["phone_number"] as? String
        phoneNumberVerified = claims["phone_number_verified"] as? Bool
    }
}

/// What a successful `signIn` returns.
public struct SarvSignInResult: Sendable {
    public let tokens: SarvTokens
    /// From the ID token; call `fetchUser()` for the full userinfo profile.
    public let user: SarvUser?
}
