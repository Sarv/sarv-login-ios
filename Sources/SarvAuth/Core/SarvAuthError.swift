import Foundation

/// Everything the SDK can throw. Server text (`detail`) is human-readable,
/// never a machine code — branch on the case, not on the message.
public enum SarvAuthError: Error, Equatable, LocalizedError {
    /// The configuration is unusable (missing client id, reserved parameter, …).
    case invalidConfiguration(String)
    /// The user closed the sign-in sheet.
    case cancelled
    /// Sarv redirected back with `?error=` (e.g. `access_denied`).
    case authorizationFailed(error: String, description: String?)
    /// The callback carried no authorization code.
    case missingCode
    /// The callback's `state` is not the one this flow sent. The code was not used.
    case stateMismatch
    /// The ID token failed a check (`iss`, `aud`, `exp` or `nonce`). The tokens were discarded.
    case invalidIDToken(String)
    /// Too many requests from this IP (HTTP 429). Not a credential problem.
    case rateLimited(detail: String?)
    /// The refresh token was rejected (expired, revoked or already rotated).
    /// Stored tokens were cleared — sign in again.
    case sessionExpired
    /// No tokens stored — call `signIn` first.
    case notSignedIn
    /// Any other non-2xx answer from the authorization server.
    case server(status: Int, detail: String?)
    /// The request never got an answer (offline, timeout, TLS…).
    case network(String)
    /// The server answered with something the SDK could not read.
    case invalidResponse(String)
    /// Keychain read/write failed.
    case keychain(OSStatus)
    /// The system sign-in sheet could not start (no window, bad callback, …).
    case presentationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return "Sarv login: \(message)"
        case .cancelled: return "Sign in was cancelled."
        case .authorizationFailed(let error, let description): return description ?? "Sign in failed (\(error))."
        case .missingCode: return "Sign in failed: no authorization code was returned."
        case .stateMismatch: return "Sign in failed: the response did not match this sign-in attempt."
        case .invalidIDToken(let reason): return "Sign in failed: \(reason)"
        case .rateLimited(let detail): return detail ?? "Too many attempts. Please wait a minute and try again."
        case .sessionExpired: return "Your Sarv session has ended. Please sign in again."
        case .notSignedIn: return "Not signed in."
        case .server(let status, let detail): return detail ?? "Sarv returned an error (\(status))."
        case .network(let message): return message
        case .invalidResponse(let message): return "Unexpected response from Sarv: \(message)"
        case .keychain(let status): return "Could not access the keychain (\(status))."
        case .presentationFailed(let message): return message
        }
    }
}
