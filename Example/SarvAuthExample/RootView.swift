import SarvAuth
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionModel

    var body: some View {
        NavigationStack {
            Group {
                if session.isSignedIn {
                    HomeView()
                } else {
                    SignInView()
                }
            }
            .navigationTitle("SarvAuth Example")
        }
        .alert("Login with Sarv", isPresented: Binding(
            get: { session.alert != nil },
            set: { if !$0 { session.alert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.alert ?? "")
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var session: SessionModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Welcome")
                .font(.largeTitle.bold())
            Text("Sign in with your Sarv account to continue.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            if !SarvConfig.isConfigured {
                Label("Set your client id in SarvConfig.swift", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            SarvLoginButtonView(size: .large, fullWidth: true) {
                Task { await session.signIn() }
            }
            SarvLoginButtonView("Use another account", variant: .surface, size: .large, fullWidth: true) {
                Task { await session.signIn(newAccount: true) }
            }
        }
        .disabled(session.isWorking)
        .overlay { if session.isWorking { ProgressView() } }
        .padding(24)
    }
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionModel

    var body: some View {
        List {
            if let user = session.user {
                Section("Profile") {
                    row("Name", user.name)
                    row("Email", user.email)
                    row("Email verified", user.emailVerified.map { $0 ? "Yes" : "No" })
                    row("User id (sub)", user.sub)
                }
            }
            if let tokens = session.tokens {
                Section("Tokens") {
                    row("Access token expires", tokens.expiresAt.formatted(date: .omitted, time: .standard))
                    row("Refresh token", tokens.refreshToken == nil ? "None" : "Stored")
                    row("Scopes", tokens.scope)
                }
            }
            Section {
                Button("Reload profile") { Task { await session.loadProfile() } }
                Button("Get access token") { Task { await session.getAccessToken() } }
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            }
        }
        .disabled(session.isWorking)
        .refreshable { await session.loadProfile() }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        LabeledContent(title, value: value ?? "—")
    }
}
