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
    func signedCoverURL(path: String) async throws -> URL { try await signedURL(bucket: "covers", path: path) }
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

    func clearPlaybackHistory() async throws {
        try await client.rpc("clear_playback_history").execute()
    }

    func fetchNotifications() async throws -> [SocialNotification] {
        try await client.rpc("notifications_feed", params: ["p_limit": 60]).execute().value
    }

    func markAllNotificationsRead() async throws {
        try await client.rpc("mark_all_notifications_read").execute()
    }

    private func signedURL(bucket: String, path: String) async throws -> URL {
        let key = "\(bucket):\(path)"
        if let cached = signedURLCache[key], cached.expiresAt > Date().addingTimeInterval(30) { return cached.url }
        let url = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 600)
        signedURLCache[key] = (url, Date().addingTimeInterval(570))
        return url
    }
}
