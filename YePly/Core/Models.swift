import Foundation

enum UserRole: String, Codable, Sendable {
    case listener
    case creator
    case admin
}

struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var username: String
    var avatarPath: String?
    var role: UserRole
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case role
        case createdAt = "created_at"
    }
}

enum PlaylistVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case publicAccess = "public"
    case unlisted
    case privateAccess = "private"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .publicAccess: "Pública"
        case .unlisted: "Somente com link"
        case .privateAccess: "Privada"
        }
    }
    var icon: String {
        switch self {
        case .publicAccess: "globe"
        case .unlisted: "link"
        case .privateAccess: "lock"
        }
    }
}

struct Playlist: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerId: UUID
    var title: String
    var artistName: String
    var summary: String?
    var coverPath: String?
    var visibility: PlaylistVisibility
    var shareToken: UUID
    var isFeatured: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case title
        case artistName = "artist_name"
        case summary
        case coverPath = "cover_path"
        case visibility
        case shareToken = "share_token"
        case isFeatured = "is_featured"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case trackCount = "track_count"
    }
}

struct Track: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let playlistId: UUID
    let uploaderId: UUID
    var title: String
    var artistName: String
    var albumName: String?
    var durationSeconds: Double
    var audioPath: String
    var artworkPath: String?
    var position: Int
    var fileSizeBytes: Int64?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case playlistId = "playlist_id"
        case uploaderId = "uploader_id"
        case title
        case artistName = "artist_name"
        case albumName = "album_name"
        case durationSeconds = "duration_seconds"
        case audioPath = "audio_path"
        case artworkPath = "artwork_path"
        case position
        case fileSizeBytes = "file_size_bytes"
        case createdAt = "created_at"
    }

    var formattedDuration: String {
        let seconds = max(0, Int(durationSeconds.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum LibraryScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case mine
    case shared

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Tudo"
        case .mine: "Minhas"
        case .shared: "Compartilhadas"
        }
    }
}

struct NewPlaylist: Encodable, Sendable {
    let ownerId: UUID
    let title: String
    let artistName: String
    let summary: String?
    let visibility: PlaylistVisibility

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case title
        case artistName = "artist_name"
        case summary
        case visibility
    }
}

struct NewTrack: Encodable, Sendable {
    let id: UUID
    let playlistId: UUID
    let uploaderId: UUID
    let title: String
    let artistName: String
    let albumName: String?
    let durationSeconds: Double
    let audioPath: String
    let artworkPath: String?
    let position: Int
    let fileSizeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case playlistId = "playlist_id"
        case uploaderId = "uploader_id"
        case title
        case artistName = "artist_name"
        case albumName = "album_name"
        case durationSeconds = "duration_seconds"
        case audioPath = "audio_path"
        case artworkPath = "artwork_path"
        case position
        case fileSizeBytes = "file_size_bytes"
    }
}

enum YePlyError: LocalizedError {
    case configurationMissing
    case invalidCredentials
    case accountNeedsConfirmation
    case invalidLink
    case accessDenied
    case unsupportedFile
    case fileTooLarge
    case noActiveUser
    case message(String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing: "O backend ainda não foi configurado."
        case .invalidCredentials: "E-mail ou senha inválidos."
        case .accountNeedsConfirmation: "Confirme seu e-mail antes de entrar."
        case .invalidLink: "Este link do YePly não é válido."
        case .accessDenied: "Você não tem permissão para acessar este conteúdo."
        case .unsupportedFile: "Escolha um arquivo MP3 válido."
        case .fileTooLarge: "O arquivo excede o limite de 200 MB."
        case .noActiveUser: "Entre na sua conta para continuar."
        case .message(let value): value
        }
    }
}
