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
}

actor DemoMusicRepository: MusicRepository {
    private var playlists: [Playlist]
    private var tracksByPlaylist: [UUID: [Track]]
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
}
