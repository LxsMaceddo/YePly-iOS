import Foundation

extension Error {
    var isYePlyCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return message == "cancelled" || message == "canceled" || message == "cancelado"
    }
}

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
    var bio: String?
    var tastes: [String]?
    var role: UserRole
    var createdAt: Date?
    var followerCount: Int? = nil
    var followingCount: Int? = nil
    var isFollowed: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case bio
        case tastes
        case role
        case createdAt = "created_at"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowed = "is_followed"
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
    var viewCount: Int? = nil
    var followerCount: Int? = nil
    var isFollowed: Bool? = nil

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
        case viewCount = "view_count"
        case followerCount = "follower_count"
        case isFollowed = "is_followed"
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
    var waveformSamples: [Double]? = nil
    var likeCount: Int? = nil
    var commentCount: Int? = nil
    var isLiked: Bool? = nil

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
        case waveformSamples = "waveform_samples"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
    }

    var formattedDuration: String {
        let seconds = max(0, Int(durationSeconds.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ArtistSummary: Codable, Identifiable, Hashable, Sendable {
    let artistKey: String
    let artistName: String
    let playlistCount: Int
    let trackCount: Int
    var followerCount: Int
    var isFollowed: Bool
    var isVerified: Bool = false

    var id: String { artistKey }

    enum CodingKeys: String, CodingKey {
        case artistKey = "artist_key"
        case artistName = "artist_name"
        case playlistCount = "playlist_count"
        case trackCount = "track_count"
        case followerCount = "follower_count"
        case isFollowed = "is_followed"
        case isVerified = "is_verified"
    }
}

struct TrackComment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let trackId: UUID
    let userId: UUID
    let body: String
    let timestampSeconds: Double?
    let createdAt: Date
    let updatedAt: Date
    let displayName: String
    let username: String
    let avatarPath: String?
    var likeCount: Int
    var isLiked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case trackId = "track_id"
        case userId = "user_id"
        case body
        case timestampSeconds = "timestamp_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case displayName = "display_name"
        case username
        case avatarPath = "avatar_path"
        case likeCount = "like_count"
        case isLiked = "is_liked"
    }
}

struct TrackSocialSummary: Codable, Sendable {
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool

    enum CodingKeys: String, CodingKey {
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
    }
}

struct NewTrackComment: Encodable, Sendable {
    let trackId: UUID
    let userId: UUID
    let body: String
    let timestampSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case userId = "user_id"
        case body
        case timestampSeconds = "timestamp_seconds"
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
    let waveformSamples: [Double]?

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
        case waveformSamples = "waveform_samples"
    }
}

struct PlaybackHistoryItem: Codable, Identifiable, Hashable, Sendable {
    let trackId: UUID
    let playlistId: UUID
    let uploaderId: UUID
    let title: String
    let artistName: String
    let albumName: String?
    let durationSeconds: Double
    let audioPath: String
    let artworkPath: String?
    let position: Int
    let fileSizeBytes: Int64?
    let trackCreatedAt: Date?
    let waveformSamples: [Double]?
    let playlistTitle: String
    let playlistCoverPath: String?
    let lastPlayedAt: Date
    let playCount: Int

    var id: UUID { trackId }
    var track: Track {
        Track(
            id: trackId, playlistId: playlistId, uploaderId: uploaderId, title: title,
            artistName: artistName, albumName: albumName, durationSeconds: durationSeconds,
            audioPath: audioPath, artworkPath: artworkPath, position: position,
            fileSizeBytes: fileSizeBytes, createdAt: trackCreatedAt, waveformSamples: waveformSamples
        )
    }

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
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
        case trackCreatedAt = "track_created_at"
        case waveformSamples = "waveform_samples"
        case playlistTitle = "playlist_title"
        case playlistCoverPath = "playlist_cover_path"
        case lastPlayedAt = "last_played_at"
        case playCount = "play_count"
    }
}

enum SocialNotificationKind: String, Codable, Sendable {
    case newFollower = "new_follower"
    case playlistFollow = "playlist_follow"
    case trackLike = "track_like"
    case trackComment = "track_comment"
}

struct SocialNotification: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: SocialNotificationKind
    let actorId: UUID
    let actorDisplayName: String
    let actorUsername: String
    let actorAvatarPath: String?
    let playlistId: UUID?
    let playlistTitle: String?
    let trackId: UUID?
    let trackTitle: String?
    let commentId: UUID?
    let createdAt: Date
    let readAt: Date?

    var isUnread: Bool { readAt == nil }
    var message: String {
        switch kind {
        case .newFollower: "começou a seguir você"
        case .playlistFollow: "seguiu a playlist \(playlistTitle ?? "")"
        case .trackLike: "curtiu \(trackTitle ?? "sua música")"
        case .trackComment: "comentou em \(trackTitle ?? "sua música")"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case actorId = "actor_id"
        case actorDisplayName = "actor_display_name"
        case actorUsername = "actor_username"
        case actorAvatarPath = "actor_avatar_path"
        case playlistId = "playlist_id"
        case playlistTitle = "playlist_title"
        case trackId = "track_id"
        case trackTitle = "track_title"
        case commentId = "comment_id"
        case createdAt = "created_at"
        case readAt = "read_at"
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
