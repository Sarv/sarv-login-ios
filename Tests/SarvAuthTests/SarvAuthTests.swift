import XCTest
@testable import SarvAuth

final class PKCETests: XCTestCase {

    func testChallengeMatchesRFC7636Example() {
        // RFC 7636 Appendix B.
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testSizesMatchWebSDK() {
        XCTAssertEqual(PKCE.verifier().count, 43)
        XCTAssertEqual(PKCE.state().count, 22)
        XCTAssertEqual(PKCE.nonce().count, 22)
        XCTAssertNotEqual(PKCE.state(), PKCE.state())
    }

    func testBase64urlHasNoPaddingOrUnsafeCharacters() {
        let encoded = PKCE.base64url(Data([0xfb, 0xff, 0xfe]))
        XCTAssertEqual(encoded, "-__-")
    }
}

final class ConfigurationTests: XCTestCase {

    func testDefaults() throws {
        let config = try SarvAuthConfiguration.test()
        XCTAssertEqual(config.scopes, ["openid", "email", "profile"])
        XCTAssertEqual(config.oauthURL.absoluteString, "https://oauth.sarv.com")
        XCTAssertNil(config.postLogoutRedirectURI)
    }

    func testRejectsUppercaseSchemeAndCustomSchemePostLogout() {
        XCTAssertThrowsError(try SarvAuthConfiguration(clientId: "c", redirectURI: URL(string: "Com.Sarv:/cb")!))
        XCTAssertThrowsError(try SarvAuthConfiguration(clientId: "c", redirectURI: URL(string: "com.sarv:/cb")!,
                                                       postLogoutRedirectURI: URL(string: "com.sarv:/out")!))
    }

    func testRejectsReservedExtraParameter() {
        XCTAssertThrowsError(try SarvAuthConfiguration.test(extra: ["state": "x"]))
    }

    func testRejectsEmptyClientId() {
        XCTAssertThrowsError(try SarvAuthConfiguration(clientId: "", redirectURI: URL(string: "a://b")!))
    }
}

final class AuthorizationRequestTests: XCTestCase {

    func testAuthorizeURL() throws {
        let config = try SarvAuthConfiguration.test(extra: ["prompt": "login"])
        let request = AuthorizationRequest(configuration: config, state: "s1", codeVerifier: "v".padding(toLength: 43, withPad: "v", startingAt: 0), nonce: "n1")
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(request.url.path, "/api/oauth/authorize")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "client-1")
        XCTAssertEqual(value("redirect_uri"), "com.sarv.test:/oauth2redirect")
        XCTAssertEqual(value("scope"), "openid email profile")
        XCTAssertEqual(value("state"), "s1")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), PKCE.challenge(for: request.codeVerifier))
        XCTAssertEqual(value("nonce"), "n1")
        XCTAssertEqual(value("prompt"), "login")
    }

    func testPromptLoginAfterSignOut() throws {
        let request = AuthorizationRequest(configuration: try .test(), promptLogin: true)
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "prompt" }?.value, "login")
    }

    func testNoNonceWithoutOpenID() throws {
        let config = try SarvAuthConfiguration(clientId: "c", redirectURI: URL(string: "a://b")!, scopes: ["email"])
        XCTAssertNil(AuthorizationRequest(configuration: config).nonce)
    }

    func testCallbackChecks() throws {
        let request = AuthorizationRequest(configuration: try .test(), state: "good")
        XCTAssertEqual(try request.code(from: URL(string: "com.sarv.test:/oauth2redirect?code=abc&state=good")!), "abc")
        XCTAssertThrowsError(try request.code(from: URL(string: "com.sarv.test:/oauth2redirect?code=abc&state=bad")!)) {
            XCTAssertEqual($0 as? SarvAuthError, .stateMismatch)
        }
        XCTAssertThrowsError(try request.code(from: URL(string: "com.sarv.test:/oauth2redirect?state=good")!)) {
            XCTAssertEqual($0 as? SarvAuthError, .missingCode)
        }
        XCTAssertThrowsError(try request.code(from: URL(string: "com.sarv.test:/oauth2redirect?error=access_denied&error_description=No")!)) {
            XCTAssertEqual($0 as? SarvAuthError, .authorizationFailed(error: "access_denied", description: "No"))
        }
    }
}

final class ClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testSignInExchangesCodeChecksNonceAndStores() async throws {
        let store = InMemoryTokenStore()
        let client = SarvAuthClient(configuration: try .test(), tokenStore: store, urlSession: .mock)
        let request = AuthorizationRequest(configuration: client.configuration, state: "st", nonce: "nonce-1")
        var body: [String: Any] = [:]
        MockURLProtocol.handler = { urlRequest in
            XCTAssertEqual(urlRequest.url?.path, "/api/oauth/token")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
            body = try JSONSerialization.jsonObject(with: urlRequest.bodyData) as! [String: Any]
            return (200, tokenJSON(nonce: "nonce-1"))
        }

        let result = try await client.completeSignIn(request: request,
                                                     callbackURL: URL(string: "com.sarv.test:/oauth2redirect?code=c1&state=st")!)
        XCTAssertEqual(body["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(body["code"] as? String, "c1")
        XCTAssertEqual(body["code_verifier"] as? String, request.codeVerifier)
        XCTAssertEqual(body["client_id"] as? String, "client-1")
        XCTAssertEqual(result.user?.sub, "user-1")
        XCTAssertEqual(result.user?.email, "a@sarv.com")
        XCTAssertEqual(try store.load()?.refreshToken, "r1")
    }

    func testSignInRejectsWrongNonce() async throws {
        let store = InMemoryTokenStore()
        let client = SarvAuthClient(configuration: try .test(), tokenStore: store, urlSession: .mock)
        let request = AuthorizationRequest(configuration: client.configuration, state: "st", nonce: "mine")
        MockURLProtocol.handler = { _ in (200, tokenJSON(nonce: "someone-else")) }
        do {
            _ = try await client.completeSignIn(request: request, callbackURL: URL(string: "com.sarv.test:/oauth2redirect?code=c&state=st")!)
            XCTFail("expected nonce mismatch")
        } catch let error as SarvAuthError {
            guard case .invalidIDToken = error else { return XCTFail("got \(error)") }
        }
        XCTAssertNil(try store.load())
    }

    func testSignInRejectsIDTokenForAnotherAppOrIssuerOrExpired() async throws {
        let client = SarvAuthClient(configuration: try .test(), tokenStore: InMemoryTokenStore(), urlSession: .mock)
        let request = AuthorizationRequest(configuration: client.configuration, state: "st", nonce: "n")
        let callback = URL(string: "com.sarv.test:/oauth2redirect?code=c&state=st")!
        for claims in [["aud": "other-app"], ["iss": "https://evil.example"], ["exp": 1000]] as [[String: Any]] {
            MockURLProtocol.handler = { _ in (200, tokenJSON(nonce: "n", overrides: claims)) }
            do { _ = try await client.completeSignIn(request: request, callbackURL: callback); XCTFail("accepted \(claims)") }
            catch { guard case .invalidIDToken = error as? SarvAuthError else { return XCTFail("got \(error)") } }
        }
    }

    @MainActor
    func testSignOutRevokesClearsAndForcesPasswordNextTime() async throws {
        let defaults = UserDefaults(suiteName: "SarvAuthTests.\(UUID().uuidString)")!
        let store = InMemoryTokenStore(tokens: SarvTokens(accessToken: "a", refreshToken: "r", idToken: nil, scope: nil, expiresAt: .distantFuture))
        let client = SarvAuthClient(configuration: try .test(), tokenStore: store, urlSession: .mock, userDefaults: defaults)
        var hints: [String] = []
        MockURLProtocol.handler = { urlRequest in
            hints.append((try JSONSerialization.jsonObject(with: urlRequest.bodyData) as! [String: Any])["token_type_hint"] as! String)
            return (200, Data(#"{"revoked":true}"#.utf8))
        }
        await client.signOut()
        XCTAssertEqual(hints, ["refresh_token", "access_token"])
        XCTAssertNil(try store.load())
        XCTAssertTrue(client.promptLoginOnNextSignIn)
        XCTAssertNil(client.logoutURL())
    }

    func testServerDetailAndRateLimit() async throws {
        let client = SarvAuthClient(configuration: try .test(), tokenStore: InMemoryTokenStore(), urlSession: .mock)
        let request = AuthorizationRequest(configuration: client.configuration, state: "st")
        let callback = URL(string: "com.sarv.test:/oauth2redirect?code=c&state=st")!

        MockURLProtocol.handler = { _ in (400, Data(#"{"detail":"Bad code"}"#.utf8)) }
        do { _ = try await client.completeSignIn(request: request, callbackURL: callback); XCTFail() }
        catch { XCTAssertEqual(error as? SarvAuthError, .server(status: 400, detail: "Bad code")) }

        MockURLProtocol.handler = { _ in (429, Data(#"{"detail":"Slow down"}"#.utf8)) }
        do { _ = try await client.completeSignIn(request: request, callbackURL: callback); XCTFail() }
        catch { XCTAssertEqual(error as? SarvAuthError, .rateLimited(detail: "Slow down")) }
    }

    func testConcurrentCallersShareOneRefreshAndRotationIsStored() async throws {
        let expired = SarvTokens(accessToken: "old", refreshToken: "r-old", idToken: nil, scope: nil, expiresAt: Date(timeIntervalSinceNow: -10))
        let store = InMemoryTokenStore(tokens: expired)
        let client = SarvAuthClient(configuration: try .test(), tokenStore: store, urlSession: .mock)
        let counter = Counter()
        MockURLProtocol.handler = { urlRequest in
            counter.increment()
            let body = try JSONSerialization.jsonObject(with: urlRequest.bodyData) as! [String: Any]
            XCTAssertEqual(body["grant_type"] as? String, "refresh_token")
            XCTAssertEqual(body["refresh_token"] as? String, "r-old")
            Thread.sleep(forTimeInterval: 0.2)
            return (200, Data(#"{"access_token":"new","token_type":"Bearer","expires_in":3600,"refresh_token":"r-new"}"#.utf8))
        }

        async let a = client.validAccessToken()
        async let b = client.validAccessToken()
        async let c = client.validAccessToken()
        let tokens = try await [a, b, c]
        XCTAssertEqual(tokens, ["new", "new", "new"])
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(try store.load()?.refreshToken, "r-new")
    }

    func testRejectedRefreshClearsSession() async throws {
        let expired = SarvTokens(accessToken: "old", refreshToken: "r", idToken: nil, scope: nil, expiresAt: .distantPast)
        let store = InMemoryTokenStore(tokens: expired)
        let client = SarvAuthClient(configuration: try .test(), tokenStore: store, urlSession: .mock)
        MockURLProtocol.handler = { _ in (400, Data(#"{"detail":"Invalid refresh token"}"#.utf8)) }
        do { _ = try await client.validAccessToken(); XCTFail() }
        catch { XCTAssertEqual(error as? SarvAuthError, .sessionExpired) }
        XCTAssertNil(try store.load())
    }

    func testRefreshNetworkErrorKeepsTokens() async throws {
        let expired = SarvTokens(accessToken: "old", refreshToken: "r", idToken: nil, scope: nil, expiresAt: .distantPast)
        let store = InMemoryTokenStore(tokens: expired)
        let client = SarvAuthClient(configuration: try .test(), tokenStore: store, urlSession: .mock)
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client.validAccessToken(); XCTFail() }
        catch { guard case .network = error as? SarvAuthError else { return XCTFail("got \(error)") } }
        XCTAssertNotNil(try store.load())
    }

    func testRevokeAndLogoutURL() async throws {
        let client = SarvAuthClient(configuration: try .test(), tokenStore: InMemoryTokenStore(), urlSession: .mock)
        MockURLProtocol.handler = { urlRequest in
            let body = try JSONSerialization.jsonObject(with: urlRequest.bodyData) as! [String: Any]
            XCTAssertEqual(urlRequest.url?.path, "/api/oauth/revoke")
            XCTAssertEqual(body["token_type_hint"] as? String, "refresh_token")
            return (200, Data(#"{"revoked":true}"#.utf8))
        }
        let revoked = try await client.revoke("r", hint: .refreshToken)
        XCTAssertTrue(revoked)

        let https = SarvAuthClient(configuration: try SarvAuthConfiguration(
            clientId: "client-1", redirectURI: URL(string: "com.sarv.test:/oauth2redirect")!,
            postLogoutRedirectURI: URL(string: "https://app.example.com/signed-out")!), tokenStore: InMemoryTokenStore())
        let items = URLComponents(url: https.logoutURL(state: "s")!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "client_id" }?.value, "client-1")
        XCTAssertEqual(items.first { $0.name == "post_logout_redirect_uri" }?.value, "https://app.example.com/signed-out")
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "s")
    }
}

// MARK: - Helpers

extension SarvAuthConfiguration {
    static func test(extra: [String: String] = [:]) throws -> SarvAuthConfiguration {
        try SarvAuthConfiguration(clientId: "client-1",
                                  redirectURI: URL(string: "com.sarv.test:/oauth2redirect")!,
                                  extraParameters: extra)
    }
}

private func jwt(_ claims: [String: Any]) -> String {
    let header = PKCE.base64url(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
    let payload = PKCE.base64url(try! JSONSerialization.data(withJSONObject: claims))
    return "\(header).\(payload).sig"
}

private func tokenJSON(nonce: String, overrides: [String: Any] = [:]) -> Data {
    var claims: [String: Any] = ["iss": "https://oauth.sarv.com", "aud": "client-1",
                                 "exp": Date().timeIntervalSince1970 + 3600,
                                 "sub": "user-1", "email": "a@sarv.com", "nonce": nonce]
    claims.merge(overrides) { $1 }
    let idToken = jwt(claims)
    return Data(#"{"access_token":"a1","token_type":"Bearer","expires_in":3600,"refresh_token":"r1","id_token":"\#(idToken)","scope":"openid email profile"}"#.utf8)
}

private final class Counter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

extension URLSession {
    static let mock: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }()
}

extension URLRequest {
    /// URLSession moves httpBody into a stream before URLProtocol sees it.
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
