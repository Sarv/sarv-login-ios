import Foundation

/// Who the app is, and where Sarv sends the user back.
///
/// Mirrors the web SDK's `SarvLoginConfig` (`@sarv-in/login`): the same
/// defaults, and the same refusal to let `extraParameters` overwrite a
/// parameter the SDK owns.
public struct SarvAuthConfiguration: Sendable, Equatable {

    public static let defaultOAuthURL = URL(string: "https://oauth.sarv.com")!
    public static let defaultScopes = ["openid", "email", "profile"]

    /// Parameters the SDK sets itself; `extraParameters` may not contain them.
    static let reservedParameters: Set<String> = [
        "response_type", "client_id", "redirect_uri", "scope", "state",
        "code_challenge", "code_challenge_method", "nonce",
    ]

    /// Public OAuth client id from the Sarv developer console.
    public let clientId: String
    /// Must match a redirect URI registered for the client exactly — the
    /// server compares the whole string. Use a lowercase private-use scheme
    /// from a domain you own, e.g. `com.example.app:/oauth2redirect` (single
    /// slash). An `https` universal link needs iOS 17.4+ / macOS 14.4+.
    public let redirectURI: URL
    /// Scopes to request. Ask only for what the app uses: the consent screen
    /// lists every one of them.
    public let scopes: [String]
    /// The authorization server.
    public let oauthURL: URL
    /// Extra authorization parameters (`prompt`, `login_hint`, …).
    public let extraParameters: [String: String]
    /// Where Sarv's sign-out page sends the user. Sarv only redirects to an
    /// `https://` URL on the origin of a registered redirect URI, so a
    /// custom-scheme app leaves this nil — `signOut` then makes the next
    /// sign-in ask for the password (`prompt=login`) instead.
    public let postLogoutRedirectURI: URL?

    public init(
        clientId: String,
        redirectURI: URL,
        scopes: [String] = SarvAuthConfiguration.defaultScopes,
        oauthURL: URL = SarvAuthConfiguration.defaultOAuthURL,
        extraParameters: [String: String] = [:],
        postLogoutRedirectURI: URL? = nil
    ) throws {
        guard !clientId.isEmpty else {
            throw SarvAuthError.invalidConfiguration("`clientId` is required.")
        }
        guard let scheme = redirectURI.scheme, !scheme.isEmpty else {
            throw SarvAuthError.invalidConfiguration("`redirectURI` needs a scheme, e.g. com.example.app:/oauth2redirect.")
        }
        guard scheme == scheme.lowercased() else {
            throw SarvAuthError.invalidConfiguration("`redirectURI` scheme must be lowercase.")
        }
        if let postLogoutRedirectURI, postLogoutRedirectURI.scheme?.lowercased() != "https" {
            throw SarvAuthError.invalidConfiguration("`postLogoutRedirectURI` must be an https:// URL — Sarv does not redirect to custom schemes after sign-out.")
        }
        if let reserved = extraParameters.keys.first(where: Self.reservedParameters.contains) {
            throw SarvAuthError.invalidConfiguration("`extraParameters.\(reserved)` is set by the SDK and cannot be overridden.")
        }
        self.clientId = clientId
        self.redirectURI = redirectURI
        self.scopes = scopes.isEmpty ? Self.defaultScopes : scopes
        self.oauthURL = Self.trimmingTrailingSlashes(oauthURL)
        self.extraParameters = extraParameters
        self.postLogoutRedirectURI = postLogoutRedirectURI
    }

    /// The scheme the system sign-in sheet waits for.
    var callbackScheme: String { redirectURI.scheme ?? "" }

    var requestsOpenID: Bool { scopes.contains("openid") }

    func endpoint(_ path: String) -> URL {
        oauthURL.appendingPathComponent(path)
    }

    private static func trimmingTrailingSlashes(_ url: URL) -> URL {
        var string = url.absoluteString
        while string.hasSuffix("/") { string.removeLast() }
        return URL(string: string) ?? url
    }
}
