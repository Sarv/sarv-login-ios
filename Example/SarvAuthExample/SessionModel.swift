import Foundation
import SarvAuth

@MainActor
final class SessionModel: ObservableObject {
    /// Read from the Keychain at launch, so a returning user skips sign-in.
    @Published private(set) var user: SarvUser? = Sarv.client.currentUser
    @Published private(set) var tokens: SarvTokens? = Sarv.client.tokens
    @Published private(set) var isWorking = false
    @Published var alert: String?

    var isSignedIn: Bool { user != nil }

    func signIn(newAccount: Bool = false) async {
        await run {
            let result = try await Sarv.client.signIn(prefersEphemeralSession: newAccount)
            self.user = result.user
            self.tokens = result.tokens
        }
    }

    /// GET /api/oauth/userinfo with a valid access token.
    func loadProfile() async {
        await run {
            self.user = try await Sarv.client.fetchUser()
            self.tokens = Sarv.client.tokens
        }
    }

    /// What every API call does: get a token, refreshing it when it's about to expire.
    func getAccessToken() async {
        await run {
            let token = try await Sarv.client.validAccessToken()
            self.tokens = Sarv.client.tokens
            self.alert = "Access token ready (\(token.prefix(12))…)"
        }
    }

    func signOut() async {
        isWorking = true
        await Sarv.client.signOut()
        isWorking = false
        user = nil
        tokens = nil
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch SarvAuthError.cancelled {
            // The user closed the sheet.
        } catch SarvAuthError.sessionExpired, SarvAuthError.notSignedIn {
            user = nil
            tokens = nil
            alert = "Your session has ended. Please sign in again."
        } catch {
            alert = error.localizedDescription
        }
    }
}
