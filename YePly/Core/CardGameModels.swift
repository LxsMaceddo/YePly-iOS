import Foundation

struct CardGameDashboard: Codable, Hashable, Sendable {
    var xp: Int
    var level: Int
    var nextLevelXP: Int
    var currentStreak: Int
    var bestStreak: Int
    var unopenedPacks: Int
    var totalCards: Int
    var uniqueCards: Int
    var completedAlbums: Int
    var completedTrades: Int
    var favoriteArtists: [String]
    var dailyClaimAvailable: Bool
    var equippedBadges: [EquippedAlbumBadge]? = nil

    var levelProgress: Double {
        let previousThreshold = max(0, (level - 1) * (level - 1) * 500)
        let span = max(nextLevelXP - previousThreshold, 1)
        return min(max(Double(xp - previousThreshold) / Double(span), 0), 1)
    }

    static let empty = CardGameDashboard(
        xp: 0, level: 1, nextLevelXP: 100, currentStreak: 0, bestStreak: 0,
        unopenedPacks: 0, totalCards: 0, uniqueCards: 0, completedAlbums: 0,
        completedTrades: 0, favoriteArtists: [], dailyClaimAvailable: true
    )

    enum CodingKeys: String, CodingKey {
        case xp, level
        case nextLevelXP = "next_level_xp"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case unopenedPacks = "unopened_pack_count"
        case totalCards = "total_cards"
        case uniqueCards = "unique_cards"
        case completedAlbums = "completed_albums"
        case completedTrades = "completed_trades"
        case favoriteArtists = "favorite_artists"
        case dailyClaimAvailable = "daily_claim_available"
        case equippedBadges = "equipped_badges"
    }
}

struct EquippedAlbumBadge: Codable, Identifiable, Hashable, Sendable {
    let badgeId: UUID
    let albumId: UUID
    let title: String
    let artworkPath: String?
    let slot: Int

    var id: UUID { badgeId }

    enum CodingKeys: String, CodingKey {
        case badgeId = "badge_id"
        case albumId = "album_id"
        case title
        case artworkPath = "artwork_path"
        case slot
    }
}

struct CollectibleCardItem: Codable, Identifiable, Hashable, Sendable {
    let instanceId: UUID
    let serialNumber: Int
    let definitionId: UUID
    let trackId: UUID?
    let title: String
    let artistName: String
    let albumName: String
    let artworkPath: String?
    let rarity: CollectibleCardRarity
    let acquiredAt: Date?
    var externalURL: String? = nil
    var catalogSource: String? = nil
    var globalListenCount: Int? = nil
    var globalListenerCount: Int? = nil
    var popularityScore: Double? = nil
    var artistPopularityRank: Int? = nil
    var artistCatalogSize: Int? = nil

    var id: UUID { instanceId }

    enum CodingKeys: String, CodingKey {
        case instanceId = "instance_id"
        case serialNumber = "serial_number"
        case definitionId = "definition_id"
        case trackId = "track_id"
        case title
        case artistName = "artist_name"
        case albumName = "album_name"
        case artworkPath = "artwork_path"
        case rarity
        case acquiredAt = "acquired_at"
        case externalURL = "external_url"
        case catalogSource = "catalog_source"
        case globalListenCount = "global_listen_count"
        case globalListenerCount = "global_listener_count"
        case popularityScore = "popularity_score"
        case artistPopularityRank = "artist_popularity_rank"
        case artistCatalogSize = "artist_catalog_size"
    }
}

struct CardPackSummary: Codable, Identifiable, Hashable, Sendable {
    let packId: UUID
    let source: String
    let cardCount: Int
    let createdAt: Date

    var id: UUID { packId }

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case source
        case cardCount = "card_count"
        case createdAt = "created_at"
    }
}

struct CardAlbumProgress: Codable, Identifiable, Hashable, Sendable {
    let albumId: UUID
    let albumTitle: String
    let artistName: String
    var artistArtworkPath: String? = nil
    var artistSourceURL: String? = nil
    let artworkPath: String?
    var releaseDate: String? = nil
    let ownedUnique: Int
    let totalCards: Int
    let isComplete: Bool
    let badgeId: UUID?
    var badgeEquipped: Bool

    var id: UUID { albumId }
    var progress: Double { totalCards > 0 ? min(Double(ownedUnique) / Double(totalCards), 1) : 0 }

    enum CodingKeys: String, CodingKey {
        case albumId = "album_id"
        case albumTitle = "album_title"
        case artistName = "artist_name"
        case artistArtworkPath = "artist_artwork_path"
        case artistSourceURL = "artist_source_url"
        case artworkPath = "artwork_path"
        case releaseDate = "release_date"
        case ownedUnique = "owned_unique"
        case totalCards = "total_cards"
        case isComplete = "is_complete"
        case badgeId = "badge_id"
        case badgeEquipped = "badge_equipped"
    }
}

/// An enabled card definition in an album, together with the caller's ownership state.
/// This powers the exact list of tracks a collector is still missing.
struct CardAlbumCatalogItem: Codable, Identifiable, Hashable, Sendable {
    let definitionId: UUID
    let albumId: UUID
    let albumTitle: String
    let artistKey: String
    let artistName: String
    let artworkPath: String?
    let discNumber: Int?
    let trackNumber: Int
    let title: String
    let rarity: CollectibleCardRarity
    let ownedCount: Int
    let ownedInstanceId: UUID?

    var id: UUID { definitionId }
    var isOwned: Bool { ownedCount > 0 }

    enum CodingKeys: String, CodingKey {
        case definitionId = "definition_id"
        case albumId = "album_id"
        case albumTitle = "album_title"
        case artistKey = "artist_key"
        case artistName = "artist_name"
        case artworkPath = "artwork_path"
        case discNumber = "disc_number"
        case trackNumber = "track_number"
        case title, rarity
        case ownedCount = "owned_count"
        case ownedInstanceId = "owned_instance_id"
    }
}

struct CardAchievement: Codable, Identifiable, Hashable, Sendable {
    let achievementKey: String
    let title: String
    let description: String
    let icon: String
    let progress: Int
    let target: Int
    let unlockedAt: Date?
    let rewardClaimedAt: Date?

    var id: String { achievementKey }
    var isUnlocked: Bool { unlockedAt != nil || progress >= target }
    var canClaimReward: Bool { isUnlocked && rewardClaimedAt == nil }
    var completion: Double { target > 0 ? min(Double(progress) / Double(target), 1) : 0 }
    var symbolName: String {
        switch achievementKey {
        case "night_listener": "moon.stars.fill"
        case "again": "repeat"
        case "day_one": "figure.wave"
        case "audiophile": "headphones"
        case "collector": "opticaldisc.fill"
        case "trader": "arrow.left.arrow.right"
        case "obsessed": "heart.fill"
        case "show_off": "square.and.arrow.up.fill"
        default: "trophy.fill"
        }
    }

    enum CodingKeys: String, CodingKey {
        case achievementKey = "achievement_key"
        case title, description, icon, progress, target
        case unlockedAt = "unlocked_at"
        case rewardClaimedAt = "reward_claimed_at"
    }
}

struct CardArtistOption: Codable, Identifiable, Hashable, Sendable {
    let artistKey: String
    let artistName: String
    let cardCount: Int
    var id: String { artistKey }

    enum CodingKeys: String, CodingKey {
        case artistKey = "artist_key"
        case artistName = "artist_name"
        case cardCount = "card_count"
    }
}

struct CardRewardResult: Codable, Hashable, Sendable {
    let success: Bool?
    let message: String?
    let packId: UUID?
    let packsAwarded: Int?
    let xpAwarded: Int?
    let streak: Int?
    let achievementKey: String?
    let rewardClaimed: Bool?
    let packDropped: Bool?
    let accepted: Bool?
    let claimed: Bool?
    let redeemed: Bool?

    enum CodingKeys: String, CodingKey {
        case success, message, streak
        case packId = "pack_id"
        case packsAwarded = "packs_awarded"
        case xpAwarded = "xp_awarded"
        case achievementKey = "achievement_key"
        case rewardClaimed = "reward_claimed"
        case packDropped = "pack_dropped"
        case accepted, claimed, redeemed
    }
}

struct CardTradeSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let direction: String
    let counterpartyId: UUID
    let counterpartyUsername: String
    let counterpartyDisplayName: String
    let status: String
    let offeredCardIds: [UUID]
    let requestedCardIds: [UUID]
    let offeredTitles: [String]
    let requestedTitles: [String]
    let createdAt: Date
    let expiresAt: Date
    let respondedAt: Date?

    var canRespond: Bool { direction == "incoming" && status == "pending" }

    enum CodingKeys: String, CodingKey {
        case id = "trade_id"
        case direction, status
        case counterpartyId = "other_user_id"
        case counterpartyUsername = "other_username"
        case counterpartyDisplayName = "other_display_name"
        case offeredCardIds = "offered_instance_ids"
        case requestedCardIds = "requested_instance_ids"
        case offeredTitles = "offered_titles"
        case requestedTitles = "requested_titles"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case respondedAt = "responded_at"
    }
}
