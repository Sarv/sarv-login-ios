# Login with Sarv for iOS

**SarvAuth** adds **Login with Sarv** to an iOS app: the official button and an
OAuth 2.1 + PKCE / OpenID Connect client for `https://oauth.sarv.com`, following
[RFC 8252 — OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252). Same
protocol and rules as the web SDK [sarv-login-js](https://github.com/Sarv/sarv-login-js).

- Sign-in runs in the **system sign-in sheet** (`ASWebAuthenticationSession`), never a
  `WKWebView` — the password stays out of your app, and Google sign-in to Sarv keeps working.
- **PKCE S256**, `state`, and ID-token `iss` / `aud` / `exp` / `nonce` checks, enforced.
- Sarv's token and revoke endpoints take **JSON** bodies — handled for you.
- Tokens in the **Keychain** (`…AfterFirstUnlockThisDeviceOnly`).
- **Refresh-token rotation** handled: one refresh in flight, the new refresh token saved.
- No third-party dependencies.

> Building for Android? See [sarv-login-android](https://github.com/Sarv/sarv-login-android).
> Integrating without this SDK (e.g. with AppAuth)? See the
> [manual integration guide](docs/manual-integration.md).

---

## Contents

- [Requirements](#requirements)
- [How it works](#how-it-works)
- [1. Register a public app](#1-register-a-public-app)
- [2. Install](#2-install)
- [3. Configure the client](#3-configure-the-client)
- [4. Sign in](#4-sign-in)
- [5. Restore the session at launch](#5-restore-the-session-at-launch)
- [6. Call APIs](#6-call-apis)
- [7. Sign out](#7-sign-out)
- [8. Add another account](#8-add-another-account)
- [The button](#the-button)
- [Complete example (SwiftUI)](#complete-example-swiftui)
- [Complete example (UIKit)](#complete-example-uikit)
- [Errors](#errors)
- [Using a backend for the code exchange](#using-a-backend-for-the-code-exchange)
- [Troubleshooting](#troubleshooting)
- [Security checklist](#security-checklist)
- [API reference](#api-reference)
- [Development](#development)

---

## Requirements

- iOS 15 or later.
- Xcode 15 or later, Swift 5.9 or later.
- A Sarv developer account to register the app.
- A custom-scheme redirect URI (recommended) works on iOS 15+; an `https` universal-link
  redirect URI needs iOS 17.4+.

## How it works

```
 App                    ASWebAuthenticationSession               oauth.sarv.com
  |  signIn()                    |                                      |
  |  PKCE verifier, state, nonce |                                      |
  |----------------------------->|  /api/oauth/authorize -------------->|
  |                              |  user signs in + consents            |
  |<-----------------------------|  com.example.app:/oauth2redirect?code=…&state=…
  |  check state                                                        |
  |  POST /api/oauth/token  (JSON: code + code_verifier) -------------->|
  |<---------------------------------------- access, refresh, id token -|
  |  check id_token iss / aud / exp / nonce, save to Keychain           |
```

## 1. Register a public app

In the Sarv developer dashboard, open **Apps → New App** and set:

| Field | Value |
| --- | --- |
| Client type | **public**. Anything shipped in an IPA can be extracted, so an app has no `client_secret`; PKCE protects the flow instead. |
| Redirect URI | `com.example.app:/oauth2redirect` — a **lowercase** private-use scheme built from a domain you own, reversed (your bundle ID works). Note the **single** slash. Matched exactly, character for character. |
| Grant types | `authorization_code`, `refresh_token` |
| Scopes | `openid email profile`, plus any API scopes your app needs |

Copy the `client_id`. A public client has no secret.

Nothing to add to `Info.plist`: `ASWebAuthenticationSession` watches for your redirect
scheme itself, so you need no `CFBundleURLTypes` entry and no `openURL` handler.

> Shipping an Android app too? Register its redirect URI on the same client, or use a
> separate client per platform. Both work.

## 2. Install

**Swift Package Manager** — in Xcode choose **File → Add Package Dependencies…**, enter
`https://github.com/Sarv/sarv-login-ios`, and add the **SarvAuth** product to your app
target. Or in `Package.swift`:

```swift
.package(url: "https://github.com/Sarv/sarv-login-ios.git", from: "0.1.0")
```

**CocoaPods:**

```ruby
pod 'SarvAuth', :git => 'https://github.com/Sarv/sarv-login-ios.git', :tag => '0.1.0'
```

## 3. Configure the client

Create **one** `SarvAuthClient` and keep it for the app's lifetime — refreshes are
serialised per instance, and two instances refreshing at once would replay a rotated
refresh token.

```swift
import SarvAuth

enum Sarv {
    static let client = SarvAuthClient(configuration: try! SarvAuthConfiguration(
        clientId: "YOUR_CLIENT_ID",
        redirectURI: URL(string: "com.example.app:/oauth2redirect")!
    ))
}
```

`SarvAuthConfiguration` options:

| Parameter | Default | Notes |
| --- | --- | --- |
| `clientId` | — | Required. |
| `redirectURI` | — | Required. Exactly as registered; lowercase scheme. |
| `scopes` | `["openid", "email", "profile"]` | Ask only for what you use — the consent screen lists every scope. |
| `oauthURL` | `https://oauth.sarv.com` | |
| `extraParameters` | `[:]` | Extra authorize parameters (`login_hint`, `prompt`, …). SDK-owned parameters (`state`, `code_challenge`, …) are rejected. |
| `postLogoutRedirectURI` | `nil` | Only an `https://` URL on a registered redirect origin. See [Sign out](#7-sign-out). |

The initializer throws `SarvAuthError.invalidConfiguration` for an empty client id, an
uppercase scheme, a reserved extra parameter or a non-https `postLogoutRedirectURI`.

`SarvAuthClient(configuration:tokenStore:urlSession:userDefaults:)` also accepts your own
`SarvTokenStore` — e.g. `KeychainTokenStore(clientId:accessGroup:)` to share tokens with
an app extension.

## 4. Sign in

```swift
do {
    let result = try await Sarv.client.signIn()
    print(result.user?.sub ?? "")     // stable user id — store this, not the email
    print(result.user?.email ?? "")
} catch SarvAuthError.cancelled {
    // The user closed the sheet — do nothing.
} catch {
    showError(error.localizedDescription)
}
```

`signIn` runs on the main actor, presents over the key window (pass `anchor:` to choose
another window) and stores the tokens before returning. iOS first shows its standard
"…wants to use oauth.sarv.com to sign in" alert; that's expected.

## 5. Restore the session at launch

Tokens survive app restarts in the Keychain. On launch, pick the first screen without a
network call:

```swift
if Sarv.client.isSignedIn {
    showHome(user: Sarv.client.currentUser)   // from the stored ID token
} else {
    showSignIn()
}
```

The stored access token may have expired while the app was closed — `validAccessToken()`
(next step) refreshes it. If the refresh token itself is no longer valid, the first API
call throws `.sessionExpired`: send the user back to sign-in.

## 6. Call APIs

```swift
func authorizedRequest(_ url: URL) async throws -> URLRequest {
    var request = URLRequest(url: url)
    let token = try await Sarv.client.validAccessToken()   // refreshes when < 60 s left
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
}
```

- Access tokens last **30 minutes**; refresh tokens last **30 days** and **rotate** on
  every use. The SDK saves the new refresh token before handing out the new access token,
  and concurrent callers share one refresh.
- `.sessionExpired` — Sarv rejected the refresh token (expired, revoked or replayed). The
  stored tokens are already cleared; show sign-in.
- `.network` — offline or timed out. Tokens are kept; retry later.

User profile:

```swift
let user = try await Sarv.client.fetchUser()   // GET /api/oauth/userinfo
// sub, email, emailVerified, name, profile, phoneNumber (with the `phone` scope)
```

Sarv says *who* someone is; it exposes no roles or permissions. What they may do in your
app is your app's decision.

## 7. Sign out

```swift
await Sarv.client.signOut()
showSignIn()
```

1. Revokes the **refresh token first**, then the access token — revoking the refresh token
   takes every access token issued under it along with it.
2. Clears the Keychain. A failed revocation never blocks sign-out; an unrevoked access
   token expires within 30 minutes on its own.
3. Makes the next sign-in ask for the password. Sarv's sign-out page only redirects to an
   `https://` URL, so it can't return to a custom-scheme app; instead the **next sign-in
   sends `prompt=login`**. If your client also has an `https` redirect URI, set
   `postLogoutRedirectURI:` in the configuration and `signOut` opens Sarv's sign-out page
   as well.

`signOut(endSarvSession: false)` only revokes and clears; the next sign-in may then reuse
the browser session without a password.

## 8. Add another account

Sarv's browser session would sign the same person straight back in. Use an ephemeral
session, which shares nothing with Safari:

```swift
let result = try await Sarv.client.signIn(prefersEphemeralSession: true)
```

This also skips the system sign-in alert. One `SarvAuthClient` holds one account's tokens.
To keep several accounts signed in at once, create one client per account with its own
store — `KeychainTokenStore(clientId:service:)` with a different `service` per account —
and keep each client for the app's lifetime.

## The button

Use the same button users see on the web, so they recognise it.

```swift
// SwiftUI
SarvLoginButtonView { Task { await signIn() } }
SarvLoginButtonView("Continue with Sarv", variant: .surface, size: .large, theme: .auto, fullWidth: true) {
    Task { await signIn() }
}
```

```swift
// UIKit
let button = SarvLoginButton()
button.title = "Login with Sarv"
button.variant = .brand            // .brand (Sarv blue #3069B0) or .surface (white / dark, bordered)
button.size = .large               // .small / .medium / .large = 30 / 38 / 44 pt
button.theme = .auto               // .auto follows the app's appearance; or .light / .dark
button.addAction(UIAction { _ in Task { await signIn() } }, for: .primaryActionTriggered)
```

Colours, sizes and the Sarv mark come from Sarv's design tokens and match the
[web button](https://github.com/Sarv/sarv-login-js#what-it-looks-like). Use `.large` (44 pt,
the minimum touch target) when it's the main action, and `.surface` on screens that already
have a primary action. Disable it while a sign-in is running (`.disabled(true)` /
`isEnabled = false`).

> If your app offers any third-party sign-in, App Store Review Guideline 4.8 requires an
> equivalent privacy-focused option such as Sign in with Apple alongside it.

## Complete example (SwiftUI)

```swift
import SarvAuth
import SwiftUI

@MainActor
final class SessionModel: ObservableObject {
    @Published private(set) var user: SarvUser? = Sarv.client.currentUser
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    func signIn(newAccount: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        do {
            user = try await Sarv.client.signIn(prefersEphemeralSession: newAccount).user
        } catch SarvAuthError.cancelled {
            // closed by the user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProfile() async {
        do {
            user = try await Sarv.client.fetchUser()
        } catch SarvAuthError.sessionExpired, SarvAuthError.notSignedIn {
            user = nil                       // back to sign-in
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        await Sarv.client.signOut()
        user = nil
    }
}

struct RootView: View {
    @StateObject private var session = SessionModel()

    var body: some View {
        Group {
            if let user = session.user {
                VStack(spacing: 16) {
                    Text("Signed in as \(user.name ?? user.email ?? user.sub)")
                    Button("Sign out") { Task { await session.signOut() } }
                }
                .task { await session.loadProfile() }
            } else {
                SarvLoginButtonView(size: .large, fullWidth: true) {
                    Task { await session.signIn() }
                }
                .disabled(session.isWorking)
                .padding()
            }
        }
        .alert("Sign in failed", isPresented: .constant(session.errorMessage != nil)) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}
```

## Complete example (UIKit)

```swift
import SarvAuth
import UIKit

final class SignInViewController: UIViewController {
    private let button = SarvLoginButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        button.size = .large
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        button.addAction(UIAction { [weak self] _ in self?.signIn() }, for: .primaryActionTriggered)
    }

    private func signIn() {
        button.isEnabled = false
        Task {
            defer { button.isEnabled = true }
            do {
                let result = try await Sarv.client.signIn(anchor: view.window)
                showHome(user: result.user)
            } catch SarvAuthError.cancelled {
                // closed by the user
            } catch {
                let alert = UIAlertController(title: "Sign in failed",
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func showHome(user: SarvUser?) { /* navigate */ }
}
```

## Errors

Every failure is a `SarvAuthError`. Server text (`detail`) is human-readable — branch on
the case, never on the message.

| Case | Meaning | Typical handling |
| --- | --- | --- |
| `.cancelled` | The user closed the sign-in sheet. | Ignore. |
| `.authorizationFailed(error:description:)` | Sarv redirected back with `?error=` (e.g. `access_denied` when consent was declined). | Show `description`. |
| `.missingCode`, `.stateMismatch` | The redirect wasn't a valid answer to this sign-in. The code was not used. | Ask the user to try again. |
| `.invalidIDToken(_)` | The ID token failed `iss` / `aud` / `exp` / `nonce`. Tokens discarded. | Try again; check `clientId` / `oauthURL`. |
| `.rateLimited(detail:)` | HTTP 429 — limits are per IP. | Wait a minute. |
| `.server(status:detail:)` | Any other non-2xx answer. | Show `detail`; see [Troubleshooting](#troubleshooting). |
| `.sessionExpired` | Refresh token rejected; stored tokens cleared. | Show sign-in. |
| `.notSignedIn` | No stored tokens. | Show sign-in. |
| `.network(_)` | No answer (offline, timeout, TLS). Tokens kept. | Retry. |
| `.invalidResponse(_)`, `.keychain(_)`, `.presentationFailed(_)`, `.invalidConfiguration(_)` | Unexpected server data, Keychain failure, the sheet couldn't be shown, bad configuration. | Log; show a generic error. |

## Using a backend for the code exchange

Exchanging the code on **your** server keeps tokens off the device entirely and is still
the most secure option. In that setup use this SDK only for the button, and follow
[step 5 of the manual guide](docs/manual-integration.md#5-exchange-the-code) for the
authorization request and the server-side exchange.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `.server(status: 400, detail: "Invalid redirect_uri")` | The redirect URI differs from the registered one. | Compare scheme, slashes and path character by character (`com.example.app:/oauth2redirect`, one slash). |
| `.invalidConfiguration` at launch | Uppercase scheme, empty client id, reserved `extraParameters` key, or a custom-scheme `postLogoutRedirectURI`. | Read the message; fix the configuration. |
| `.invalidIDToken` | Wrong `clientId` or `oauthURL`, or a device clock far off. | Check the configuration and the device time. |
| `.sessionExpired` soon after sign-in | Two `SarvAuthClient` instances refreshed at once and replayed a rotated refresh token. | Keep a single shared instance. |
| Next sign-in skips the password after sign-out | `signOut(endSarvSession: false)` was used. | Use the default `signOut()`. |
| "…wants to use oauth.sarv.com to sign in" alert | Standard `ASWebAuthenticationSession` behaviour with shared cookies. | Expected; `prefersEphemeralSession: true` removes it. |
| `.rateLimited` | Per-IP limits: authorize and token 20/min, revoke 10/min. | Back off; many users behind one office IP share the limit. |

## Security checklist

- [ ] Client registered as **public**; no secret anywhere in the app.
- [ ] Sign-in through `SarvAuthClient.signIn` (system sheet), never a `WKWebView`.
- [ ] One shared `SarvAuthClient`, so refreshes never race.
- [ ] `sub` stored as the user's id, not the email.
- [ ] The ID token is never sent to an API — it's not a credential. Send the access token.
- [ ] Tokens are never logged or put in `UserDefaults`.
- [ ] Sign-out calls `signOut()`, so tokens are revoked and the next sign-in asks for the password.

## API reference

| `SarvAuthClient` | |
| --- | --- |
| `init(configuration:tokenStore:urlSession:userDefaults:)` | Keychain store by default. |
| `signIn(anchor:prefersEphemeralSession:) async throws -> SarvSignInResult` | `@MainActor`. Returns `tokens` and `user`. |
| `isSignedIn`, `tokens`, `currentUser` | Stored state, no network. |
| `validAccessToken() async throws -> String` | Refreshes when needed. |
| `refresh() async throws -> SarvTokens` | Refreshes if expired; shared among concurrent callers. |
| `fetchUser() async throws -> SarvUser` | `/api/oauth/userinfo`. |
| `revoke(_:hint:) async throws -> Bool` | `false` = nothing to revoke (already expired or rotated). |
| `signOut(endSarvSession:anchor:) async` | `@MainActor`. Revoke, clear, end the session. |
| `logoutURL(state:) -> URL?` | Sarv's end-session URL; nil without an https `postLogoutRedirectURI`. |

| Type | |
| --- | --- |
| `SarvTokens` | `accessToken`, `refreshToken`, `idToken`, `scope`, `expiresAt`, `isExpired(leeway:)`, `user`. |
| `SarvUser` | `sub`, `email`, `emailVerified`, `name`, `profile`, `phoneNumber`, `phoneNumberVerified`. |
| `SarvTokenStore` | Protocol; `KeychainTokenStore`, `InMemoryTokenStore`. |
| `SarvLoginButtonView`, `SarvLoginButton` | SwiftUI and UIKit buttons; `SarvButtonVariant`, `SarvButtonSize`, `SarvButtonTheme`. |

## Development

```sh
swift build
swift test      # runs on macOS — the core is platform-independent
xcodebuild -scheme SarvAuth -destination 'generic/platform=iOS' build
pod lib lint --allow-warnings
```

## License

MIT — see [LICENSE](LICENSE).
