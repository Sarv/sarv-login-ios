import SwiftUI

@main
struct SarvAuthExampleApp: App {
    @StateObject private var session = SessionModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
