import Foundation
import SarvAuth

/// Replace these with your app's values from the Sarv developer dashboard.
/// The redirect URI must be registered there exactly as written here.
enum SarvConfig {
    static let clientId = "YOUR_CLIENT_ID"
    static let redirectURI = "com.sarv.authexample:/oauth2redirect"

    static var isConfigured: Bool { clientId != "YOUR_CLIENT_ID" }
}

/// One client for the app's lifetime — refreshes are serialised per instance.
enum Sarv {
    static let client = SarvAuthClient(configuration: try! SarvAuthConfiguration(
        clientId: SarvConfig.clientId,
        redirectURI: URL(string: SarvConfig.redirectURI)!
    ))
}
