import Foundation
import Supabase

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable { case loading, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    @Published private(set) var profile: UserProfile?
    @Published var errorMessage: String?
    @Published var isDemo = false

    private let client: SupabaseClient?
    private var authListener: Task<Void, Never>?
    let demoUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    init(client: SupabaseClient?) { self.client = client }

    var userID: UUID? { profile?.id }
    var isAdmin: Bool { profile?.role == .admin }

    func start() async {
        guard let client else { state = .signedOut; return }
        authListener?.cancel()
        authListener = Task { [weak self] in
            for await (_, session) in client.auth.authStateChanges {
                guard let self else { return }
                if let session { await self.loadProfile(userID: session.user.id) }
                else { self.profile = nil; self.state = .signedOut }
            }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        guard let client else { errorMessage = YePlyError.configurationMissing.localizedDescription; return }
        do {
            let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            await loadProfile(userID: session.user.id)
        } catch { errorMessage = friendly(error) }
    }

    func signUp(name: String, username: String, email: String, password: String) async -> Bool {
        errorMessage = nil
        guard let client else { errorMessage = YePlyError.configurationMissing.localizedDescription; return false }
        do {
            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                data: ["display_name": .string(name), "username": .string(username.lowercased())],
                redirectTo: URL(string: "yeply://auth/callback")
            )
            if let session = response.session { await loadProfile(userID: session.user.id) }
            return true
        } catch { errorMessage = friendly(error); return false }
    }

    func signOut() async {
        if let client { try? await client.auth.signOut() }
        isDemo = false
        profile = nil
        state = .signedOut
    }

    func enterDemo() {
        isDemo = true
        profile = UserProfile(id: demoUserID, displayName: "Vitor", username: "vitor", avatarPath: nil, role: .admin, createdAt: .now)
        state = .signedIn
    }

    private func loadProfile(userID: UUID) async {
        guard let client else { return }
        do {
            profile = try await client.from("profiles").select().eq("id", value: userID).single().execute().value
            state = .signedIn
        } catch {
            errorMessage = friendly(error)
            state = .signedOut
        }
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") { return YePlyError.invalidCredentials.localizedDescription }
        if text.localizedCaseInsensitiveContains("email not confirmed") { return YePlyError.accountNeedsConfirmation.localizedDescription }
        return text
    }
}
