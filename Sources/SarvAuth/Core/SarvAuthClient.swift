import AuthenticationServices
import Foundation

/// Login with Sarv for native apps: OAuth 2.1 authorization code + PKCE
/// against `oauth.sarv.com`, in the system sign-in sheet.
///
/// ```swift
/// let config = try SarvAuthConfiguration(clientId: "your-client-id",
///                                        redirectURI: URL(string: "com.example.app://oauth/callback")!)
/// let sarv = SarvAuthClient(configuration: config)
/// let result = try await sarv.signIn()
/// let token = try await sarv.validAccessToken()   // refreshes when needed
/// ```
///
/// One instance per client id; keep it for the app's lifetime so token
/// refreshes are serialised (Sarv rotates refresh tokens, and replaying a used
/// one revokes the whole authorization).
public final class SarvAuthClient: @unchecked Sendable {

    public let configuration: SarvAuthConfiguration
    private let store: SarvTokenStore
    private let http: OAuthHTTP
    private let refresher = RefreshCoordinator()
    private let defaults: UserDefaults
    private var promptLoginKey: String { "com.sarv.auth.promptLogin.\(configuration.clientId)" }

    public init(configuration: SarvAuthConfiguration,
                tokenStore: SarvTokenStore? = nil,
                urlSession: URLSession = .shared,
                userDefaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.store = tokenStore ?? KeychainTokenStore(clientId: configuration.clientId)
        self.http = OAuthHTTP(configuration: configuration, session: urlSession)
        self.defaults = userDefaults
    }

    /// Set by `signOut`: the next shared-session sign-in sends `prompt=login`
    /// so Sarv asks for the password instead of reusing its browser session.
    var promptLoginOnNextSignIn: Bool {
        get { defaults.bool(forKey: promptLoginKey) }
        set { defaults.set(newValue, forKey: promptLoginKey) }
    }

    // MARK: - State

    /// The stored tokens, if any (possibly expired — use `validAccessToken()`).
    public var tokens: SarvTokens? { try? store.load() }

    public var isSignedIn: Bool { tokens != nil }

    /// The signed-in user from the stored ID token, without a network call.
    public var currentUser: SarvUser? { tokens?.user }

    // MARK: - Sign in

    /// Opens Sarv's sign-in page in the system sheet and completes the flow:
    /// `state` check, code exchange, `nonce` check, Keychain storage.
    ///
    /// - Parameters:
    ///   - anchor: window to present over; defaults to the key window.
    ///   - prefersEphemeralSession: true to share nothing with Safari — use it
    ///     for "add another account", otherwise Sarv's browser session signs the
    ///     same person straight back in. Also skips the system "wants to use
    ///     oauth.sarv.com to sign in" alert.
    @MainActor
    public func signIn(anchor: ASPresentationAnchor? = nil,
                       prefersEphemeralSession: Bool = false) async throws -> SarvSignInResult {
        let request = AuthorizationRequest(configuration: configuration,
                                           promptLogin: !prefersEphemeralSession && promptLoginOnNextSignIn)
        let callbackURL = try await WebAuthenticator(anchor: anchor)
            .start(url: request.url, callback: configuration.redirectURI, ephemeral: prefersEphemeralSession)
        let result = try await completeSignIn(request: request, callbackURL: callbackURL)
        promptLoginOnNextSignIn = false
        return result
    }

    func completeSignIn(request: AuthorizationRequest, callbackURL: URL) async throws -> SarvSignInResult {
        let code = try request.code(from: callbackURL)
        let data = try await http.postJSON("api/oauth/token", body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI.absoluteString,
            "code_verifier": request.codeVerifier,
            "client_id": configuration.clientId,
        ])
        let tokens = try Self.decodeTokens(data)
        if configuration.requestsOpenID,
           let problem = JWT.idTokenProblem(tokens.idToken, issuer: configuration.oauthURL.absoluteString,
                                            clientId: configuration.clientId, nonce: request.nonce) {
            throw SarvAuthError.invalidIDToken(problem)
        }
        try store.save(tokens)
        return SarvSignInResult(tokens: tokens, user: tokens.user)
    }

    // MARK: - Tokens

    /// An access token that is valid for at least another minute, refreshing
    /// first if needed. Concurrent callers share one refresh.
    public func validAccessToken() async throws -> String {
        guard let current = tokens else { throw SarvAuthError.notSignedIn }
        if !current.isExpired() { return current.accessToken }
        return try await refresh().accessToken
    }

    /// Forces a refresh. Throws `.sessionExpired` (and clears the stored
    /// tokens) when Sarv rejects the refresh token; keeps them on network errors.
    @discardableResult
    public func refresh() async throws -> SarvTokens {
        try await refresher.run { [self] in
            guard let current = tokens else { throw SarvAuthError.notSignedIn }
            // Another caller may have refreshed while this one waited.
            if !current.isExpired() { return current }
            guard let refreshToken = current.refreshToken else {
                try? store.clear()
                throw SarvAuthError.sessionExpired
            }
            let data: Data
            do {
                data = try await http.postJSON("api/oauth/token", body: [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": configuration.clientId,
                ])
            } catch SarvAuthError.server(let status, _) where status == 400 || status == 401 {
                try? store.clear()
                throw SarvAuthError.sessionExpired
            }
            let refreshed = try Self.decodeTokens(data, previousRefreshToken: refreshToken)
            try store.save(refreshed)
            return refreshed
        }
    }

    /// The OIDC userinfo profile for the signed-in user.
    public func fetchUser() async throws -> SarvUser {
        let token = try await validAccessToken()
        let data = try await http.getJSON("api/oauth/userinfo", bearer: token)
        guard let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = SarvUser(claims: claims) else {
            throw SarvAuthError.invalidResponse("userinfo had no `sub`")
        }
        return user
    }

    // MARK: - Sign out

    /// Revokes one token. `false` means Sarv found nothing to revoke (already
    /// expired or rotated) — not an error. Rate limited to 10/min per IP.
    @discardableResult
    public func revoke(_ token: String, hint: TokenTypeHint? = nil) async throws -> Bool {
        var body: [String: Any] = ["token": token, "client_id": configuration.clientId]
        if let hint { body["token_type_hint"] = hint.rawValue }
        let data = try await http.postJSON("api/oauth/revoke", body: body)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["revoked"] as? Bool == true
    }

    public enum TokenTypeHint: String, Sendable {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }

    /// Signs out: revokes the refresh token, then the access token (the
    /// refresh token first, so it takes its whole family with it) and clears
    /// the stored tokens. Revocation failures don't stop the sign-out.
    ///
    /// With `endSarvSession` (the default) the next sign-in also has to ask
    /// for the password: when `postLogoutRedirectURI` is set (https), Sarv's
    /// sign-out page is opened; either way the next shared-session sign-in
    /// sends `prompt=login`.
    @MainActor
    public func signOut(endSarvSession: Bool = true, anchor: ASPresentationAnchor? = nil) async {
        let current = tokens
        try? store.clear()
        for (token, hint) in [(current?.refreshToken, TokenTypeHint.refreshToken),
                              (current?.accessToken, TokenTypeHint.accessToken)] {
            guard let token else { continue }
            _ = try? await revoke(token, hint: hint)
        }
        guard endSarvSession else { return }
        promptLoginOnNextSignIn = true
        if let logoutURL = logoutURL(), let returnURL = configuration.postLogoutRedirectURI {
            _ = try? await WebAuthenticator(anchor: anchor).start(url: logoutURL, callback: returnURL, ephemeral: false)
        }
    }

    /// Sarv's end-session URL, or nil without an https `postLogoutRedirectURI`
    /// (Sarv won't redirect a custom scheme after sign-out).
    public func logoutURL(state: String? = nil) -> URL? {
        guard let returnURL = configuration.postLogoutRedirectURI else { return nil }
        var components = URLComponents(url: configuration.endpoint("api/oauth/logout"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "post_logout_redirect_uri", value: returnURL.absoluteString),
        ]
        if let state { items.append(URLQueryItem(name: "state", value: state)) }
        components.queryItems = items
        return components.url!
    }

    // MARK: - Helpers

    static func decodeTokens(_ data: Data, previousRefreshToken: String? = nil) throws -> SarvTokens {
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
                .tokens(previousRefreshToken: previousRefreshToken)
        } catch {
            throw SarvAuthError.invalidResponse("token response could not be read")
        }
    }
}

/// One refresh in flight at a time; later callers await the same result.
actor RefreshCoordinator {
    private var task: Task<SarvTokens, Error>?

    func run(_ operation: @escaping @Sendable () async throws -> SarvTokens) async throws -> SarvTokens {
        if let task { return try await task.value }
        let task = Task { try await operation() }
        self.task = task
        defer { self.task = nil }
        return try await task.value
    }
}
