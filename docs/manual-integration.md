# Login with Sarv for iOS

Add **Login with Sarv** to an iOS app. Sign-in uses OAuth 2.1 with
Authorization Code + PKCE and OpenID Connect, following
[RFC 8252 — OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252).

This guide is the manual path, for apps that don't use the SarvAuth SDK in this repository (see the [README](../README.md)). `oauth.sarv.com` is a standards-based
authorization server with a published discovery document, so the OpenID
Foundation's reference client, [AppAuth for iOS](https://github.com/openid/AppAuth-iOS),
does the hard parts: it presents `ASWebAuthenticationSession` and generates
PKCE, `state` and `nonce`. It also checks `state` and receives the redirect.
This guide covers everything around that, end to end.

> Building for Android? See [sarv-login-android](https://github.com/Sarv/sarv-login-android).
> For the web, use [sarv-login-js](https://github.com/Sarv/sarv-login-js).

---

## Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Endpoints](#endpoints)
- [1. Register a public app](#1-register-a-public-app)
- [2. Add AppAuth](#2-add-appauth)
- [3. Choose the redirect URI](#3-choose-the-redirect-uri)
- [4. Start sign-in](#4-start-sign-in)
- [5. Exchange the code](#5-exchange-the-code)
- [6. Store tokens safely](#6-store-tokens-safely)
- [7. Refresh the access token](#7-refresh-the-access-token)
- [8. Call Sarv APIs](#8-call-sarv-apis)
- [9. Sign out](#9-sign-out)
- [The button](#the-button)
- [Troubleshooting](#troubleshooting)
- [Security checklist](#security-checklist)

---

## How it works

```
 App               ASWebAuthenticationSession          oauth.sarv.com           Your backend
  |  1. build request         |                                  |                        |
  |  (PKCE, state, nonce)     |                                  |                        |
  |-------------------------->|  2. /api/oauth/authorize ------->|                        |
  |                           |     user signs in + consents     |                        |
  |<--------------------------|  3. com.example.app:/oauth2redirect?code=...&state=...   |
  |  4. AppAuth checks state  |                                  |                        |
  |------------------------------------------------- 5. code + code_verifier + nonce ---->|
  |                                                              |<-- 6. POST /token -----|
  |                                                              |--- tokens ------------>|
  |<----------------------------------------------------------------- 7. your session ----|
```

`ASWebAuthenticationSession` runs the sign-in page in Safari's process, not
yours. A `WKWebView` would let the app read the user's password and cannot
reuse the user's existing Sarv session. It is also forbidden by RFC 8252.
Google blocks its own sign-in inside web views, too, so a user who signs in to
Sarv with Google would be stuck. App Review may also reject an app that signs
users in through a web view.

## Requirements

- iOS 12 or later (`ASWebAuthenticationSession`).
- Xcode 15 or later, Swift 5.9 or later.
- A Sarv developer account to register the app.

## Endpoints

AppAuth reads all of these from
[`https://oauth.sarv.com/.well-known/openid-configuration`](https://oauth.sarv.com/.well-known/openid-configuration);
they are listed here for reference.

| Purpose        | Endpoint |
| -------------- | -------- |
| Issuer         | `https://oauth.sarv.com` |
| Authorize      | `https://oauth.sarv.com/api/oauth/authorize` |
| Token          | `https://oauth.sarv.com/api/oauth/token` |
| User info      | `https://oauth.sarv.com/api/oauth/userinfo` |
| Revoke         | `https://oauth.sarv.com/api/oauth/revoke` |
| End session    | `https://oauth.sarv.com/api/oauth/logout` |
| JWKS           | `https://oauth.sarv.com/.well-known/jwks.json` |

- PKCE: `S256` only, required on every request.
- ID tokens: signed `RS256`.
- Access tokens last **30 minutes**; refresh tokens last **30 days** and
  **rotate** on every use.

> [!IMPORTANT]
> The token and revoke endpoints accept **JSON bodies only**
> (`Content-Type: application/json`). Standard OAuth clients, AppAuth included,
> send `application/x-www-form-urlencoded`, which is rejected with `422`. Use
> AppAuth for the authorization step only, and make the token and revoke calls
> yourself as shown below.

## 1. Register a public app

In the Sarv developer dashboard, open **Apps → New App** and set:

| Field         | Value |
| ------------- | ----- |
| Client type   | **public**. Anything shipped in an IPA can be extracted, so a mobile app has no `client_secret`. PKCE protects the flow instead. |
| Redirect URI  | `com.example.app:/oauth2redirect`: a private-use scheme built from a domain you own, reversed (your bundle ID works). Note the **single** slash. Matched exactly, character for character. |
| Grant types   | `authorization_code`, `refresh_token` |
| Scopes        | `openid email profile`, plus any API scopes your app needs |

Copy the `client_id`. A public client has no secret to copy.

> If the same app also ships an Android version, register the Android redirect
> URI on the same client, or use a separate client per platform. Both work.

## 2. Add AppAuth

**Swift Package Manager**: in Xcode, choose **File → Add Package Dependencies…**,
enter `https://github.com/openid/AppAuth-iOS`, and add the **AppAuth** product
to your app target. Or in `Package.swift`:

```swift
.package(url: "https://github.com/openid/AppAuth-iOS.git", from: "1.7.5")
```

**CocoaPods**:

```ruby
pod 'AppAuth'
```

## 3. Choose the redirect URI

Nothing to register. `ASWebAuthenticationSession` watches for the scheme of
your redirect URI and hands the callback straight back to AppAuth, so on
iOS 12+ you need no `CFBundleURLTypes` entry and no `openURL` handler.

Keep the scheme lowercase and unique to your app. The reversed-domain form
makes a collision with another app unlikely.

## 4. Start sign-in

```swift
import AppAuth
import UIKit

enum Sarv {
    static let issuer = URL(string: "https://oauth.sarv.com")!
    static let clientID = "YOUR_CLIENT_ID"
    static let redirectURL = URL(string: "com.example.app:/oauth2redirect")!
}

struct AuthorizationResult {
    let code: String
    let codeVerifier: String
    let nonce: String?
    let redirectURI: String
}

final class SarvSignIn {
    // Must stay alive until the callback fires, or the session is cancelled.
    private var currentFlow: OIDExternalUserAgentSession?

    func start(from viewController: UIViewController,
               completion: @escaping (Result<AuthorizationResult, Error>) -> Void) {
        OIDAuthorizationService.discoverConfiguration(forIssuer: Sarv.issuer) { config, error in
            guard let config else {
                return completion(.failure(error ?? URLError(.badServerResponse)))
            }
            // PKCE (S256), state and nonce are generated by this initializer.
            let request = OIDAuthorizationRequest(
                configuration: config,
                clientId: Sarv.clientID,
                scopes: [OIDScopeOpenID, OIDScopeEmail, OIDScopeProfile],
                redirectURL: Sarv.redirectURL,
                responseType: OIDResponseTypeCode,
                additionalParameters: nil
            )
            self.currentFlow = OIDAuthorizationService.present(request, presenting: viewController) { response, error in
                self.currentFlow = nil
                guard let response, let code = response.authorizationCode else {
                    // OIDErrorCode.userCanceledAuthorizationFlow when the user closes the sheet.
                    return completion(.failure(error ?? URLError(.cancelled)))
                }
                // AppAuth has already rejected a mismatched state.
                completion(.success(AuthorizationResult(
                    code: code,
                    codeVerifier: request.codeVerifier!,
                    nonce: request.nonce,
                    redirectURI: request.redirectURL!.absoluteString
                )))
            }
        }
    }
}
```

Useful extras:

| Option | Effect |
| ------ | ------ |
| `additionalParameters: ["prompt": "login"]` | Always ask for the password, even with a live Sarv session. |
| `additionalParameters: ["prompt": "consent"]` | Always show the consent screen. |
| `additionalParameters: ["login_hint": "user@example.com"]` | Pre-fill the email field. |
| `OIDExternalUserAgentIOS(presenting: vc, prefersEphemeralSession: true)` with `OIDAuthorizationService.present(_:externalUserAgent:callback:)` | No shared cookies: no "wants to use oauth.sarv.com to sign in" alert, and nothing to clean up on sign-out, but the user types the password every time. |

## 5. Exchange the code

> [!WARNING]
> Do **not** call `OIDAuthorizationService.perform(_ tokenRequest:)` or use
> `OIDAuthState.authState(byPresenting:)`. Both send a form-encoded token
> request, which this server rejects. Exchange the code with a JSON request
> instead, as shown below.

### Recommended: on your backend

Send `code`, `codeVerifier`, `nonce` and `redirectURI` to your own server and
let it call the token endpoint. Tokens then never live on the device, and
refresh happens in one place. That matters because refresh tokens rotate, and
replaying a used one revokes the whole authorization.

```js
// Node.js, with jose for ID token verification
import { createRemoteJWKSet, jwtVerify } from "jose";

const OAUTH = "https://oauth.sarv.com";
const CLIENT_ID = process.env.SARV_IOS_CLIENT_ID;
const JWKS = createRemoteJWKSet(new URL(`${OAUTH}/.well-known/jwks.json`));

app.post("/auth/sarv/mobile", async (req, res) => {
  const { code, codeVerifier, nonce, redirectUri } = req.body;
  try {
    const response = await fetch(`${OAUTH}/api/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        grant_type: "authorization_code",
        code,
        code_verifier: codeVerifier,
        redirect_uri: redirectUri,     // the exact string the app sent
        client_id: CLIENT_ID,
      }),
    });
    if (!response.ok) return res.status(401).json(await response.json());
    const tokens = await response.json();

    const { payload } = await jwtVerify(tokens.id_token, JWKS, {
      issuer: OAUTH,
      audience: CLIENT_ID,
    });
    if (payload.nonce !== nonce) return res.status(401).json({ error: "nonce mismatch" });

    // Keep tokens server-side, keyed to payload.sub; give the app your own session.
    res.json({ session: await createSession(payload.sub, tokens) });
  } catch (error) {
    res.status(502).json({ error: error.message });
  }
});
```

### Without a backend: in the app

A public client can make the same request itself. No secret is involved.

```swift
import Foundation

struct SarvTokens: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

struct SarvAuthError: Error {
    let status: Int
    let body: String
}

func postJSON(_ path: String, _ body: [String: String]) async throws -> Data {
    var request = URLRequest(url: Sarv.issuer.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        throw SarvAuthError(status: status, body: String(decoding: data, as: UTF8.self))
    }
    return data
}

func exchangeCode(_ result: AuthorizationResult) async throws -> SarvTokens {
    let data = try await postJSON("api/oauth/token", [
        "grant_type": "authorization_code",
        "code": result.code,
        "code_verifier": result.codeVerifier,
        "redirect_uri": result.redirectURI,
        "client_id": Sarv.clientID,
    ])
    return try JSONDecoder().decode(SarvTokens.self, from: data)
}
```

Then check the ID token's claims before trusting it. It arrived straight from
the token endpoint over TLS, so OIDC allows skipping the signature check here,
but `iss`, `aud`, `exp` and `nonce` must still match:

```swift
func idTokenProblem(_ idToken: String, expectedNonce: String?) -> String? {
    let segments = idToken.split(separator: ".")
    guard segments.count == 3 else { return "malformed token" }
    var base64 = segments[1].replacingOccurrences(of: "-", with: "+")
                            .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64),
          let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return "unreadable claims" }

    let audiences = (claims["aud"] as? [String]) ?? [claims["aud"] as? String].compactMap { $0 }
    let expiry = (claims["exp"] as? TimeInterval) ?? 0

    if claims["iss"] as? String != Sarv.issuer.absoluteString { return "wrong issuer" }
    if !audiences.contains(Sarv.clientID) { return "wrong audience" }
    if Date(timeIntervalSince1970: expiry) < Date() { return "expired" }
    if let expectedNonce, claims["nonce"] as? String != expectedNonce { return "nonce mismatch" }
    return nil
}
```

## 6. Store tokens safely

Skip this section if your backend holds the tokens.

- Keep the access token **in memory**. It lasts 30 minutes, so there is no need
  to persist it.
- Persist only the refresh token, in the **Keychain** with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it is never synced to
  iCloud or restored onto another device. Never use `UserDefaults`, a plist, or
  logs.

```swift
import Security

enum RefreshTokenStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.example.app.sarv",
        kSecAttrAccount as String: "refresh_token",
    ]

    static func write(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
```

## 7. Refresh the access token

Refresh tokens **rotate**. Every refresh returns a new refresh token and
invalidates the one you sent. Sending a used refresh token again revokes the
entire authorization and signs the user out. So:

1. Save the new refresh token **before** using the new access token.
2. Never run two refreshes at once. An `actor` with a shared in-flight task
   makes concurrent callers wait for the same refresh.

```swift
struct SignedOutError: Error {}

actor SarvSession {
    private var tokens: SarvTokens?
    private var expiresAt = Date.distantPast
    private var refreshing: Task<SarvTokens, Error>?

    func accessToken() async throws -> String {
        if let tokens, Date() < expiresAt.addingTimeInterval(-60) {
            return tokens.accessToken
        }
        if let refreshing { return try await refreshing.value.accessToken }

        let task = Task { try await Self.refresh() }
        refreshing = task
        defer { refreshing = nil }

        let fresh = try await task.value
        tokens = fresh
        expiresAt = Date().addingTimeInterval(TimeInterval(fresh.expiresIn ?? 1800))
        return fresh.accessToken
    }

    private static func refresh() async throws -> SarvTokens {
        guard let refreshToken = RefreshTokenStore.read() else { throw SignedOutError() }
        do {
            let data = try await postJSON("api/oauth/token", [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": Sarv.clientID,
            ])
            let fresh = try JSONDecoder().decode(SarvTokens.self, from: data)
            if let rotated = fresh.refreshToken { RefreshTokenStore.write(rotated) }   // 1. persist first
            return fresh                                                              // 2. then use
        } catch let error as SarvAuthError where (400...401).contains(error.status) {
            RefreshTokenStore.clear()   // revoked or replayed: sign in again
            throw error
        }
    }
}
```

## 8. Call Sarv APIs

Send the access token as a bearer token:

```swift
var request = URLRequest(url: Sarv.issuer.appendingPathComponent("api/oauth/userinfo"))
request.setValue("Bearer \(try await session.accessToken())", forHTTPHeaderField: "Authorization")
let (data, _) = try await URLSession.shared.data(for: request)
```

`/api/oauth/userinfo` returns the OIDC profile: `sub`, `email`,
`email_verified`, `name`, and `phone_number` with the `phone` scope. Use `sub`
as the user's stable ID; an email address can change.

## 9. Sign out

Two things have to end: the tokens the app holds, and the user's Sarv session
in Safari's shared cookie jar. If you end only the tokens, the next sign-in
skips the password because Safari is still signed in to Sarv.

**1. Revoke the refresh token first, then the access token.** Revoking the
refresh token takes every access token issued under it along with it. In the
other order, a just-refreshed access token could survive.

```swift
func revoke(_ token: String, hint: String) async {
    do {
        _ = try await postJSON("api/oauth/revoke", [
            "token": token,
            "token_type_hint": hint,   // "refresh_token" or "access_token"
            "client_id": Sarv.clientID,
        ])
    } catch {
        print("Revoke failed; continuing sign-out: \(error)")
    }
}

func signOut(accessToken: String?) async {
    if let refreshToken = RefreshTokenStore.read() { await revoke(refreshToken, hint: "refresh_token") }
    if let accessToken { await revoke(accessToken, hint: "access_token") }
    RefreshTokenStore.clear()
}
```

A failed revocation should not block the sign-out. The user asked to leave, and
an unrevoked access token expires within 30 minutes on its own.

**2. The browser session.** The end-session endpoint
(`/api/oauth/logout`) only redirects back to an `https://` URL on the origin of
a registered redirect URI, so it cannot return to a custom-scheme app. Pick
one:

- **Use an ephemeral session** (`prefersEphemeralSession: true`, see
  [step 4](#4-start-sign-in)). Nothing is shared with Safari, so there is
  nothing to end.
- **Force the password on the next sign-in** by sending `prompt=login` after a
  sign-out.

## The button

Use the same button users see on the web, so they recognise it:

| | |
| - | - |
| Label | **Login with Sarv** (or "Continue with Sarv" / "Sign in to continue") |
| Mark | [`sarv-mark.svg`](https://github.com/Sarv/sarv-login-js/blob/main/assets/sarv-mark.svg). Add it to the asset catalog with **Preserve Vector Data** checked |
| Fill | Sarv brand blue `#3069B0`, white label |
| Alternative | White surface with a 1pt border, for screens that already have a primary action |
| Height | 44pt, the minimum touch target |

See the [web button screenshots](https://github.com/Sarv/sarv-login-js#what-it-looks-like)
for reference.

> If your app offers any third-party sign-in, App Store Review Guideline 4.8
> requires an equivalent privacy-focused option such as Sign in with Apple
> alongside it.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `422` with `"Input should be a valid dictionary or object"` | Form-encoded body sent to `/token` or `/revoke` (e.g. `OIDAuthState.authState(byPresenting:)`) | Send JSON, as in [step 5](#5-exchange-the-code). |
| `400 Missing required parameters for authorization_code grant` | `code_verifier` missing at `/token` | Send `request.codeVerifier`. |
| `400 Invalid redirect_uri` | Redirect URI differs from the registered one by even one character | Compare scheme, slashes, and trailing path exactly. |
| Sheet closes immediately, callback never fires | `currentFlow` was released | Hold the `OIDExternalUserAgentSession` in a property until the callback. |
| "…wants to use oauth.sarv.com to sign in" alert | Standard `ASWebAuthenticationSession` behaviour with shared cookies | Expected. `prefersEphemeralSession: true` removes it. |
| `invalid_grant` on refresh, then the user is signed out | A used refresh token was sent again: two refreshes raced, or the new token was not saved | Serialize refreshes and persist before use ([step 7](#7-refresh-the-access-token)). |
| `invalid_grant` on code exchange | Code already used, expired, or exchanged with a different verifier | Exchange each code once, immediately, with its own verifier. |

## Security checklist

- [ ] Client registered as **public**; no secret anywhere in the app bundle.
- [ ] Sign-in uses `ASWebAuthenticationSession`, never a `WKWebView`.
- [ ] Every attempt uses a fresh PKCE verifier, `state` and `nonce` (AppAuth's default).
- [ ] ID token `iss`, `aud`, `exp` and `nonce` are checked before it is trusted.
- [ ] Refresh token in the Keychain with `…ThisDeviceOnly` accessibility. Better still, kept on your backend.
- [ ] Refreshes serialized; the new refresh token is persisted before use.
- [ ] Sign-out revokes the refresh token, then the access token.
- [ ] Only the scopes the app needs are requested.
