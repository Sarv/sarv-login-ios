# Login with Sarv for iOS

**SarvAuth** adds **Login with Sarv** to an iOS app: the official button and an
OAuth 2.1 + PKCE / OpenID Connect client for `https://oauth.sarv.com`, following
[RFC 8252 — OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252). Same
protocol and rules as the web SDK [sarv-login-js](https://github.com/Sarv/sarv-login-js).

- Sign-in runs in the **system sign-in sheet** (`ASWebAuthenticationSession`), never a
  `WKWebView` — the password stays out of your app.
- **PKCE S256**, `state`, and ID-token `iss` / `aud` / `exp` / `nonce` checks, enforced.
- Sarv's token and revoke endpoints take **JSON** bodies — handled for you.
- Tokens in the **Keychain** (`…AfterFirstUnlockThisDeviceOnly`).
- **Refresh-token rotation** handled: one refresh in flight, the new refresh token saved.
- iOS 15+, Swift Package Manager or CocoaPods, no third-party dependencies.

> Building for Android? See [sarv-login-android](https://github.com/Sarv/sarv-login-android).
> Integrating without this SDK (e.g. with AppAuth)? See the
> [manual integration guide](docs/manual-integration.md).

## Install

**Swift Package Manager** — in Xcode, **File → Add Package Dependencies…**, enter
`https://github.com/Sarv/sarv-login-ios`, add the **SarvAuth** product. Or:

```swift
.package(url: "https://github.com/Sarv/sarv-login-ios.git", from: "0.1.0")
```

**CocoaPods:**

```ruby
pod 'SarvAuth', :git => 'https://github.com/Sarv/sarv-login-ios.git', :tag => '0.1.0'
```

## 1. Register a public app

In the Sarv developer dashboard, **Apps → New App**:

| Field | Value |
| --- | --- |
| Client type | **public** — an app has no `client_secret`; PKCE protects the flow. |
| Redirect URI | `com.example.app:/oauth2redirect` — a lowercase private-use scheme from a domain you own, reversed (your bundle ID works). Note the **single** slash. Matched exactly. |
| Grant types | `authorization_code`, `refresh_token` |
| Scopes | `openid email profile`, plus any API scopes your app needs |

Nothing to add to `Info.plist`: `ASWebAuthenticationSession` catches the redirect itself.

## 2. Configure

```swift
import SarvAuth

let sarv = SarvAuthClient(configuration: try SarvAuthConfiguration(
    clientId: "YOUR_CLIENT_ID",
    redirectURI: URL(string: "com.example.app:/oauth2redirect")!
))
```

Keep **one** `SarvAuthClient` for the app's lifetime, so refreshes are serialised.

## 3. Sign in

```swift
let result = try await sarv.signIn()
result.user?.sub      // stable user id — store this, not the email
result.user?.email
```

- `prefersEphemeralSession: true` shares nothing with Safari: use it for "add another
  account", and it also removes the system "…wants to use oauth.sarv.com to sign in" alert.
- Errors are `SarvAuthError`: `.cancelled` (sheet closed), `.authorizationFailed`,
  `.stateMismatch`, `.invalidIDToken`, `.rateLimited`, `.server(status:detail:)`, `.network`, …

## 4. Call APIs

```swift
let token = try await sarv.validAccessToken()   // refreshes when < 60 s left
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

Access tokens last 30 minutes; refresh tokens 30 days and **rotate** on every use. Concurrent
callers share one refresh. `.sessionExpired` means Sarv rejected the refresh token (expired,
revoked or replayed) and the stored tokens are already cleared — show sign-in again. Network
errors keep them.

`sarv.fetchUser()` returns the userinfo profile (`sub`, `email`, `email_verified`, `name`,
`phone_number` with the `phone` scope). Sarv exposes no roles or permissions.

**Exchange on a backend instead?** That is still the most secure option — tokens never reach
the device. Follow [step 5 of the manual guide](docs/manual-integration.md#5-exchange-the-code)
and use this SDK only for the button.

## 5. Sign out

```swift
await sarv.signOut()
```

Revokes the refresh token, then the access token, and clears the Keychain. Sarv's sign-out
page only redirects to an `https://` URL, so it can't return to a custom-scheme app; instead
the **next sign-in sends `prompt=login`** and Sarv asks for the password. If your client also
has an https redirect URI, pass `postLogoutRedirectURI:` to the configuration and `signOut`
opens Sarv's sign-out page too.

## The button

```swift
// SwiftUI
SarvLoginButtonView { Task { try await sarv.signIn() } }
SarvLoginButtonView("Continue with Sarv", variant: .surface, size: .large, fullWidth: true) { … }

// UIKit
let button = SarvLoginButton()
button.variant = .brand     // .brand (Sarv blue #3069B0) or .surface (bordered)
button.size = .large        // .small / .medium / .large — 30 / 38 / 44 pt
button.theme = .auto        // follows the app's appearance
button.addAction(UIAction { _ in Task { try await sarv.signIn() } }, for: .primaryActionTriggered)
```

Colours, sizes and the mark match the [web button](https://github.com/Sarv/sarv-login-js#what-it-looks-like).
Use `.large` (44 pt) where it is the main touch target.

> If your app offers any third-party sign-in, App Store Review Guideline 4.8 requires an
> equivalent privacy-focused option such as Sign in with Apple alongside it.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `.server(status: 400, detail: "Invalid redirect_uri")` | The redirect URI differs from the registered one — compare scheme, slashes and path exactly. |
| `.invalidIDToken` | The token was not issued by `oauth.sarv.com` for your `clientId`, has expired, or carries another sign-in's `nonce`. |
| `.sessionExpired` right after a refresh | Two refreshes raced in different `SarvAuthClient` instances — keep one. |
| `.rateLimited` | Limits are per IP (authorize/token 20/min, revoke 10/min). |

## Development

```sh
swift build
swift test      # runs on macOS — the core is platform-independent
xcodebuild -scheme SarvAuth -destination 'generic/platform=iOS' build
```

## License

MIT
