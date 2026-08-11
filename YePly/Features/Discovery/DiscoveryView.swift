import SwiftUI
import UIKit

private enum DiscoverySection: String, CaseIterable, Identifiable {
    case top, users, artists, playlists
    var id: String { rawValue }
    var title: String { switch self { case .top: "Top"; case .users: "Usuários"; case .artists: "Artistas"; case .playlists: "Playlists" } }
}

@MainActor
private final class DiscoveryViewModel: ObservableObject {
    @Published var profiles: [UserProfile] = []
    @Published var artists: [ArtistSummary] = []
    @Published var playlists: [Playlist] = []
    @Published var topTracks: [PublicTrackRankingItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func search(query: String, repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let profiles = repository.searchProfiles(query: query)
            async let artists = repository.searchArtists(query: query)
            async let playlists = repository.searchPlaylists(query: query)
            async let topTracks = repository.fetchTopPublicTracks(limit: 25)
            self.profiles = try await profiles
            self.artists = try await artists
            self.playlists = try await playlists
            self.topTracks = try await topTracks
            errorMessage = nil
        } catch let error where error.isYePlyCancellation { return }
        catch { errorMessage = error.localizedDescription }
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
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var model = DiscoveryViewModel()
    @State private var query = ""
    @State private var section: DiscoverySection = .top

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
        case .top:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MAIS REPRODUZIDAS").font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.tertiary)
                        Text("Top músicas públicas").font(.title3.bold())
                    }
                    Spacer()
                    Image(systemName: "chart.bar.fill").foregroundStyle(YePlyTheme.accent)
                }
                if model.topTracks.isEmpty {
                    ContentUnavailableView("Nenhuma reprodução pública", systemImage: "chart.bar", description: Text("O ranking aparecerá quando músicas de playlists públicas forem tocadas."))
                        .frame(maxWidth: .infinity).padding(.top, 28)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(Array(model.topTracks.enumerated()), id: \.element.id) { entry in
                            topTrackRow(entry.element, rank: entry.offset + 1)
                        }
                    }
                }
            }
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
                                    HStack(spacing: 5) {
                                        Text(artist.artistName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        if artist.isVerified { VerifiedArtistBadge() }
                                    }
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
                                PlaylistArtworkView(playlist: playlist)
                                    .frame(width: 58, height: 58)
                                    .clipped()
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
        switch section { case .top: model.topTracks.count; case .users: model.profiles.count; case .artists: model.artists.count; case .playlists: model.playlists.count }
    }

    private func topTrackRow(_ item: PublicTrackRankingItem, rank: Int) -> some View {
        Button { playTopTrack(item) } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(rank <= 3 ? YePlyTheme.accent : YePlyTheme.tertiary)
                    .frame(width: 24)
                PlayerArtworkView(track: item.track, artworkPath: item.playlistCoverPath)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(item.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                    Text("\(item.playCount.formatted()) \(item.playCount == 1 ? "reprodução" : "reproduções")")
                        .font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                }
                Spacer()
                Image(systemName: player.currentTrack?.id == item.trackId && player.isPlaying ? "waveform" : "play.fill")
                    .foregroundStyle(YePlyTheme.accent)
            }
            .padding(10)
            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Número \(rank), \(item.title), \(item.artistName), \(item.playCount) reproduções")
    }

    private func playTopTrack(_ item: PublicTrackRankingItem) {
        let queue = model.topTracks.map(\.track)
        Task {
            await player.play(
                item.track,
                queue: queue,
                repository: container.repository,
                artworkPath: item.playlistCoverPath,
                collectionTitle: "Top músicas públicas"
            )
        }
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

struct VerifiedArtistBadge: View {
    var size: CGFloat = 15
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(red: 0.05, green: 0.55, blue: 1))
            .accessibilityLabel("Artista verificado")
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
                YePlyRemoteImage(url: avatarURL) { phase in
                    if case let .success(image) = phase { image.resizable().scaledToFill() }
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
    @State private var equippedBadges: [EquippedAlbumBadge] = []
    @State private var ownedBadgeCount = 0
    @State private var featuredCard: CollectibleCardItem?
    @State private var backgroundURL: URL?
    @State private var collector: CollectorProfileSummary?
    @State private var presence: ProfileMusicPresence?
    @State private var wishlist: [CardWishlistItem] = []
    @State private var folders: [CardFolder] = []
    @State private var marketOffers: [CardPublicOffer] = []
    @State private var ownCards: [CollectibleCardItem] = []
    @State private var ownCoinBalance = 0
    @State private var showingTrade = false
    @State private var scrollOffset: CGFloat = 0
    @State private var errorMessage: String?

    init(profile: UserProfile) { _current = State(initialValue: profile) }

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                PublicProfileBackdrop(url: backgroundURL)
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .ignoresSafeArea(edges: .top)
                    .opacity(Double(max(0, min(1, 1 + scrollOffset / 340))))
                ScrollView {
                    VStack(spacing: 20) {
                Color.clear.frame(height: backgroundURL == nil ? 8 : 142)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: PublicProfileScrollOffsetKey.self, value: proxy.frame(in: .named("publicProfileScroll")).minY)
                        }
                    }
                SocialAvatarView(profile: current, size: 112)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 3))
                VStack(spacing: 5) {
                    HStack(spacing: 7) {
                        Text(current.displayName).font(.title2.bold())
                        if current.role == .admin { Image(systemName: "checkmark.seal.fill").foregroundStyle(YePlyTheme.accent) }
                    }
                    Text("@\(current.username)").foregroundStyle(YePlyTheme.secondary)
                }
                if current.id != session.userID {
                    HStack(spacing: 10) {
                        FollowButton(isFollowing: current.isFollowed ?? false) { Task { await toggleFollow() } }
                        Button { showingTrade = true } label: {
                            Label("Propor troca", systemImage: "arrow.left.arrow.right")
                                .font(.subheadline.bold()).foregroundStyle(.black)
                                .padding(.horizontal, 15).frame(height: 42).background(YePlyTheme.accent, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                if let presence { PublicProfilePresencePanel(presence: presence) }
                if !equippedBadges.isEmpty {
                    ProfileBadgeShowcase(badges: equippedBadges)
                }
                if let featuredCard {
                    ProfileFeaturedCardPanel(card: featuredCard)
                }
                HStack(spacing: 10) {
                    socialMetric(current.followerCount ?? 0, "Seguidores")
                    socialMetric(current.followingCount ?? 0, "Seguindo")
                    socialMetric(max(ownedBadgeCount, current.ownedBadgeCount ?? 0), "Badges")
                }
                if let collector { PublicCollectorPanel(summary: collector) }
                if !marketOffers.isEmpty {
                    ProfileMarketPanel(offers: marketOffers, isOwner: current.id == session.userID) {
                        await refreshMarket()
                    }
                }
                if !wishlist.isEmpty {
                    PublicWishlistPanel(items: wishlist) { showingTrade = true }
                }
                if !folders.isEmpty { PublicFoldersPanel(folders: folders) }
                if let bio = current.bio, !bio.isEmpty {
                    Text(bio).font(.subheadline).foregroundStyle(YePlyTheme.secondary).multilineTextAlignment(.center).padding(16)
                        .frame(maxWidth: .infinity).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                }
                if let tastes = current.tastes, !tastes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ESTILOS MUSICAIS").font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.tertiary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(tastes, id: \.self) { Text($0).font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(height: 32).background(YePlyTheme.elevatedStrong, in: Capsule()) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 40)
                    .frame(width: viewport.size.width)
                }
                .coordinateSpace(name: "publicProfileScroll")
                .onPreferenceChange(PublicProfileScrollOffsetKey.self) { scrollOffset = $0 }
            }
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                async let profile = container.repository.fetchProfile(id: current.id)
                async let badges = container.repository.fetchEquippedCardBadges(profileID: current.id)
                async let allBadges = container.repository.fetchOwnedProfileBadges(profileID: current.id)
                async let featured = container.repository.fetchFeaturedProfileCard(profileID: current.id)
                async let collectorRequest = container.repository.fetchCollectorProfile(profileID: current.id)
                async let presenceRequest = container.repository.fetchProfileMusicPresence(profileID: current.id)
                async let wishlistRequest = container.repository.fetchUserWishlist(username: current.username)
                async let foldersRequest = container.repository.fetchCardFolders(profileID: current.id)
                async let marketRequest = container.repository.fetchPublicCardOffers(profileID: current.id)
                current = try await profile
                equippedBadges = try await badges
                ownedBadgeCount = (try? await allBadges)?.count ?? current.ownedBadgeCount ?? equippedBadges.count
                featuredCard = try? await featured
                collector = try? await collectorRequest
                presence = try? await presenceRequest
                wishlist = (try? await wishlistRequest) ?? []
                folders = (try? await foldersRequest) ?? []
                marketOffers = (try? await marketRequest) ?? []
                if let path = current.backgroundPath { backgroundURL = try? await container.repository.signedAvatarURL(path: path) }
                if current.id != session.userID {
                    async let cards = container.repository.fetchCardInventory()
                    async let dashboard = container.repository.fetchCardDashboard()
                    ownCards = (try? await cards) ?? []
                    ownCoinBalance = (try? await dashboard)?.coinBalance ?? 0
                }
            }
            catch { errorMessage = error.localizedDescription }
        }
        .alert("Não foi possível carregar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showingTrade) {
            CreateCardTradeView(ownCards: ownCards, coinBalance: ownCoinBalance, initialUsername: current.username, onCreated: {})
        }
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

    @MainActor private func refreshMarket() async {
        marketOffers = (try? await container.repository.fetchPublicCardOffers(profileID: current.id)) ?? []
    }
}

private struct PublicProfileScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct PublicProfileBackdrop: View {
    let url: URL?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [YePlyTheme.accentSoft.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottom)
                if let url {
                    ProfileMediaImage(url: url).frame(width: proxy.size.width, height: proxy.size.height)
                }
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.25), location: 0.55), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            }.clipped()
        }
    }
}

struct PublicProfilePresencePanel: View {
    let presence: ProfileMusicPresence
    var body: some View {
        HStack(spacing: 13) {
            CardBrowserArtwork(path: presence.artworkPath, seed: presence.trackId?.uuidString ?? presence.title, title: presence.title, tint: YePlyTheme.accent, cornerRadius: 13)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    NowPlayingBars(isPlaying: presence.isPlaying)
                    Text(presence.isPlaying ? "OUVINDO AGORA" : "OUVIU RECENTEMENTE").font(.caption2.bold()).tracking(1.2).foregroundStyle(YePlyTheme.accent)
                }
                Text(presence.title).font(.subheadline.bold()).lineLimit(1)
                Text("\(presence.artistName) · \(time(presence.positionSeconds))").font(.caption).foregroundStyle(YePlyTheme.secondary)
                ProgressView(value: presence.progress).tint(YePlyTheme.accent)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    private func time(_ seconds: Int) -> String { "\(seconds / 60):\(String(format: "%02d", seconds % 60))" }
}

private struct NowPlayingBars: View {
    let isPlaying: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.32, paused: !isPlaying)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 3)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(YePlyTheme.accent).frame(width: 3, height: CGFloat(5 + ((phase + index * 3) % 4) * 3))
                }
            }.frame(width: 18, height: 16)
        }
    }
}

struct PublicCollectorPanel: View {
    let summary: CollectorProfileSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Perfil de colecionador", systemImage: "sparkles.rectangle.stack.fill").font(.headline)
            HStack { metric(summary.totalCards, "cartas"); metric(summary.uniqueCards, "únicas"); metric(summary.completedAlbums, "álbuns"); metric(summary.completedTrades, "trocas") }
            if let title = summary.rarestTitle { Text("Destaque raro: \(title)").font(.caption).foregroundStyle(YePlyTheme.secondary) }
        }.padding(16).background(YePlyTheme.elevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
    }
    private func metric(_ value: Int, _ label: String) -> some View { VStack { Text(value.formatted()).font(.headline.bold()); Text(label).font(.caption2).foregroundStyle(YePlyTheme.secondary) }.frame(maxWidth: .infinity) }
}

struct PublicWishlistPanel: View {
    let items: [CardWishlistItem]
    var proposeTrade: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cartas desejadas", systemImage: "heart.fill").font(.headline)
                Spacer()
                if let proposeTrade { Button("Oferecer", action: proposeTrade).font(.caption.bold()) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(items.prefix(8)) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        CardBrowserArtwork(path: item.artworkPath, seed: item.definitionId.uuidString, title: item.title, tint: item.rarity.accentColor, cornerRadius: 12)
                            .aspectRatio(1, contentMode: .fit)
                        Text(item.title).font(.caption2.bold()).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if items.isEmpty {
                Text("Nenhuma carta adicionada ainda.").font(.caption).foregroundStyle(YePlyTheme.secondary)
            }
        }.padding(16).background(YePlyTheme.elevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PublicFoldersPanel: View {
    let folders: [CardFolder]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pastas públicas", systemImage: "folder.fill").font(.headline)
            ForEach(folders) { folder in
                HStack { Text(folder.emoji).font(.title2); VStack(alignment: .leading) { Text(folder.name).font(.subheadline.bold()); Text("\(folder.itemCount) cartas").font(.caption).foregroundStyle(YePlyTheme.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                    .padding(12).background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 15))
            }
            if folders.isEmpty {
                Text("Nenhuma pasta pública criada ainda.").font(.caption).foregroundStyle(YePlyTheme.secondary)
            }
        }.padding(16).background(YePlyTheme.elevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ProfileMarketPanel: View {
    @EnvironmentObject private var container: AppContainer
    let offers: [CardPublicOffer]
    let isOwner: Bool
    let didChange: @MainActor () async -> Void
    @State private var buying: UUID?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mercado", systemImage: "storefront.fill").font(.headline)
                Spacer()
                Text("7% de taxa").font(.caption2.bold()).foregroundStyle(YePlyTheme.tertiary)
            }
            ForEach(offers.prefix(8)) { offer in
                HStack(spacing: 11) {
                    CardBrowserArtwork(path: offer.artworkPath, seed: offer.definitionId.uuidString, title: offer.title, tint: offer.rarity.accentColor, cornerRadius: 12)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(offer.title).font(.subheadline.bold()).lineLimit(1)
                        Text(offer.albumName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                        Text("¥ \(offer.askingCoins.formatted())").font(.caption.bold()).foregroundStyle(YePlyTheme.accent)
                    }
                    Spacer()
                    if !isOwner {
                        Button {
                            Task { await buy(offer) }
                        } label: {
                            if buying == offer.id { ProgressView().tint(.black) }
                            else { Text("Comprar").font(.caption.bold()) }
                        }
                        .buttonStyle(.plain).foregroundStyle(.black)
                        .frame(width: 76, height: 36).background(YePlyTheme.accent, in: Capsule())
                        .disabled(buying != nil)
                    }
                }
                .padding(10).background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 16))
            }
            if offers.isEmpty {
                Text("Nenhuma carta à venda agora.").font(.caption).foregroundStyle(YePlyTheme.secondary)
            }
        }
        .padding(16).background(YePlyTheme.elevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .alert("Mercado", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
    }

    @MainActor private func buy(_ offer: CardPublicOffer) async {
        buying = offer.id
        defer { buying = nil }
        do {
            let result = try await container.repository.buyPublicCardOffer(id: offer.id)
            message = "Compra concluída por ¥ \(result.price.formatted()). O vendedor recebeu ¥ \(result.sellerReceives.formatted()) após a taxa."
            await didChange()
        } catch { message = error.localizedDescription }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @State private var current: ArtistSummary
    @State private var playlists: [Playlist] = []
    @State private var errorMessage: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(artist: ArtistSummary) { _current = State(initialValue: artist) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack { Circle().fill(YePlyTheme.elevated); Image(systemName: "music.mic").font(.system(size: 42)).foregroundStyle(YePlyTheme.accent) }.frame(width: 112, height: 112).padding(.top, 22)
                HStack(spacing: 7) {
                    Text(current.artistName).font(.title.bold()).multilineTextAlignment(.center)
                    if current.isVerified { VerifiedArtistBadge(size: 23) }
                }
                FollowButton(isFollowing: current.isFollowed) { Task { await toggleFollow() } }
                if session.isAdmin {
                    Button { Task { await toggleVerification() } } label: {
                        Label(current.isVerified ? "Remover verificação" : "Verificar artista", systemImage: current.isVerified ? "checkmark.seal.fill" : "checkmark.seal")
                    }
                    .buttonStyle(.bordered).tint(.blue)
                }
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

    private func toggleVerification() async {
        do { current.isVerified = try await container.repository.toggleArtistVerification(artistName: current.artistName) }
        catch { errorMessage = error.localizedDescription }
    }
}
