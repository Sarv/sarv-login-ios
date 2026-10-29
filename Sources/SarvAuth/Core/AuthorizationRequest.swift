import Foundation

/// One sign-in attempt: the values minted for the authorize URL that the
/// callback and the token exchange must match.
struct AuthorizationRequest {
    let state: String
    let codeVerifier: String
    let nonce: String?
    let url: URL

    init(configuration: SarvAuthConfiguration,
         state: String = PKCE.state(),
         codeVerifier: String = PKCE.verifier(),
         nonce: String? = nil,
         promptLogin: Bool = false) {
        let nonce = nonce ?? (configuration.requestsOpenID ? PKCE.nonce() : nil)
        self.state = state
        self.codeVerifier = codeVerifier
        self.nonce = nonce

        var components = URLComponents(url: configuration.endpoint("api/oauth/authorize"),
                                       resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if let nonce { items.append(URLQueryItem(name: "nonce", value: nonce)) }
        var extra = configuration.extraParameters
        if promptLogin, extra["prompt"] == nil { extra["prompt"] = "login" }
        items += extra.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        // URLComponents leaves "+" unescaped; a server reading form-style
        // queries would turn it into a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        self.url = components.url!
    }

    /// The authorization code from Sarv's redirect, after the `state` check.
    func code(from callbackURL: URL) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw SarvAuthError.authorizationFailed(error: error, description: value("error_description"))
        }
        guard let code = value("code"), !code.isEmpty else { throw SarvAuthError.missingCode }
        guard value("state") == state else { throw SarvAuthError.stateMismatch }
        return code
    }
}
