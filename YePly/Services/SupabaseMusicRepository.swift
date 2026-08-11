import Foundation
import Supabase

private struct ShareTokenInput: Encodable { let pToken: UUID; enum CodingKeys: String, CodingKey { case pToken = "p_token" } }
private struct LibraryInput: Encodable { let pScope: String; enum CodingKeys: String, CodingKey { case pScope = "p_scope" } }
private struct SearchInput: Encodable {
    let pQuery: String
    let pLimit: Int
    enum CodingKeys: String, CodingKey { case pQuery = "p_query"; case pLimit = "p_limit" }
}
private struct ProfileIDInput: Encodable { let pProfileId: UUID; enum CodingKeys: String, CodingKey { case pProfileId = "p_profile_id" } }
private struct CardInventoryPageInput: Encodable {
    let pOffset: Int
    let pLimit: Int
    enum CodingKeys: String, CodingKey { case pOffset = "p_offset"; case pLimit = "p_limit" }
}
private struct CardCatalogPageInput: Encodable {
    let pOffset: Int
    let pLimit: Int
    enum CodingKeys: String, CodingKey { case pOffset = "p_offset"; case pLimit = "p_limit" }
}
private struct CardDefinitionInput: Encodable {
    let pDefinitionId: UUID
    enum CodingKeys: String, CodingKey { case pDefinitionId = "p_definition_id" }
}
private struct CardPackPurchaseInput: Encodable {
    let pProductKey: String
    enum CodingKeys: String, CodingKey { case pProductKey = "p_product_key" }
}
private struct UserFollowInput: Encodable { let pUserId: UUID; enum CodingKeys: String, CodingKey { case pUserId = "p_user_id" } }
private struct PlaylistIDInput: Encodable { let pPlaylistId: UUID; enum CodingKeys: String, CodingKey { case pPlaylistId = "p_playlist_id" } }
private struct TrackIDInput: Encodable { let pTrackId: UUID; enum CodingKeys: String, CodingKey { case pTrackId = "p_track_id" } }
private struct CommentIDInput: Encodable { let pCommentId: UUID; enum CodingKeys: String, CodingKey { case pCommentId = "p_comment_id" } }
private struct ArtistNameInput: Encodable { let pArtistName: String; enum CodingKeys: String, CodingKey { case pArtistName = "p_artist_name" } }
private struct ArtistKeyInput: Encodable { let pArtistKey: String; enum CodingKeys: String, CodingKey { case pArtistKey = "p_artist_key" } }
private struct PlaybackInput: Encodable {
    let pTrackId: UUID
    let pPositionSeconds: Double
    enum CodingKeys: String, CodingKey { case pTrackId = "p_track_id"; case pPositionSeconds = "p_position_seconds" }
}
private struct CardPackInput: Encodable { let pPackId: UUID; enum CodingKeys: String, CodingKey { case pPackId = "p_pack_id" } }
private struct CardCodeInput: Encodable { let pCode: String; enum CodingKeys: String, CodingKey { case pCode = "p_code" } }
private struct CardPackCodeCreationInput: Encodable {
    let pCode: String
    let pLabel: String?
    let pMaxRedemptions: Int
    let pExpiresAt: Date?
    let pArtistKey: String?
    let pCardCount: Int
    let pRarityFloor: CollectibleCardRarity
    enum CodingKeys: String, CodingKey {
        case pCode = "p_code"
        case pLabel = "p_label"
        case pMaxRedemptions = "p_max_redemptions"
        case pExpiresAt = "p_expires_at"
        case pArtistKey = "p_artist_key"
        case pCardCount = "p_card_count"
        case pRarityFloor = "p_rarity_floor"
    }
}
private struct AdminCardPackGrantInput: Encodable {
    let pUsername: String
    let pPackCount: Int
    let pCardCount: Int
    let pArtistKey: String?
    let pRarityFloor: CollectibleCardRarity
    let pReason: String?
    enum CodingKeys: String, CodingKey {
        case pUsername = "p_username"
        case pPackCount = "p_pack_count"
        case pCardCount = "p_card_count"
        case pArtistKey = "p_artist_key"
        case pRarityFloor = "p_rarity_floor"
        case pReason = "p_reason"
    }
}
private struct CardListeningInput: Encodable {
    let pTrackId: UUID
    let pListenedSeconds: Int
    enum CodingKeys: String, CodingKey { case pTrackId = "p_track_id"; case pListenedSeconds = "p_listened_seconds" }
}
private struct FavoriteArtistsInput: Encodable { let pArtistKeys: [String]; enum CodingKeys: String, CodingKey { case pArtistKeys = "p_artist_keys" } }
private struct CardBadgeInput: Encodable {
    let pBadgeId: UUID
    let pSlot: Int
    enum CodingKeys: String, CodingKey { case pBadgeId = "p_badge_id"; case pSlot = "p_slot" }
}
private struct FeaturedCardInput: Encodable {
    let pInstanceId: UUID?
    enum CodingKeys: String, CodingKey { case pInstanceId = "p_instance_id" }
}
private struct CardAchievementInput: Encodable {
    let pAchievementKey: String
    let pArtistKey: String
    enum CodingKeys: String, CodingKey { case pAchievementKey = "p_achievement_key"; case pArtistKey = "p_artist_key" }
}
private struct CardTradeInput: Encodable {
    let pRecipientId: UUID
    let pOfferedIds: [UUID]
    let pRequestedIds: [UUID]
    let pOfferedCoins: Int
    let pRequestedCoins: Int
    enum CodingKeys: String, CodingKey {
        case pRecipientId = "p_recipient_id"
        case pOfferedIds = "p_offered_ids"
        case pRequestedIds = "p_requested_ids"
        case pOfferedCoins = "p_offered_coins"
        case pRequestedCoins = "p_requested_coins"
    }
}
private struct CardTradeResponseInput: Encodable {
    let pTradeId: UUID
    let pAccept: Bool
    enum CodingKeys: String, CodingKey { case pTradeId = "p_trade_id"; case pAccept = "p_accept" }
}
private struct CardTradeIDInput: Encodable {
    let pTradeId: UUID
    enum CodingKeys: String, CodingKey { case pTradeId = "p_trade_id" }
}
private struct ExternalCardCatalogInput: Encodable {
    let artistName: String
    enum CodingKeys: String, CodingKey { case artistName = "artist_name" }
}
private struct ExternalCardCatalogError: Decodable { let error: String? }
private struct CardTradeableInput: Encodable { let pUsername: String; enum CodingKeys: String, CodingKey { case pUsername = "p_username" } }
private struct OptionalProfileIDInput: Encodable { let pProfileId: UUID?; enum CodingKeys: String, CodingKey { case pProfileId = "p_profile_id" } }
private struct CardInstanceInput: Encodable { let pInstanceId: UUID; enum CodingKeys: String, CodingKey { case pInstanceId = "p_instance_id" } }
private struct CardFolderCreateInput: Encodable {
    let pName: String; let pEmoji: String; let pIsPublic: Bool
    enum CodingKeys: String, CodingKey { case pName = "p_name"; case pEmoji = "p_emoji"; case pIsPublic = "p_is_public" }
}
private struct CardFolderIDInput: Encodable { let pFolderId: UUID; enum CodingKeys: String, CodingKey { case pFolderId = "p_folder_id" } }
private struct CardFolderItemInput: Encodable {
    let pFolderId: UUID; let pInstanceId: UUID
    enum CodingKeys: String, CodingKey { case pFolderId = "p_folder_id"; case pInstanceId = "p_instance_id" }
}
private struct PublicOfferInput: Encodable {
    let pInstanceId: UUID; let pAskingCoins: Int; let pNote: String?
    enum CodingKeys: String, CodingKey { case pInstanceId = "p_instance_id"; case pAskingCoins = "p_asking_coins"; case pNote = "p_note" }
}
private struct PresenceInput: Encodable {
    let pTrackId: UUID; let pTitle: String; let pArtistName: String; let pAlbumName: String?
    let pArtworkPath: String?; let pPositionSeconds: Int; let pDurationSeconds: Int; let pIsPlaying: Bool
    enum CodingKeys: String, CodingKey {
        case pTrackId = "p_track_id"; case pTitle = "p_title"; case pArtistName = "p_artist_name"
        case pAlbumName = "p_album_name"; case pArtworkPath = "p_artwork_path"
        case pPositionSeconds = "p_position_seconds"; case pDurationSeconds = "p_duration_seconds"; case pIsPlaying = "p_is_playing"
    }
}
private struct CardTradeFeedResponse: Decodable { let trades: [CardTradeSummary] }
private struct PlaylistUpdate: Encodable {
    let title: String
    let artistName: String
    let summary: String?
    let visibility: PlaylistVisibility
    enum CodingKeys: String, CodingKey { case title; case artistName = "artist_name"; case summary; case visibility }
}

actor SupabaseMusicRepository: MusicRepository {
    private let client: SupabaseClient
    private var signedURLCache: [String: (url: URL, expiresAt: Date)] = [:]

    init(client: SupabaseClient) { self.client = client }

    func fetchLibrary(scope: LibraryScope) async throws -> [Playlist] {
        try await client.rpc("library_playlists_social", params: LibraryInput(pScope: scope.rawValue)).execute().value
    }

    func fetchPlaylist(id: UUID) async throws -> Playlist {
        try await client.rpc("playlist_with_social", params: PlaylistIDInput(pPlaylistId: id)).single().execute().value
    }

    func fetchTracks(playlistID: UUID) async throws -> [Track] {
        try await client.rpc("playlist_tracks_v2", params: PlaylistIDInput(pPlaylistId: playlistID)).execute().value
    }

    func acceptSharedPlaylist(token: UUID) async throws -> Playlist {
        let playlistID: UUID = try await client.rpc("accept_playlist_share", params: ShareTokenInput(pToken: token)).execute().value
        return try await fetchPlaylist(id: playlistID)
    }

    func createPlaylist(_ input: NewPlaylist) async throws -> Playlist {
        try await client.from("playlists").insert(input).select().single().execute().value
    }

    func updatePlaylist(_ playlist: Playlist) async throws {
        let update = PlaylistUpdate(title: playlist.title, artistName: playlist.artistName, summary: playlist.summary, visibility: playlist.visibility)
        try await client.from("playlists").update(update).eq("id", value: playlist.id).execute()
    }

    func uploadCover(_ jpegData: Data, for playlist: Playlist) async throws -> String {
        guard jpegData.count <= 10 * 1_024 * 1_024 else { throw YePlyError.fileTooLarge }
        let path = "\(playlist.id.uuidString.lowercased())/cover/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("covers").upload(
            path,
            data: jpegData,
            options: FileOptions(cacheControl: "86400", contentType: "image/jpeg", upsert: false)
        )
        do {
            try await client.from("playlists").update(["cover_path": path]).eq("id", value: playlist.id).execute()
            if let oldPath = playlist.coverPath { try? await client.storage.from("covers").remove(paths: [oldPath]) }
            return path
        } catch {
            try? await client.storage.from("covers").remove(paths: [path])
            throw error
        }
    }

    func deletePlaylist(id: UUID) async throws {
        try await client.from("playlists").delete().eq("id", value: id).execute()
    }

    func uploadTrack(_ upload: TrackUpload, to playlist: Playlist, uploaderID: UUID, position: Int) async throws -> Track {
        let fileData = try Data(contentsOf: upload.fileURL, options: .mappedIfSafe)
        guard fileData.count <= 200 * 1_024 * 1_024 else { throw YePlyError.fileTooLarge }
        let trackID = UUID()
        let cleanName = upload.fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let objectPath = "\(playlist.id.uuidString.lowercased())/\(trackID.uuidString.lowercased())/\(cleanName).mp3"

        try await client.storage.from("audio").upload(
            objectPath,
            data: fileData,
            options: FileOptions(cacheControl: "3600", contentType: "audio/mpeg", upsert: false)
        )

        do {
            let record = NewTrack(id: trackID, playlistId: playlist.id, uploaderId: uploaderID, title: upload.title, artistName: upload.artistName, albumName: upload.albumName, durationSeconds: upload.duration, audioPath: objectPath, artworkPath: nil, position: position, fileSizeBytes: upload.fileSize, waveformSamples: upload.waveformSamples)
            return try await client.from("tracks").insert(record).select().single().execute().value
        } catch {
            try? await client.storage.from("audio").remove(paths: [objectPath])
            throw error
        }
    }

    func deleteTrack(_ track: Track) async throws {
        try await client.from("tracks").delete().eq("id", value: track.id).execute()
        try await client.storage.from("audio").remove(paths: [track.audioPath])
    }

    func signedAudioURL(for track: Track) async throws -> URL { try await signedURL(bucket: "audio", path: track.audioPath) }
    func signedCoverURL(path: String) async throws -> URL {
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPath.isEmpty else { throw YePlyError.message("Capa inválida.") }

        if let url = URL(string: cleanPath), url.scheme?.lowercased() == "https" { return url }
        return try await signedURL(bucket: "covers", path: cleanPath)
    }
    func signedAvatarURL(path: String) async throws -> URL { try await signedURL(bucket: "avatars", path: path) }

    func searchProfiles(query: String) async throws -> [UserProfile] {
        try await client.rpc("search_profiles", params: SearchInput(pQuery: query, pLimit: 30)).execute().value
    }

    func fetchProfile(id: UUID) async throws -> UserProfile {
        try await client.rpc("profile_with_social", params: ProfileIDInput(pProfileId: id)).single().execute().value
    }

    func toggleUserFollow(userID: UUID) async throws -> Bool {
        try await client.rpc("toggle_user_follow", params: UserFollowInput(pUserId: userID)).execute().value
    }

    func searchArtists(query: String) async throws -> [ArtistSummary] {
        try await client.rpc("search_artists_v2", params: SearchInput(pQuery: query, pLimit: 30)).execute().value
    }

    func fetchArtistPlaylists(artistKey: String) async throws -> [Playlist] {
        try await client.rpc("artist_playlists", params: ArtistKeyInput(pArtistKey: artistKey)).execute().value
    }

    func toggleArtistFollow(artistName: String) async throws -> Bool {
        try await client.rpc("toggle_artist_follow", params: ArtistNameInput(pArtistName: artistName)).execute().value
    }

    func toggleArtistVerification(artistName: String) async throws -> Bool {
        try await client.rpc("toggle_artist_verification", params: ArtistNameInput(pArtistName: artistName)).execute().value
    }

    func searchPlaylists(query: String) async throws -> [Playlist] {
        try await client.rpc("search_playlists", params: SearchInput(pQuery: query, pLimit: 40)).execute().value
    }

    func togglePlaylistFollow(playlistID: UUID) async throws -> Bool {
        try await client.rpc("toggle_playlist_follow", params: PlaylistIDInput(pPlaylistId: playlistID)).execute().value
    }

    func recordPlaylistView(playlistID: UUID) async throws -> Int {
        try await client.rpc("record_playlist_view", params: PlaylistIDInput(pPlaylistId: playlistID)).execute().value
    }

    func toggleTrackLike(trackID: UUID) async throws -> Bool {
        try await client.rpc("toggle_track_like", params: TrackIDInput(pTrackId: trackID)).execute().value
    }

    func fetchTrackComments(trackID: UUID) async throws -> [TrackComment] {
        try await client.rpc("track_comments_with_timestamps", params: TrackIDInput(pTrackId: trackID)).execute().value
    }

    func addTrackComment(trackID: UUID, userID: UUID, body: String, timestampSeconds: Double?) async throws {
        let comment = NewTrackComment(trackId: trackID, userId: userID, body: body, timestampSeconds: timestampSeconds)
        try await client.from("track_comments").insert(comment).execute()
    }

    func deleteTrackComment(commentID: UUID) async throws {
        try await client.from("track_comments").delete().eq("id", value: commentID).execute()
    }

    func toggleCommentLike(commentID: UUID) async throws -> Bool {
        try await client.rpc("toggle_comment_like", params: CommentIDInput(pCommentId: commentID)).execute().value
    }

    func fetchTrackSocialSummary(trackID: UUID) async throws -> TrackSocialSummary {
        try await client.rpc("track_social_summary", params: TrackIDInput(pTrackId: trackID)).single().execute().value
    }

    func recordPlayback(trackID: UUID, positionSeconds: Double) async throws {
        try await client.rpc("record_playback", params: PlaybackInput(pTrackId: trackID, pPositionSeconds: positionSeconds)).execute()
    }

    func fetchPlaybackHistory() async throws -> [PlaybackHistoryItem] {
        try await client.rpc("playback_history_feed", params: ["p_limit": 150]).execute().value
    }

    func fetchTopPublicTracks(limit: Int) async throws -> [PublicTrackRankingItem] {
        try await client.rpc("top_public_tracks", params: ["p_limit": min(max(limit, 1), 100)]).execute().value
    }

    func searchPublicTracks(query: String, limit: Int) async throws -> [PublicTrackRankingItem] {
        try await client.rpc(
            "search_public_tracks",
            params: SearchInput(pQuery: query, pLimit: min(max(limit, 1), 100))
        ).execute().value
    }

    func clearPlaybackHistory() async throws {
        try await client.rpc("clear_playback_history").execute()
    }

    func fetchNotifications() async throws -> [SocialNotification] {
        try await client.rpc("notifications_feed", params: ["p_limit": 60]).execute().value
    }

    func markAllNotificationsRead() async throws {
        try await client.rpc("mark_all_notifications_read").execute()
    }

    func fetchCardDashboard() async throws -> CardGameDashboard {
        try await client.rpc("card_game_dashboard").execute().value
    }

    func fetchCardInventory() async throws -> [CollectibleCardItem] {
        let pageSize = 500
        var offset = 0
        var result: [CollectibleCardItem] = []
        while true {
            let page: [CollectibleCardItem]
            do {
                page = try await client.rpc(
                    "card_inventory_social_feed_page",
                    params: CardInventoryPageInput(pOffset: offset, pLimit: pageSize)
                ).execute().value
            } catch {
                page = try await client.rpc(
                    "card_inventory_feed_page",
                    params: CardInventoryPageInput(pOffset: offset, pLimit: pageSize)
                ).execute().value
            }
            result.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += page.count
        }
        return result
    }

    func fetchCardPacks() async throws -> [CardPackSummary] {
        try await client.rpc("card_pack_feed").execute().value
    }

    func fetchCardAlbumProgress() async throws -> [CardAlbumProgress] {
        try await client.rpc("card_album_progress").execute().value
    }

    func fetchCardAlbumCatalog() async throws -> [CardAlbumCatalogItem] {
        let pageSize = 500
        var offset = 0
        var result: [CardAlbumCatalogItem] = []
        do {
            while true {
                let page: [CardAlbumCatalogItem] = try await client.rpc(
                    "card_album_catalog_feed_page",
                    params: CardCatalogPageInput(pOffset: offset, pLimit: pageSize)
                ).execute().value
                result.append(contentsOf: page)
                if page.count < pageSize { return result }
                offset += page.count
            }
        } catch {
            // Compatibilidade com backends anteriores durante a migração do feed paginado.
            return try await client.rpc("card_album_catalog_feed").execute().value
        }
    }

    func fetchEquippedCardBadges(profileID: UUID) async throws -> [EquippedAlbumBadge] {
        try await client.rpc(
            "profile_equipped_card_badges",
            params: ProfileIDInput(pProfileId: profileID)
        ).execute().value
    }

    func fetchOwnedProfileBadges(profileID: UUID) async throws -> [ProfileCollectibleBadge] {
        try await client.rpc(
            "profile_owned_badges",
            params: ProfileIDInput(pProfileId: profileID)
        ).execute().value
    }

    func fetchFeaturedProfileCard(profileID: UUID) async throws -> CollectibleCardItem? {
        let cards: [CollectibleCardItem] = try await client.rpc(
            "profile_featured_card",
            params: ProfileIDInput(pProfileId: profileID)
        ).execute().value
        return cards.first
    }

    func fetchCardAchievements() async throws -> [CardAchievement] {
        try await client.rpc("card_achievement_feed").execute().value
    }

    func fetchCardArtists() async throws -> [CardArtistOption] {
        try await client.rpc("card_available_artists").execute().value
    }

    func fetchCardTrades() async throws -> [CardTradeSummary] {
        let response: CardTradeFeedResponse = try await client.rpc("card_trade_feed").execute().value
        return response.trades
    }

    func fetchTradeableCards(username: String) async throws -> [CollectibleCardItem] {
        try await client.rpc("card_tradeable_inventory", params: CardTradeableInput(pUsername: username)).execute().value
    }

    func fetchCardWishlist() async throws -> [CardWishlistItem] {
        try await client.rpc("card_wishlist_feed").execute().value
    }

    func toggleCardWishlist(definitionID: UUID) async throws -> CardRewardResult {
        try await client.rpc(
            "toggle_card_wishlist",
            params: CardDefinitionInput(pDefinitionId: definitionID)
        ).execute().value
    }

    func fetchCardPackStore() async throws -> [CardPackStoreProduct] {
        try await client.rpc("card_pack_store").execute().value
    }

    func buyCardPack(product: CardPackProductKind) async throws -> CardRewardResult {
        try await client.rpc(
            "buy_card_pack",
            params: CardPackPurchaseInput(pProductKey: product.rawValue)
        ).execute().value
    }

    func claimDailyCardReward() async throws -> CardRewardResult {
        try await client.rpc("claim_daily_card_reward").execute().value
    }

    func createCardPackCode(_ code: String, label: String?, maxRedemptions: Int, artistKey: String?, cardCount: Int, rarityFloor: CollectibleCardRarity) async throws -> UUID {
        try await client.rpc(
            "create_card_pack_code",
            params: CardPackCodeCreationInput(
                pCode: code, pLabel: label, pMaxRedemptions: maxRedemptions,
                pExpiresAt: nil, pArtistKey: artistKey, pCardCount: cardCount,
                pRarityFloor: rarityFloor
            )
        ).execute().value
    }

    func adminGrantCardPacks(username: String, packCount: Int, cardCount: Int, artistKey: String?, rarityFloor: CollectibleCardRarity, reason: String?) async throws -> CardRewardResult {
        try await client.rpc(
            "admin_grant_card_packs",
            params: AdminCardPackGrantInput(
                pUsername: username, pPackCount: packCount, pCardCount: cardCount,
                pArtistKey: artistKey, pRarityFloor: rarityFloor, pReason: reason
            )
        ).execute().value
    }

    func redeemPackCode(_ code: String) async throws -> CardRewardResult {
        do {
            return try await client.rpc("redeem_pack_code", params: CardCodeInput(pCode: code)).execute().value
        } catch {
            let diagnostic = "\(error.localizedDescription) \(String(describing: error))".lowercased()
            if diagnostic.contains("pack_code_already_redeemed") {
                throw YePlyError.message("Você já resgatou este código nesta conta.")
            }
            if diagnostic.contains("pack_code_expired") {
                throw YePlyError.message("Este código de pack expirou.")
            }
            if diagnostic.contains("pack_code_exhausted") {
                throw YePlyError.message("Este código atingiu o limite de resgates.")
            }
            if diagnostic.contains("invalid_pack_code") {
                throw YePlyError.message("Código de pack inválido.")
            }
            throw error
        }
    }

    func openCardPack(id: UUID) async throws -> [CollectibleCardItem] {
        try await client.rpc("open_card_pack", params: CardPackInput(pPackId: id)).execute().value
    }

    func recordCardListening(trackID: UUID, listenedSeconds: Int) async throws -> CardRewardResult {
        try await client.rpc("record_card_listening", params: CardListeningInput(pTrackId: trackID, pListenedSeconds: listenedSeconds)).execute().value
    }

    func setFavoriteCardArtists(_ artistKeys: [String]) async throws -> CardRewardResult {
        try await client.rpc("set_favorite_artists", params: FavoriteArtistsInput(pArtistKeys: artistKeys)).execute().value
    }

    func equipCardBadge(id: UUID, slot: Int) async throws -> CardRewardResult {
        try await client.rpc("equip_card_badge", params: CardBadgeInput(pBadgeId: id, pSlot: slot)).execute().value
    }

    func setFeaturedProfileCard(instanceID: UUID?) async throws -> CardRewardResult {
        try await client.rpc(
            "set_profile_featured_card",
            params: FeaturedCardInput(pInstanceId: instanceID)
        ).execute().value
    }

    func claimCardAchievement(key: String, artistKey: String) async throws -> CardRewardResult {
        try await client.rpc("claim_card_achievement", params: CardAchievementInput(pAchievementKey: key, pArtistKey: artistKey)).execute().value
    }

    func createCardTrade(receiverID: UUID, offeredCardIDs: [UUID], requestedCardIDs: [UUID], offeredCoins: Int, requestedCoins: Int) async throws -> UUID {
        try await client.rpc(
            "create_card_trade",
            params: CardTradeInput(
                pRecipientId: receiverID,
                pOfferedIds: offeredCardIDs,
                pRequestedIds: requestedCardIDs,
                pOfferedCoins: offeredCoins,
                pRequestedCoins: requestedCoins
            )
        ).execute().value
    }

    func respondToCardTrade(id: UUID, accept: Bool) async throws -> CardRewardResult {
        try await client.rpc("respond_card_trade", params: CardTradeResponseInput(pTradeId: id, pAccept: accept)).execute().value
    }

    func fetchTradeDetail(id: UUID) async throws -> [CardTradeDetailItem] {
        try await client.rpc("card_trade_detail", params: CardTradeIDInput(pTradeId: id)).execute().value
    }

    func toggleCardProtection(instanceID: UUID) async throws -> CardRewardResult {
        try await client.rpc("toggle_card_protection", params: CardInstanceInput(pInstanceId: instanceID)).execute().value
    }

    func fetchCardFolders(profileID: UUID?) async throws -> [CardFolder] {
        try await client.rpc("card_folder_feed", params: OptionalProfileIDInput(pProfileId: profileID)).execute().value
    }

    func createCardFolder(name: String, emoji: String, isPublic: Bool) async throws -> UUID {
        try await client.rpc("create_card_folder", params: CardFolderCreateInput(pName: name, pEmoji: emoji, pIsPublic: isPublic)).execute().value
    }

    func deleteCardFolder(id: UUID) async throws -> Bool {
        try await client.rpc("delete_card_folder", params: CardFolderIDInput(pFolderId: id)).execute().value
    }

    func toggleCardFolderItem(folderID: UUID, instanceID: UUID) async throws -> CardRewardResult {
        try await client.rpc("toggle_card_folder_item", params: CardFolderItemInput(pFolderId: folderID, pInstanceId: instanceID)).execute().value
    }

    func fetchUserWishlist(username: String) async throws -> [CardWishlistItem] {
        try await client.rpc("card_user_wishlist", params: CardTradeableInput(pUsername: username)).execute().value
    }

    func fetchCollectorProfile(profileID: UUID) async throws -> CollectorProfileSummary? {
        let rows: [CollectorProfileSummary] = try await client.rpc("card_collector_profile", params: ProfileIDInput(pProfileId: profileID)).execute().value
        return rows.first
    }

    func fetchProfileMusicPresence(profileID: UUID) async throws -> ProfileMusicPresence? {
        let rows: [ProfileMusicPresence] = try await client.rpc("profile_music_presence", params: ProfileIDInput(pProfileId: profileID)).execute().value
        return rows.first
    }

    func updateProfileMusicPresence(track: Track, artworkPath: String?, positionSeconds: Int, durationSeconds: Int, isPlaying: Bool) async throws {
        let input = PresenceInput(pTrackId: track.id, pTitle: track.title, pArtistName: track.artistName,
                                  pAlbumName: track.albumName, pArtworkPath: artworkPath ?? track.artworkPath,
                                  pPositionSeconds: positionSeconds, pDurationSeconds: durationSeconds, pIsPlaying: isPlaying)
        try await client.rpc("upsert_profile_music_presence", params: input).execute()
    }

    func fetchPublicCardOffers() async throws -> [CardPublicOffer] {
        try await client.rpc("card_public_offer_feed").execute().value
    }

    func togglePublicCardOffer(instanceID: UUID, askingCoins: Int, note: String?) async throws -> CardRewardResult {
        try await client.rpc("toggle_public_card_offer", params: PublicOfferInput(pInstanceId: instanceID, pAskingCoins: askingCoins, pNote: note)).execute().value
    }

    func recordNowPlayingShare(trackID: UUID) async throws -> CardRewardResult {
        try await client.rpc("record_now_playing_share", params: TrackIDInput(pTrackId: trackID)).execute().value
    }

    func syncCollectibleCatalog(artistName: String) async throws -> CardRewardResult {
        do {
            return try await client.functions.invoke(
                "sync-card-catalog",
                options: FunctionInvokeOptions(
                    body: ExternalCardCatalogInput(artistName: artistName),
                    timeoutInterval: 120
                )
            )
        } catch FunctionsError.httpError(_, let data) {
            let detail = try? JSONDecoder().decode(ExternalCardCatalogError.self, from: data).error
            throw YePlyError.message(detail ?? "Não foi possível sincronizar a discografia oficial.")
        }
    }

    func refreshCardRarities() async throws -> CardRewardResult {
        try await client.rpc("refresh_card_rarities").execute().value
    }

    private func signedURL(bucket: String, path: String) async throws -> URL {
        let key = "\(bucket):\(path)"
        if let cached = signedURLCache[key], cached.expiresAt > Date().addingTimeInterval(30) { return cached.url }
        let lifetime = bucket == "audio" ? 600 : 3_600
        let url = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: lifetime)
        signedURLCache[key] = (url, Date().addingTimeInterval(TimeInterval(lifetime - 30)))
        return url
    }

}
