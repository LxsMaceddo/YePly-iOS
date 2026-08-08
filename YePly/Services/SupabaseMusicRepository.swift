import Foundation
import Supabase

private struct ShareTokenInput: Encodable { let pToken: UUID; enum CodingKeys: String, CodingKey { case pToken = "p_token" } }
private struct LibraryInput: Encodable { let pScope: String; enum CodingKeys: String, CodingKey { case pScope = "p_scope" } }
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
        try await client.rpc("library_playlists", params: LibraryInput(pScope: scope.rawValue)).execute().value
    }

    func fetchPlaylist(id: UUID) async throws -> Playlist {
        try await client.from("playlists").select().eq("id", value: id).single().execute().value
    }

    func fetchTracks(playlistID: UUID) async throws -> [Track] {
        try await client.from("tracks").select().eq("playlist_id", value: playlistID).order("position", ascending: true).execute().value
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
            let record = NewTrack(id: trackID, playlistId: playlist.id, uploaderId: uploaderID, title: upload.title, artistName: upload.artistName, albumName: upload.albumName, durationSeconds: upload.duration, audioPath: objectPath, artworkPath: nil, position: position, fileSizeBytes: upload.fileSize)
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

    private func signedURL(bucket: String, path: String) async throws -> URL {
        let key = "\(bucket):\(path)"
        if let cached = signedURLCache[key], cached.expiresAt > Date().addingTimeInterval(30) { return cached.url }
        let url = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 600)
        signedURLCache[key] = (url, Date().addingTimeInterval(570))
        return url
    }
}
