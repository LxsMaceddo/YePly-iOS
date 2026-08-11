import Foundation
import Supabase

private struct ProfileUpdatePayload: Encodable, Sendable {
    let displayName: String
    let bio: String?
    let tastes: [String]
    let avatarPath: String?
    let backgroundPath: String?
    let residenceCountryCode: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case bio
        case tastes
        case avatarPath = "avatar_path"
        case backgroundPath = "background_path"
        case residenceCountryCode = "residence_country_code"
    }
}

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable { case loading, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    @Published private(set) var profile: UserProfile?
    @Published var errorMessage: String?
    @Published var isDemo = false

    private let client: SupabaseClient?
    private var authListener: Task<Void, Never>?
    private let cachedProfileKey = "yeply.cached.profile"
    let demoUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    init(client: SupabaseClient?) {
        self.client = client
        if let data = UserDefaults.standard.data(forKey: "yeply.cached.profile"),
           let cached = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = cached
            state = .signedIn
        }
    }

    var userID: UUID? { profile?.id }
    var isAdmin: Bool { profile?.role == .admin }

    func start() async {
        guard let client else { state = .signedOut; return }
        authListener?.cancel()
        authListener = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                if let session {
                    await self.loadProfile(userID: session.user.id)
                } else if event == .initialSession, let cached = self.cachedProfile() {
                    // Keep downloaded music available when a token cannot be
                    // refreshed yet because the app launched without internet.
                    self.profile = cached
                    self.state = .signedIn
                } else if event == .signedOut {
                    self.clearLocalSession()
                } else if self.profile == nil {
                    self.state = .signedOut
                }
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
        clearLocalSession()
    }

    func enterDemo() {
        isDemo = true
        profile = UserProfile(id: demoUserID, displayName: "Vitor", username: "vitor", avatarPath: nil, bio: "Criando e descobrindo música no YePly.", tastes: ["Rap", "R&B", "Eletrônica"], role: .admin, createdAt: .now)
        state = .signedIn
    }

    func updateProfile(
        displayName: String,
        bio: String,
        tastes: [String],
        residenceCountryCode: String?,
        avatarJPEG: Data?,
        backgroundJPEG: Data?
    ) async -> Bool {
        errorMessage = nil
        guard var current = profile else { errorMessage = YePlyError.noActiveUser.localizedDescription; return false }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTastes = Array(Set(tastes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let cleanCountryCode = residenceCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanName.isEmpty, cleanName.count <= 80 else { errorMessage = "Informe um nome de até 80 caracteres."; return false }
        guard cleanBio.count <= 280 else { errorMessage = "A descrição pode ter no máximo 280 caracteres."; return false }
        guard cleanTastes.count <= 8, cleanTastes.allSatisfy({ $0.count <= 30 }) else { errorMessage = "Escolha até 8 estilos musicais."; return false }
        guard cleanCountryCode == nil || cleanCountryCode?.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else { errorMessage = "Selecione um país válido."; return false }

        if isDemo || client == nil {
            current.displayName = cleanName
            current.bio = cleanBio.isEmpty ? nil : cleanBio
            current.tastes = cleanTastes
            current.residenceCountryCode = cleanCountryCode
            if let avatarJPEG {
                current.avatarPath = "demo/avatar"
                try? saveLocalAvatar(avatarJPEG, userID: current.id)
            }
            if let backgroundJPEG {
                current.backgroundPath = "demo/background"
                try? saveLocalBackground(backgroundJPEG, userID: current.id)
            }
            profile = current
            return true
        }

        guard let client else { return false }
        var newAvatarPath = current.avatarPath
        var newBackgroundPath = current.backgroundPath
        var uploadedPaths: [String] = []
        do {
            if let avatarJPEG {
                guard avatarJPEG.count <= 5 * 1_024 * 1_024 else { throw YePlyError.message("A foto de perfil deve ter no máximo 5 MB.") }
                let path = "\(current.id.uuidString.lowercased())/avatar/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage.from("avatars").upload(
                    path,
                    data: avatarJPEG,
                    options: FileOptions(cacheControl: "86400", contentType: "image/jpeg", upsert: false)
                )
                uploadedPaths.append(path)
                newAvatarPath = path
            }

            if let backgroundJPEG {
                guard backgroundJPEG.count <= 5 * 1_024 * 1_024 else {
                    throw YePlyError.message("A imagem de fundo deve ter no máximo 5 MB.")
                }
                let path = "\(current.id.uuidString.lowercased())/background/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage.from("avatars").upload(
                    path,
                    data: backgroundJPEG,
                    options: FileOptions(cacheControl: "86400", contentType: "image/jpeg", upsert: false)
                )
                uploadedPaths.append(path)
                newBackgroundPath = path
            }

            let payload = ProfileUpdatePayload(
                displayName: cleanName,
                bio: cleanBio.isEmpty ? nil : cleanBio,
                tastes: cleanTastes,
                avatarPath: newAvatarPath,
                backgroundPath: newBackgroundPath,
                residenceCountryCode: cleanCountryCode
            )
            let updated: UserProfile = try await client.from("profiles").update(payload).eq("id", value: current.id).select().single().execute().value
            if let avatarJPEG { try saveLocalAvatar(avatarJPEG, userID: current.id) }
            if let backgroundJPEG { try saveLocalBackground(backgroundJPEG, userID: current.id) }
            if let oldPath = current.avatarPath, oldPath != newAvatarPath { try? await client.storage.from("avatars").remove(paths: [oldPath]) }
            if let oldPath = current.backgroundPath, oldPath != newBackgroundPath { try? await client.storage.from("avatars").remove(paths: [oldPath]) }
            profile = updated
            cache(updated)
            return true
        } catch {
            if !uploadedPaths.isEmpty { try? await client.storage.from("avatars").remove(paths: uploadedPaths) }
            errorMessage = friendly(error)
            return false
        }
    }

    func avatarURL() async -> URL? {
        guard let profile, profile.avatarPath != nil else { return nil }
        let localURL = localAvatarURL(userID: profile.id)
        if FileManager.default.fileExists(atPath: localURL.path) { return localURL }
        guard let client, let path = profile.avatarPath else { return nil }
        do {
            let remoteURL = try await client.storage.from("avatars").createSignedURL(path: path, expiresIn: 600)
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            try saveLocalAvatar(data, userID: profile.id)
            return localURL
        } catch { return nil }
    }

    func backgroundURL() async -> URL? {
        guard let profile, profile.backgroundPath != nil else { return nil }
        let localURL = localBackgroundURL(userID: profile.id)
        if FileManager.default.fileExists(atPath: localURL.path) { return localURL }
        guard let client, let path = profile.backgroundPath else { return nil }
        do {
            let remoteURL = try await client.storage.from("avatars").createSignedURL(path: path, expiresIn: 600)
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            try saveLocalBackground(data, userID: profile.id)
            return localURL
        } catch { return nil }
    }

    private func loadProfile(userID: UUID) async {
        guard let client else { return }
        do {
            profile = try await client.from("profiles").select().eq("id", value: userID).single().execute().value
            if let profile { cache(profile) }
            state = .signedIn
        } catch {
            if let cached = cachedProfile(), cached.id == userID {
                profile = cached
                state = .signedIn
            } else {
                errorMessage = friendly(error)
                state = .signedOut
            }
        }
    }

    private func cache(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: cachedProfileKey)
    }

    private func cachedProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: cachedProfileKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private func clearLocalSession() {
        isDemo = false
        profile = nil
        UserDefaults.standard.removeObject(forKey: cachedProfileKey)
        state = .signedOut
    }

    private func localAvatarURL(userID: UUID) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YePlyProfiles", isDirectory: true)
        return directory.appendingPathComponent("\(userID.uuidString.lowercased()).jpg")
    }

    private func localBackgroundURL(userID: UUID) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YePlyProfiles", isDirectory: true)
        return directory.appendingPathComponent("\(userID.uuidString.lowercased())-background.jpg")
    }

    private func saveLocalAvatar(_ data: Data, userID: UUID) throws {
        let url = localAvatarURL(userID: userID)
        try saveLocalProfileImage(data, at: url)
    }

    private func saveLocalBackground(_ data: Data, userID: UUID) throws {
        let url = localBackgroundURL(userID: userID)
        try saveLocalProfileImage(data, at: url)
    }

    private func saveLocalProfileImage(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") { return YePlyError.invalidCredentials.localizedDescription }
        if text.localizedCaseInsensitiveContains("email not confirmed") { return YePlyError.accountNeedsConfirmation.localizedDescription }
        return text
    }
}
