import AuthenticationServices
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Runs a URL in the system sign-in sheet (`ASWebAuthenticationSession`) and
/// returns the redirect back to the app. Never an embedded web view: the user's
/// password stays out of the app, and Sarv's existing session is shared.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var session: ASWebAuthenticationSession?
    private let anchor: ASPresentationAnchor?

    init(anchor: ASPresentationAnchor?) {
        self.anchor = anchor
    }

    func start(url: URL, callback redirectURI: URL, ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                self?.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SarvAuthError.cancelled)
                } else {
                    continuation.resume(throwing: SarvAuthError.presentationFailed(
                        error?.localizedDescription ?? "The sign-in sheet closed without a result."))
                }
            }

            let session: ASWebAuthenticationSession
            do {
                session = try Self.makeSession(url: url, redirectURI: redirectURI, completion: completion)
            } catch {
                continuation.resume(throwing: error)
                return
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = ephemeral
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: SarvAuthError.presentationFailed("The sign-in sheet could not be shown."))
            }
        }
    }

    private static func makeSession(url: URL, redirectURI: URL,
                                    completion: @escaping ASWebAuthenticationSession.CompletionHandler) throws -> ASWebAuthenticationSession {
        let scheme = redirectURI.scheme?.lowercased() ?? ""
        if scheme == "https" {
            if #available(iOS 17.4, macOS 14.4, *), let host = redirectURI.host {
                return ASWebAuthenticationSession(url: url,
                                                  callback: .https(host: host, path: redirectURI.path),
                                                  completionHandler: completion)
            }
            throw SarvAuthError.invalidConfiguration("An https redirectURI needs iOS 17.4 / macOS 14.4 or later; register a custom-scheme redirect URI for older systems.")
        }
        return ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: completion)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let anchor { return anchor }
            #if canImport(UIKit)
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }
}
