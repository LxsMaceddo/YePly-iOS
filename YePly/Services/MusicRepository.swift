import Foundation

struct TrackUpload: Sendable {
    let fileURL: URL
    let title: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let fileSize: Int64
    let waveformSamples: [Double]?
}

protocol MusicRepository: Sendable {
    func fetchLibrary(scope: LibraryScope) async throws -> [Playlist]
    func fetchPlaylist(id: UUID) async throws -> Playlist
    func fetchTracks(playlistID: UUID) async throws -> [Track]
    func acceptSharedPlaylist(token: UUID) async throws -> Playlist
    func createPlaylist(_ input: NewPlaylist) async throws -> Playlist
    func updatePlaylist(_ playlist: Playlist) async throws
    func uploadCover(_ jpegData: Data, for playlist: Playlist) async throws -> String
    func deletePlaylist(id: UUID) async throws
    func uploadTrack(_ upload: TrackUpload, to playlist: Playlist, uploaderID: UUID, position: Int) async throws -> Track
    func deleteTrack(_ track: Track) async throws
    func signedAudioURL(for track: Track) async throws -> URL
    func signedCoverURL(path: String) async throws -> URL
    func signedAvatarURL(path: String) async throws -> URL
    func searchProfiles(query: String) async throws -> [UserProfile]
    func fetchProfile(id: UUID) async throws -> UserProfile
    func toggleUserFollow(userID: UUID) async throws -> Bool
    func searchArtists(query: String) async throws -> [ArtistSummary]
    func fetchArtistPlaylists(artistKey: String) async throws -> [Playlist]
    func toggleArtistFollow(artistName: String) async throws -> Bool
    func toggleArtistVerification(artistName: String) async throws -> Bool
    func searchPlaylists(query: String) async throws -> [Playlist]
    func togglePlaylistFollow(playlistID: UUID) async throws -> Bool
    func recordPlaylistView(playlistID: UUID) async throws -> Int
    func toggleTrackLike(trackID: UUID) async throws -> Bool
    func fetchTrackComments(trackID: UUID) async throws -> [TrackComment]
    func addTrackComment(trackID: UUID, userID: UUID, body: String, timestampSeconds: Double?) async throws
    func deleteTrackComment(commentID: UUID) async throws
    func toggleCommentLike(commentID: UUID) async throws -> Bool
    func fetchTrackSocialSummary(trackID: UUID) async throws -> TrackSocialSummary
    func recordPlayback(trackID: UUID, positionSeconds: Double) async throws
    func fetchPlaybackHistory() async throws -> [PlaybackHistoryItem]
    func fetchTopPublicTracks(limit: Int) async throws -> [PublicTrackRankingItem]
    func searchPublicTracks(query: String, limit: Int) async throws -> [PublicTrackRankingItem]
    func clearPlaybackHistory() async throws
    func fetchNotifications() async throws -> [SocialNotification]
    func markAllNotificationsRead() async throws
    func fetchCardDashboard() async throws -> CardGameDashboard
    func fetchCardInventory() async throws -> [CollectibleCardItem]
    func fetchCardPacks() async throws -> [CardPackSummary]
    func fetchCardAlbumProgress() async throws -> [CardAlbumProgress]
    func fetchCardAlbumCatalog() async throws -> [CardAlbumCatalogItem]
    func fetchEquippedCardBadges(profileID: UUID) async throws -> [EquippedAlbumBadge]
    func fetchCardAchievements() async throws -> [CardAchievement]
    func fetchCardArtists() async throws -> [CardArtistOption]
    func fetchCardTrades() async throws -> [CardTradeSummary]
    func fetchTradeableCards(username: String) async throws -> [CollectibleCardItem]
    func claimDailyCardReward() async throws -> CardRewardResult
    func createCardPackCode(_ code: String, label: String?, maxRedemptions: Int, artistKey: String?, cardCount: Int, rarityFloor: CollectibleCardRarity) async throws -> UUID
    func adminGrantCardPacks(username: String, packCount: Int, cardCount: Int, artistKey: String?, rarityFloor: CollectibleCardRarity, reason: String?) async throws -> CardRewardResult
    func redeemPackCode(_ code: String) async throws -> CardRewardResult
    func openCardPack(id: UUID) async throws -> [CollectibleCardItem]
    func recordCardListening(trackID: UUID, listenedSeconds: Int) async throws -> CardRewardResult
    func setFavoriteCardArtists(_ artistKeys: [String]) async throws -> CardRewardResult
    func equipCardBadge(id: UUID, slot: Int) async throws -> CardRewardResult
    func claimCardAchievement(key: String, artistKey: String) async throws -> CardRewardResult
    func createCardTrade(receiverID: UUID, offeredCardIDs: [UUID], requestedCardIDs: [UUID]) async throws -> UUID
    func respondToCardTrade(id: UUID, accept: Bool) async throws -> CardRewardResult
    func recordNowPlayingShare(trackID: UUID) async throws -> CardRewardResult
    func syncCollectibleCatalog(artistName: String) async throws -> CardRewardResult
    func refreshCardRarities() async throws -> CardRewardResult
}

actor DemoMusicRepository: MusicRepository {
    private var playlists: [Playlist]
    private var tracksByPlaylist: [UUID: [Track]]
    private var followedPlaylists: Set<UUID> = []
    private var followedArtists: Set<String> = []
    private var likedTracks: Set<UUID> = []
    private var commentsByTrack: [UUID: [TrackComment]] = [:]
    private var verifiedArtists: Set<String> = ["yeply sessions"]
    private var history: [PlaybackHistoryItem] = []
    private let demoUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    init() {
        let first = Playlist(id: UUID(uuidString: "A1111111-1111-1111-1111-111111111111")!, ownerId: demoUserID, title: "Entrelinhas", artistName: "Lua Norte", summary: "Uma seleção para ouvir sem pressa.", coverPath: nil, visibility: .publicAccess, shareToken: UUID(), isFeatured: true, createdAt: .now, updatedAt: .now, trackCount: 5)
        let second = Playlist(id: UUID(uuidString: "A2222222-2222-2222-2222-222222222222")!, ownerId: demoUserID, title: "Noite Inteira", artistName: "YePly Sessions", summary: "Eletrônica, textura e movimento.", coverPath: nil, visibility: .unlisted, shareToken: UUID(), isFeatured: true, createdAt: .now, updatedAt: .now, trackCount: 4)
        let third = Playlist(id: UUID(uuidString: "A3333333-3333-3333-3333-333333333333")!, ownerId: UUID(), title: "Horizonte", artistName: "Mar Aberto", summary: "Músicas compartilhadas com você.", coverPath: nil, visibility: .privateAccess, shareToken: UUID(), isFeatured: false, createdAt: .now, updatedAt: .now, trackCount: 3)
        let fourth = Playlist(id: UUID(uuidString: "A4444444-4444-4444-4444-444444444444")!, ownerId: demoUserID, title: "Arquivos Vol. 01", artistName: "Vitor", summary: "Faixas pessoais e demos.", coverPath: nil, visibility: .privateAccess, shareToken: UUID(), isFeatured: false, createdAt: .now, updatedAt: .now, trackCount: 2)
        playlists = [first, second, third, fourth]
        tracksByPlaylist = Dictionary(uniqueKeysWithValues: playlists.map { playlist in
            let count = playlist.trackCount ?? 3
            return (playlist.id, (0..<count).map { index in
                Track(id: UUID(), playlistId: playlist.id, uploaderId: playlist.ownerId, title: ["Abertura", "Sem Sinal", "Outro Lugar", "Depois das Três", "Luz Baixa"][index % 5], artistName: playlist.artistName, albumName: playlist.title, durationSeconds: Double(154 + index * 27), audioPath: "demo/track-\(index).mp3", artworkPath: nil, position: index, fileSizeBytes: nil, createdAt: .now)
            })
        })
    }

    func fetchLibrary(scope: LibraryScope) async throws -> [Playlist] {
        switch scope {
        case .all: playlists
        case .mine: playlists.filter { $0.ownerId == demoUserID }
        case .shared: playlists.filter { $0.ownerId != demoUserID }
        }
    }

    func fetchPlaylist(id: UUID) async throws -> Playlist {
        guard let playlist = playlists.first(where: { $0.id == id }) else { throw YePlyError.invalidLink }
        return playlist
    }

    func fetchTracks(playlistID: UUID) async throws -> [Track] { tracksByPlaylist[playlistID] ?? [] }

    func acceptSharedPlaylist(token: UUID) async throws -> Playlist {
        guard let playlist = playlists.first(where: { $0.shareToken == token }) else { throw YePlyError.invalidLink }
        return playlist
    }

    func createPlaylist(_ input: NewPlaylist) async throws -> Playlist {
        let playlist = Playlist(id: UUID(), ownerId: input.ownerId, title: input.title, artistName: input.artistName, summary: input.summary, coverPath: nil, visibility: input.visibility, shareToken: UUID(), isFeatured: false, createdAt: .now, updatedAt: .now, trackCount: 0)
        playlists.insert(playlist, at: 0)
        tracksByPlaylist[playlist.id] = []
        return playlist
    }

    func updatePlaylist(_ playlist: Playlist) async throws {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { throw YePlyError.invalidLink }
        playlists[index] = playlist
    }

    func uploadCover(_ jpegData: Data, for playlist: Playlist) async throws -> String { "demo/\(playlist.id.uuidString)/cover.jpg" }

    func deletePlaylist(id: UUID) async throws {
        playlists.removeAll { $0.id == id }
        tracksByPlaylist[id] = nil
    }

    func uploadTrack(_ upload: TrackUpload, to playlist: Playlist, uploaderID: UUID, position: Int) async throws -> Track {
        let track = Track(id: UUID(), playlistId: playlist.id, uploaderId: uploaderID, title: upload.title, artistName: upload.artistName, albumName: upload.albumName, durationSeconds: upload.duration, audioPath: upload.fileURL.lastPathComponent, artworkPath: nil, position: position, fileSizeBytes: upload.fileSize, createdAt: .now, waveformSamples: upload.waveformSamples)
        tracksByPlaylist[playlist.id, default: []].append(track)
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) { playlists[index].trackCount = tracksByPlaylist[playlist.id]?.count }
        return track
    }

    func deleteTrack(_ track: Track) async throws { tracksByPlaylist[track.playlistId]?.removeAll { $0.id == track.id } }
    func signedAudioURL(for track: Track) async throws -> URL { throw YePlyError.message("Adicione seu backend para reproduzir os arquivos reais.") }
    func signedCoverURL(path: String) async throws -> URL { throw YePlyError.configurationMissing }
    func signedAvatarURL(path: String) async throws -> URL { throw YePlyError.configurationMissing }

    func searchProfiles(query: String) async throws -> [UserProfile] {
        let profile = UserProfile(id: demoUserID, displayName: "Vitor", username: "vitor", avatarPath: nil, bio: "Criando e descobrindo música no YePly.", tastes: ["Rap", "R&B"], role: .admin, createdAt: .now, followerCount: 24, followingCount: 18, isFollowed: false)
        return query.isEmpty || profile.displayName.localizedCaseInsensitiveContains(query) || profile.username.localizedCaseInsensitiveContains(query) ? [profile] : []
    }

    func fetchProfile(id: UUID) async throws -> UserProfile {
        guard id == demoUserID else { throw YePlyError.invalidLink }
        guard let profile = try await searchProfiles(query: "").first else { throw YePlyError.invalidLink }
        return profile
    }

    func toggleUserFollow(userID: UUID) async throws -> Bool { false }

    func searchArtists(query: String) async throws -> [ArtistSummary] {
        let allTracks = tracksByPlaylist.values.flatMap { $0 }
        let names = Set(
            playlists.flatMap { ArtistCreditParser.names(from: $0.artistName) }
                + allTracks.flatMap { ArtistCreditParser.names(from: $0.artistName) }
        )
        return names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.sorted().map { name in
            let key = ArtistCreditParser.key(for: name)
            let artistTracks = allTracks.filter {
                ArtistCreditParser.names(from: $0.artistName).contains { ArtistCreditParser.key(for: $0) == key }
            }
            let playlistIDs = Set(
                playlists.filter { playlist in
                    ArtistCreditParser.names(from: playlist.artistName).contains { ArtistCreditParser.key(for: $0) == key }
                        || artistTracks.contains { track in track.playlistId == playlist.id }
                }.map(\.id)
            )
            return ArtistSummary(artistKey: key, artistName: name, playlistCount: playlistIDs.count, trackCount: artistTracks.count, followerCount: followedArtists.contains(key) ? 1 : 0, isFollowed: followedArtists.contains(key), isVerified: verifiedArtists.contains(key))
        }
    }

    func fetchArtistPlaylists(artistKey: String) async throws -> [Playlist] {
        let matchingPlaylistIDs = Set(tracksByPlaylist.values.flatMap { $0 }.filter {
            ArtistCreditParser.names(from: $0.artistName).contains { ArtistCreditParser.key(for: $0) == artistKey }
        }.map(\.playlistId))
        return playlists.filter {
            matchingPlaylistIDs.contains($0.id)
                || ArtistCreditParser.names(from: $0.artistName).contains { ArtistCreditParser.key(for: $0) == artistKey }
        }
    }

    func toggleArtistFollow(artistName: String) async throws -> Bool {
        let key = artistName.lowercased()
        if followedArtists.contains(key) { followedArtists.remove(key); return false }
        followedArtists.insert(key); return true
    }

    func toggleArtistVerification(artistName: String) async throws -> Bool {
        let key = artistName.lowercased()
        if verifiedArtists.contains(key) { verifiedArtists.remove(key); return false }
        verifiedArtists.insert(key); return true
    }

    func searchPlaylists(query: String) async throws -> [Playlist] {
        playlists.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artistName.localizedCaseInsensitiveContains(query) }
    }

    func togglePlaylistFollow(playlistID: UUID) async throws -> Bool {
        if followedPlaylists.contains(playlistID) { followedPlaylists.remove(playlistID); return false }
        followedPlaylists.insert(playlistID); return true
    }

    func recordPlaylistView(playlistID: UUID) async throws -> Int { 1 }

    func toggleTrackLike(trackID: UUID) async throws -> Bool {
        if likedTracks.contains(trackID) { likedTracks.remove(trackID); return false }
        likedTracks.insert(trackID); return true
    }

    func fetchTrackComments(trackID: UUID) async throws -> [TrackComment] { commentsByTrack[trackID] ?? [] }

    func addTrackComment(trackID: UUID, userID: UUID, body: String, timestampSeconds: Double?) async throws {
        let comment = TrackComment(id: UUID(), trackId: trackID, userId: userID, body: body, timestampSeconds: timestampSeconds, createdAt: .now, updatedAt: .now, displayName: "Vitor", username: "vitor", avatarPath: nil, likeCount: 0, isLiked: false)
        commentsByTrack[trackID, default: []].append(comment)
    }

    func deleteTrackComment(commentID: UUID) async throws {
        for key in Array(commentsByTrack.keys) { commentsByTrack[key]?.removeAll { $0.id == commentID } }
    }

    func toggleCommentLike(commentID: UUID) async throws -> Bool { true }

    func fetchTrackSocialSummary(trackID: UUID) async throws -> TrackSocialSummary {
        TrackSocialSummary(likeCount: likedTracks.contains(trackID) ? 1 : 0, commentCount: commentsByTrack[trackID]?.count ?? 0, isLiked: likedTracks.contains(trackID))
    }

    func recordPlayback(trackID: UUID, positionSeconds: Double) async throws {
        guard let track = tracksByPlaylist.values.flatMap({ $0 }).first(where: { $0.id == trackID }),
              let playlist = playlists.first(where: { $0.id == track.playlistId }) else { return }
        let previousPlayCount = history.first(where: { $0.trackId == trackID })?.playCount ?? 0
        history.removeAll { $0.trackId == trackID }
        history.insert(PlaybackHistoryItem(trackId: track.id, playlistId: track.playlistId, uploaderId: track.uploaderId, title: track.title, artistName: track.artistName, albumName: track.albumName, durationSeconds: track.durationSeconds, audioPath: track.audioPath, artworkPath: track.artworkPath, position: track.position, fileSizeBytes: track.fileSizeBytes, trackCreatedAt: track.createdAt, waveformSamples: track.waveformSamples, playlistTitle: playlist.title, playlistCoverPath: playlist.coverPath, lastPlayedAt: .now, playCount: previousPlayCount + 1), at: 0)
    }

    func fetchPlaybackHistory() async throws -> [PlaybackHistoryItem] { history }
    func fetchTopPublicTracks(limit: Int) async throws -> [PublicTrackRankingItem] {
        let publicPlaylists = Dictionary(uniqueKeysWithValues: playlists.filter { $0.visibility == .publicAccess }.map { ($0.id, $0) })
        let playCounts = Dictionary(uniqueKeysWithValues: history.map { ($0.trackId, $0.playCount) })
        return tracksByPlaylist.values.flatMap { $0 }
            .compactMap { track -> PublicTrackRankingItem? in
                guard let playlist = publicPlaylists[track.playlistId] else { return nil }
                return PublicTrackRankingItem(
                    trackId: track.id, playlistId: track.playlistId, uploaderId: track.uploaderId,
                    title: track.title, artistName: track.artistName, albumName: track.albumName,
                    durationSeconds: track.durationSeconds, audioPath: track.audioPath,
                    artworkPath: track.artworkPath, position: track.position,
                    fileSizeBytes: track.fileSizeBytes, trackCreatedAt: track.createdAt,
                    waveformSamples: track.waveformSamples, playlistTitle: playlist.title,
                    playlistCoverPath: playlist.coverPath, playCount: playCounts[track.id] ?? 0
                )
            }
            .sorted { lhs, rhs in
                lhs.playCount == rhs.playCount ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : lhs.playCount > rhs.playCount
            }
            .prefix(max(1, limit))
            .map { $0 }
    }
    func searchPublicTracks(query: String, limit: Int) async throws -> [PublicTrackRankingItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await fetchTopPublicTracks(limit: 100)
            .filter {
                clean.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(clean)
                    || $0.artistName.localizedCaseInsensitiveContains(clean)
                    || $0.playlistTitle.localizedCaseInsensitiveContains(clean)
            }
            .prefix(max(1, limit))
            .map { $0 }
    }
    func clearPlaybackHistory() async throws { history.removeAll() }
    func fetchNotifications() async throws -> [SocialNotification] { [] }
    func markAllNotificationsRead() async throws { }

    func fetchCardDashboard() async throws -> CardGameDashboard {
        CardGameDashboard(
            xp: history.reduce(0) { $0 + $1.playCount * 5 }, level: 1, nextLevelXP: 500,
            currentStreak: 1, bestStreak: 1, unopenedPacks: 1, totalCards: 3,
            uniqueCards: 3, completedAlbums: 0, completedTrades: 0,
            favoriteArtists: ["kanye west"], dailyClaimAvailable: true
        )
    }

    func fetchCardInventory() async throws -> [CollectibleCardItem] { demoCards }
    func fetchCardPacks() async throws -> [CardPackSummary] {
        [CardPackSummary(packId: UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!, source: "Boas-vindas", cardCount: 3, createdAt: .now)]
    }
    func fetchCardAlbumProgress() async throws -> [CardAlbumProgress] {
        [CardAlbumProgress(albumId: UUID(), albumTitle: "Coleção de demonstração", artistName: "YePly Sessions", artworkPath: nil, ownedUnique: demoCards.count, totalCards: 13, isComplete: false, badgeId: nil, badgeEquipped: false)]
    }
    func fetchCardAlbumCatalog() async throws -> [CardAlbumCatalogItem] { [] }
    func fetchEquippedCardBadges(profileID: UUID) async throws -> [EquippedAlbumBadge] {
        guard profileID == demoUserID else { return [] }
        return []
    }
    func fetchCardAchievements() async throws -> [CardAchievement] {
        [
            CardAchievement(achievementKey: "night_listener", title: "Night Listener", description: "Ouça 100 músicas entre 00:00 e 05:00.", icon: "moon.stars.fill", progress: 18, target: 100, unlockedAt: nil, rewardClaimedAt: nil),
            CardAchievement(achievementKey: "day_one", title: "Day One", description: "Está no YePly desde a versão Beta.", icon: "figure.wave", progress: 1, target: 1, unlockedAt: .now, rewardClaimedAt: nil)
        ]
    }
    func fetchCardArtists() async throws -> [CardArtistOption] { [CardArtistOption(artistKey: "kanye west", artistName: "Kanye West", cardCount: 3)] }
    func fetchCardTrades() async throws -> [CardTradeSummary] { [] }
    func fetchTradeableCards(username: String) async throws -> [CollectibleCardItem] { demoCards }
    func claimDailyCardReward() async throws -> CardRewardResult { demoReward("Pack diário recebido.") }
    func createCardPackCode(_ code: String, label: String?, maxRedemptions: Int, artistKey: String?, cardCount: Int, rarityFloor: CollectibleCardRarity) async throws -> UUID { UUID() }
    func adminGrantCardPacks(username: String, packCount: Int, cardCount: Int, artistKey: String?, rarityFloor: CollectibleCardRarity, reason: String?) async throws -> CardRewardResult { demoReward("\(packCount) pack(s) enviado(s) para @\(username).") }
    func redeemPackCode(_ code: String) async throws -> CardRewardResult { demoReward("Código resgatado.") }
    func openCardPack(id: UUID) async throws -> [CollectibleCardItem] { demoCards }
    func recordCardListening(trackID: UUID, listenedSeconds: Int) async throws -> CardRewardResult { demoReward(nil) }
    func setFavoriteCardArtists(_ artistKeys: [String]) async throws -> CardRewardResult { demoReward("Artistas favoritos atualizados.") }
    func equipCardBadge(id: UUID, slot: Int) async throws -> CardRewardResult { demoReward("Badge equipada.") }
    func claimCardAchievement(key: String, artistKey: String) async throws -> CardRewardResult { demoReward("Pack de conquista recebido.") }
    func createCardTrade(receiverID: UUID, offeredCardIDs: [UUID], requestedCardIDs: [UUID]) async throws -> UUID { UUID() }
    func respondToCardTrade(id: UUID, accept: Bool) async throws -> CardRewardResult { demoReward(accept ? "Troca concluída." : "Troca recusada.") }
    func recordNowPlayingShare(trackID: UUID) async throws -> CardRewardResult { demoReward("Conquista Show Off atualizada.") }
    func syncCollectibleCatalog(artistName: String) async throws -> CardRewardResult { demoReward("Catálogo sincronizado.") }
    func refreshCardRarities() async throws -> CardRewardResult { demoReward("Raridades recalculadas.") }

    private var demoCards: [CollectibleCardItem] {
        let names = ["Stronger", "Heartless", "Flashing Lights"]
        let rarities: [CollectibleCardRarity] = [.common, .epic, .mythic]
        return names.indices.map { index in
            CollectibleCardItem(
                instanceId: UUID(), serialNumber: index + 1, definitionId: UUID(), trackId: nil,
                title: names[index], artistName: "Kanye West", albumName: "Demonstração",
                artworkPath: nil, rarity: rarities[index], acquiredAt: .now
            )
        }
    }

    private func demoReward(_ message: String?) -> CardRewardResult {
        CardRewardResult(success: true, message: message, packId: nil, packsAwarded: message == nil ? 0 : 1, xpAwarded: 5, streak: 1, achievementKey: nil, rewardClaimed: nil, packDropped: false, accepted: true, claimed: true, redeemed: true)
    }
}
