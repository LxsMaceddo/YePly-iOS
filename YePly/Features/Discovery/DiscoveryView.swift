import SwiftUI
import UIKit

private enum DiscoverySection: String, CaseIterable, Identifiable {
    case users, artists, playlists
    var id: String { rawValue }
    var title: String { switch self { case .users: "Usuários"; case .artists: "Artistas"; case .playlists: "Playlists" } }
}

@MainActor
private final class DiscoveryViewModel: ObservableObject {
    @Published var profiles: [UserProfile] = []
    @Published var artists: [ArtistSummary] = []
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func search(query: String, repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let profiles = repository.searchProfiles(query: query)
            async let artists = repository.searchArtists(query: query)
            async let playlists = repository.searchPlaylists(query: query)
            self.profiles = try await profiles
            self.artists = try await artists
            self.playlists = try await playlists
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func toggle(_ profile: UserProfile, repository: any MusicRepository) async {
        do {
            let followed = try await repository.toggleUserFollow(userID: profile.id)
            guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            let previous = profiles[index].isFollowed ?? false
            profiles[index].isFollowed = followed
            profiles[index].followerCount = max(0, (profiles[index].followerCount ?? 0) + (followed && !previous ? 1 : !followed && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }

    func toggle(_ artist: ArtistSummary, repository: any MusicRepository) async {
        do {
            let followed = try await repository.toggleArtistFollow(artistName: artist.artistName)
            guard let index = artists.firstIndex(where: { $0.id == artist.id }) else { return }
            let previous = artists[index].isFollowed
            artists[index].isFollowed = followed
            artists[index].followerCount = max(0, artists[index].followerCount + (followed && !previous ? 1 : !followed && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }

    func toggle(_ playlist: Playlist, repository: any MusicRepository) async {
        do {
            let followed = try await repository.togglePlaylistFollow(playlistID: playlist.id)
            guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
            let previous = playlists[index].isFollowed ?? false
            playlists[index].isFollowed = followed
            playlists[index].followerCount = max(0, (playlists[index].followerCount ?? 0) + (followed && !previous ? 1 : !followed && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }
}

struct DiscoveryView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var model = DiscoveryViewModel()
    @State private var query = ""
    @State private var section: DiscoverySection = .users

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DESCOBRIR").font(.caption2.bold()).tracking(2).foregroundStyle(YePlyTheme.tertiary)
                        Text("Encontre sua comunidade").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1)
                    }
                    Spacer()
                    YePlyLogo(size: 38)
                }
                .padding(.top, 18)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(YePlyTheme.tertiary)
                    TextField("Usuário, artista ou playlist", text: $query).textInputAutocapitalization(.never)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(YePlyTheme.tertiary) } }
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                Picker("Categoria", selection: $section) {
                    ForEach(DiscoverySection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if offlineLibrary.isOfflineMode {
                    ContentUnavailableView("Busca indisponível offline", systemImage: "wifi.slash", description: Text("Conecte-se para encontrar usuários, artistas e novas playlists."))
                        .frame(maxWidth: .infinity).padding(.top, 55)
                } else if model.isLoading && currentResultCount == 0 {
                    ProgressView("Buscando…").frame(maxWidth: .infinity).padding(.top, 70)
                } else {
                    results
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .navigationDestination(for: UserProfile.self) { PublicProfileView(profile: $0) }
        .navigationDestination(for: ArtistSummary.self) { ArtistDetailView(artist: $0) }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .task(id: query) {
            guard offlineLibrary.isConnected else { return }
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await model.search(query: query.trimmingCharacters(in: .whitespacesAndNewlines), repository: container.repository)
        }
        .alert("Não foi possível buscar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .yeplyBackground()
    }

    @ViewBuilder
    private var results: some View {
        switch section {
        case .users:
            LazyVStack(spacing: 10) {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 13) {
                        NavigationLink(value: profile) {
                            HStack(spacing: 13) {
                                SocialAvatarView(profile: profile, size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text("@\(profile.username) • \(profile.followerCount ?? 0) seguidores").font(.caption).foregroundStyle(YePlyTheme.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        FollowButton(isFollowing: profile.isFollowed ?? false) { Task { await model.toggle(profile, repository: container.repository) } }
                    }
                    .padding(12).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        case .artists:
            LazyVStack(spacing: 10) {
                ForEach(model.artists) { artist in
                    HStack(spacing: 13) {
                        NavigationLink(value: artist) {
                            HStack(spacing: 13) {
                                ZStack { Circle().fill(YePlyTheme.elevatedStrong); Image(systemName: "music.mic").foregroundStyle(YePlyTheme.accent) }.frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artist.artistName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text("\(artist.followerCount) seguidores • \(artist.trackCount) músicas").font(.caption).foregroundStyle(YePlyTheme.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        FollowButton(isFollowing: artist.isFollowed) { Task { await model.toggle(artist, repository: container.repository) } }
                    }
                    .padding(12).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        case .playlists:
            LazyVStack(spacing: 10) {
                ForEach(model.playlists) { playlist in
                    HStack(spacing: 13) {
                        NavigationLink(value: playlist) {
                            HStack(spacing: 13) {
                                PlaylistArtworkView(playlist: playlist).frame(width: 58, height: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text("\(playlist.artistName) • \(playlist.viewCount ?? 0) visualizações").font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        FollowButton(isFollowing: playlist.isFollowed ?? false) { Task { await model.toggle(playlist, repository: container.repository) } }
                    }
                    .padding(10).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var currentResultCount: Int {
        switch section { case .users: model.profiles.count; case .artists: model.artists.count; case .playlists: model.playlists.count }
    }
}

struct FollowButton: View {
    let isFollowing: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(isFollowing ? "Seguindo" : "Seguir").font(.caption.weight(.bold))
                .foregroundStyle(isFollowing ? .white : .black)
                .padding(.horizontal, 13).frame(height: 34)
                .background(isFollowing ? YePlyTheme.elevatedStrong : .white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SocialAvatarView: View {
    @EnvironmentObject private var container: AppContainer
    let profile: UserProfile
    let size: CGFloat
    @State private var avatarURL: URL?

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [YePlyTheme.accent, YePlyTheme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { initials }
                }
            } else { initials }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: profile.avatarPath) {
            guard let path = profile.avatarPath else { return }
            avatarURL = try? await container.repository.signedAvatarURL(path: path)
        }
    }

    private var initials: some View {
        Text(profile.displayName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased())
            .font(.subheadline.bold()).foregroundStyle(.white)
    }
}

struct PublicProfileView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @State private var current: UserProfile
    @State private var errorMessage: String?

    init(profile: UserProfile) { _current = State(initialValue: profile) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SocialAvatarView(profile: current, size: 112).padding(.top, 24)
                VStack(spacing: 5) {
                    Text(current.displayName).font(.title2.bold())
                    Text("@\(current.username)").foregroundStyle(YePlyTheme.secondary)
                }
                if current.id != session.userID {
                    FollowButton(isFollowing: current.isFollowed ?? false) { Task { await toggleFollow() } }
                }
                HStack(spacing: 10) {
                    socialMetric(current.followerCount ?? 0, "Seguidores")
                    socialMetric(current.followingCount ?? 0, "Seguindo")
                }
                if let bio = current.bio, !bio.isEmpty {
                    Text(bio).font(.subheadline).foregroundStyle(YePlyTheme.secondary).multilineTextAlignment(.center).padding(16)
                        .frame(maxWidth: .infinity).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                }
                if let tastes = current.tastes, !tastes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GOSTOS").font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.tertiary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(tastes, id: \.self) { Text($0).font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(height: 32).background(YePlyTheme.elevatedStrong, in: Capsule()) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { current = try await container.repository.fetchProfile(id: current.id) }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Não foi possível carregar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .yeplyBackground()
    }

    private func socialMetric(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) { Text("\(value)").font(.title3.bold()); Text(label).font(.caption).foregroundStyle(YePlyTheme.secondary) }
            .frame(maxWidth: .infinity).padding(14).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
    }

    private func toggleFollow() async {
        do {
            let previous = current.isFollowed ?? false
            let followed = try await container.repository.toggleUserFollow(userID: current.id)
            current.isFollowed = followed
            current.followerCount = max(0, (current.followerCount ?? 0) + (followed && !previous ? 1 : !followed && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var current: ArtistSummary
    @State private var playlists: [Playlist] = []
    @State private var errorMessage: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(artist: ArtistSummary) { _current = State(initialValue: artist) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack { Circle().fill(YePlyTheme.elevated); Image(systemName: "music.mic").font(.system(size: 42)).foregroundStyle(YePlyTheme.accent) }.frame(width: 112, height: 112).padding(.top, 22)
                Text(current.artistName).font(.title.bold()).multilineTextAlignment(.center)
                FollowButton(isFollowing: current.isFollowed) { Task { await toggleFollow() } }
                HStack(spacing: 10) {
                    metric(current.followerCount, "Seguidores")
                    metric(current.trackCount, "Músicas")
                    metric(current.playlistCount, "Playlists")
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(playlists) { playlist in NavigationLink(value: playlist) { PlaylistCard(playlist: playlist) }.buttonStyle(.plain) }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationTitle(current.artistName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .task {
            do { playlists = try await container.repository.fetchArtistPlaylists(artistKey: current.artistKey) }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Não foi possível carregar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .yeplyBackground()
    }

    private func metric(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) { Text("\(value)").font(.headline.bold()); Text(label).font(.caption2).foregroundStyle(YePlyTheme.secondary) }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private func toggleFollow() async {
        do {
            let previous = current.isFollowed
            let followed = try await container.repository.toggleArtistFollow(artistName: current.artistName)
            current.isFollowed = followed
            current.followerCount = max(0, current.followerCount + (followed && !previous ? 1 : !followed && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }
}
