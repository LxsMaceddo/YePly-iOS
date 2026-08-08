import Foundation

struct TrackUpload: Sendable {
    let fileURL: URL
    let title: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let fileSize: Int64
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
    func searchPlaylists(query: String) async throws -> [Playlist]
    func togglePlaylistFollow(playlistID: UUID) async throws -> Bool
    func recordPlaylistView(playlistID: UUID) async throws -> Int
    func toggleTrackLike(trackID: UUID) async throws -> Bool
    func fetchTrackComments(trackID: UUID) async throws -> [TrackComment]
    func addTrackComment(trackID: UUID, userID: UUID, body: String) async throws
    func deleteTrackComment(commentID: UUID) async throws
    func toggleCommentLike(commentID: UUID) async throws -> Bool
    func fetchTrackSocialSummary(trackID: UUID) async throws -> TrackSocialSummary
}

actor DemoMusicRepository: MusicRepository {
    private var playlists: [Playlist]
    private var tracksByPlaylist: [UUID: [Track]]
    private var followedPlaylists: Set<UUID> = []
    private var followedArtists: Set<String> = []
    private var likedTracks: Set<UUID> = []
    private var commentsByTrack: [UUID: [TrackComment]] = [:]
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
        let track = Track(id: UUID(), playlistId: playlist.id, uploaderId: uploaderID, title: upload.title, artistName: upload.artistName, albumName: upload.albumName, durationSeconds: upload.duration, audioPath: upload.fileURL.lastPathComponent, artworkPath: nil, position: position, fileSizeBytes: upload.fileSize, createdAt: .now)
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
        let names = Set(playlists.map(\.artistName))
        return names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.sorted().map { name in
            let key = name.lowercased()
            return ArtistSummary(artistKey: key, artistName: name, playlistCount: playlists.filter { $0.artistName == name }.count, trackCount: tracksByPlaylist.values.flatMap { $0 }.filter { $0.artistName == name }.count, followerCount: followedArtists.contains(key) ? 1 : 0, isFollowed: followedArtists.contains(key))
        }
    }

    func fetchArtistPlaylists(artistKey: String) async throws -> [Playlist] { playlists.filter { $0.artistName.lowercased() == artistKey } }

    func toggleArtistFollow(artistName: String) async throws -> Bool {
        let key = artistName.lowercased()
        if followedArtists.contains(key) { followedArtists.remove(key); return false }
        followedArtists.insert(key); return true
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

    func addTrackComment(trackID: UUID, userID: UUID, body: String) async throws {
        let comment = TrackComment(id: UUID(), trackId: trackID, userId: userID, body: body, createdAt: .now, updatedAt: .now, displayName: "Vitor", username: "vitor", avatarPath: nil, likeCount: 0, isLiked: false)
        commentsByTrack[trackID, default: []].append(comment)
    }

    func deleteTrackComment(commentID: UUID) async throws {
        for key in Array(commentsByTrack.keys) { commentsByTrack[key]?.removeAll { $0.id == commentID } }
    }

    func toggleCommentLike(commentID: UUID) async throws -> Bool { true }

    func fetchTrackSocialSummary(trackID: UUID) async throws -> TrackSocialSummary {
        TrackSocialSummary(likeCount: likedTracks.contains(trackID) ? 1 : 0, commentCount: commentsByTrack[trackID]?.count ?? 0, isLiked: likedTracks.contains(trackID))
    }
}
