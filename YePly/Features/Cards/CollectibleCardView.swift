import Foundation
import SwiftUI

/// The three visual rarity tiers used by YePly collectible cards.
///
/// `rare` and `legendary` remain decodable only so cards created by older
/// versions keep working; the interface folds them into Common and Epic.
public enum CollectibleCardRarity: String, CaseIterable, Codable, Identifiable, Sendable {
    case common
    case rare
    case epic
    case legendary
    case mythic

    public static let allCases: [CollectibleCardRarity] = [.common, .epic, .mythic]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .common, .rare: "Comum"
        case .epic, .legendary: "Épica"
        case .mythic: "Mítica"
        }
    }

    public var symbolName: String {
        switch self {
        case .common, .rare: "circle.fill"
        case .epic, .legendary: "sparkles"
        case .mythic: "star.fill"
        }
    }

    fileprivate var palette: [Color] {
        switch self {
        case .common, .rare:
            [Color(red: 0.52, green: 0.57, blue: 0.63), Color(red: 0.28, green: 0.32, blue: 0.38)]
        case .epic, .legendary:
            [Color(red: 0.77, green: 0.31, blue: 1.00), Color(red: 0.37, green: 0.18, blue: 0.86)]
        case .mythic:
            [Color(red: 1.00, green: 0.27, blue: 0.50), Color(red: 0.51, green: 0.24, blue: 1.00), Color(red: 0.15, green: 0.79, blue: 0.94)]
        }
    }

    fileprivate var primaryColor: Color { palette[0] }

    public var accentColor: Color { primaryColor }
}

/// Data needed to render a card, deliberately independent from persistence and
/// API models so the component can also be used for unopened-card placeholders.
public struct CollectibleCardDisplayModel: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var artistName: String
    public var albumName: String
    public var genre: String?
    public var rarity: CollectibleCardRarity
    public var serialNumber: Int
    public var artworkURL: URL?
    public var ownerUsername: String?
    public var favoriteCount: Int
    public var isLocked: Bool

    public init(
        id: String,
        title: String,
        artistName: String,
        albumName: String,
        genre: String? = nil,
        rarity: CollectibleCardRarity,
        serialNumber: Int,
        artworkURL: URL? = nil,
        ownerUsername: String? = nil,
        favoriteCount: Int = 0,
        isLocked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.genre = genre
        self.rarity = rarity
        self.serialNumber = serialNumber
        self.artworkURL = artworkURL
        self.ownerUsername = ownerUsername
        self.favoriteCount = favoriteCount
        self.isLocked = isLocked
    }

    fileprivate var formattedSerialNumber: String {
        "#\(String(format: "%04d", max(0, serialNumber)))"
    }
}

public enum CollectibleCardStyle: Equatable, Sendable {
    case compact
    case detailed
}

/// Native YePly collectible card. It contains no third-party brand marks and
/// works with remote artwork or a deterministic, track-specific placeholder.
public struct CollectibleCardView: View {
    public let model: CollectibleCardDisplayModel
    public var style: CollectibleCardStyle
    public var onPlay: (() -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        model: CollectibleCardDisplayModel,
        style: CollectibleCardStyle = .detailed,
        onPlay: (() -> Void)? = nil
    ) {
        self.model = model
        self.style = style
        self.onPlay = onPlay
    }

    public var body: some View {
        switch style {
        case .compact:
            compactCard
        case .detailed:
            detailedCard
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            artwork(cornerRadius: 15)
                .aspectRatio(1, contentMode: .fit)

            rarityLabel(compact: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(model.artistName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(YePlyTheme.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(cardBackground)
        .overlay(cardBorder(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: model.rarity.primaryColor.opacity(reduceTransparency ? 0.08 : 0.22), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var detailedCard: some View {
        ZStack {
            artwork(cornerRadius: 30)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: .clear, location: 0.40),
                    .init(color: .black.opacity(0.46), location: 0.63),
                    .init(color: .black.opacity(0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    rarityLabel(compact: false)
                    Spacer()
                    Label("YEPLY", systemImage: "waveform")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(model.formattedSerialNumber)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 130)

                HStack(alignment: .bottom, spacing: 12) {
                    Rectangle()
                        .fill(rarityGradient)
                        .frame(width: 4, height: 62)
                        .clipShape(Capsule())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.title)
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.70)
                        Text(model.artistName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if let onPlay {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 43, height: 43)
                                .background(.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reproduzir \(model.title)")
                    }
                }

                HStack(spacing: 7) {
                    metadataPill(icon: "square.stack.fill", text: model.albumName, tint: .white.opacity(0.82))
                    if let genre = model.genre, !genre.isEmpty {
                        metadataPill(icon: "music.note", text: genre, tint: YePlyTheme.accent)
                    }
                }
                .padding(.top, 13)

                HStack(spacing: 10) {
                    Circle()
                        .fill(rarityGradient)
                        .frame(width: 32, height: 32)
                        .overlay(Text(ownerInitial).font(.caption.bold()).foregroundStyle(.white))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.ownerUsername == nil ? "EDIÇÃO YEPLY" : "COLEÇÃO DE")
                            .font(.system(size: 8, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.44))
                        Text(model.ownerUsername.map { "@\($0)" } ?? "Carta oficial da coleção")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                    }
                    Spacer()
                    Label(model.favoriteCount.formatted(), systemImage: "heart.fill")
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.64))
                    if model.isLocked {
                        Image(systemName: "lock.fill").foregroundStyle(model.rarity.primaryColor)
                    }
                }
                .padding(.top, 14)
            }
            .padding(18)
        }
        .aspectRatio(0.67, contentMode: .fit)
        .background(model.rarity.primaryColor.opacity(0.14))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(rarityGradient, lineWidth: differentiateWithoutColor ? 3 : 1.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: model.rarity.primaryColor.opacity(reduceTransparency ? 0.12 : 0.42), radius: 30, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private func artwork(cornerRadius: CGFloat) -> some View {
        ZStack {
            // The list browser already has the reliable renderer for direct
            // URLs, Supabase paths and album fallbacks. Reuse that exact path
            // here so inspecting/opening a card cannot silently fall back to a
            // different image pipeline than the collection list.
            CardBrowserArtwork(
                path: model.artworkURL?.absoluteString,
                seed: model.id,
                title: model.title,
                albumName: model.albumName,
                tint: model.rarity.primaryColor,
                cornerRadius: cornerRadius
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )

            if model.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: style == .compact ? 18 : 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(style == .compact ? 10 : 14)
                    .background(.black.opacity(0.58))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(rarityGradient, lineWidth: differentiateWithoutColor ? 3 : 1.5)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func rarityLabel(compact: Bool) -> some View {
        Label(model.rarity.title, systemImage: model.rarity.symbolName)
            .font(.system(size: compact ? 10 : 12, weight: .black, design: .rounded))
            .textCase(.uppercase)
            .tracking(compact ? 0.5 : 0.9)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 5 : 7)
            .background(model.rarity.primaryColor.opacity(reduceTransparency ? 0.75 : 0.28))
            .overlay {
                Capsule().stroke(model.rarity.primaryColor.opacity(0.8), lineWidth: 1)
            }
            .clipShape(Capsule())
    }

    private func metadataPill(icon: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(reduceTransparency ? 0.18 : 0.10))
            .clipShape(Capsule())
    }

    private var cardBackground: some View {
        ZStack {
            YePlyTheme.elevated
            RadialGradient(
                colors: [model.rarity.primaryColor.opacity(reduceTransparency ? 0.09 : 0.18), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 320
            )
            LinearGradient(colors: [.white.opacity(0.045), .clear], startPoint: .top, endPoint: .center)
        }
    }

    private func cardBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(rarityGradient, lineWidth: differentiateWithoutColor ? 3 : 1.5)
    }

    private var rarityGradient: LinearGradient {
        LinearGradient(colors: model.rarity.palette, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var ownerInitial: String {
        let value = model.ownerUsername ?? "Y"
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var accessibilityDescription: String {
        var parts = [
            "Carta \(model.rarity.title)",
            model.title,
            "de \(model.artistName)",
            "álbum \(model.albumName)",
            model.formattedSerialNumber
        ]
        if model.isLocked { parts.append("bloqueada para trocas") }
        return parts.joined(separator: ", ")
    }
}

/// Convenience wrapper for two-column collections and horizontal carousels.
public struct CompactCollectibleCardView: View {
    public let model: CollectibleCardDisplayModel

    public init(model: CollectibleCardDisplayModel) {
        self.model = model
    }

    public var body: some View {
        CollectibleCardView(model: model, style: .compact)
    }
}

private struct CardArtworkPlaceholder: View {
    let seed: String
    let rarity: CollectibleCardRarity
    let title: String

    private var rotation: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 19 }) - 9
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: placeholderColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 210, height: 210)
                .blur(radius: 2)
                .offset(x: 90, y: -90)

            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 22)
                .rotationEffect(.degrees(rotation))
                .padding(42)

            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 52, weight: .black))
                Text(monogram)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(2)
            }
            .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var placeholderColors: [Color] {
        let variants: [[Color]] = [
            [rarity.palette[0], Color(red: 0.11, green: 0.07, blue: 0.18)],
            [Color(red: 0.08, green: 0.16, blue: 0.25), rarity.palette.last ?? rarity.palette[0]],
            [Color(red: 0.22, green: 0.08, blue: 0.12), rarity.palette[0]]
        ]
        let index = seed.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % variants.count }
        return variants[index]
    }

    private var monogram: String {
        title
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }
}

#if DEBUG
#Preview("Carta detalhada") {
    ScrollView {
        CollectibleCardView(
            model: CollectibleCardDisplayModel(
                id: "demo-flashing-lights",
                title: "Flashing Lights",
                artistName: "Kanye West",
                albumName: "Graduation",
                genre: "Hip-hop",
                rarity: .epic,
                serialNumber: 42,
                ownerUsername: "LXS",
                favoriteCount: 128
            )
        )
        .frame(maxWidth: 390)
        .padding()
    }
    .yeplyBackground()
}

#Preview("Grade compacta") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
        ForEach(Array(CollectibleCardRarity.allCases.enumerated()), id: \.element) { index, rarity in
            CompactCollectibleCardView(
                model: CollectibleCardDisplayModel(
                    id: "demo-\(rarity.rawValue)",
                    title: ["Stronger", "Heartless", "Runaway", "Power", "Ghost Town"][index],
                    artistName: "Kanye West",
                    albumName: "YePly Collection",
                    rarity: rarity,
                    serialNumber: index + 1
                )
            )
        }
    }
    .padding()
    .yeplyBackground()
}
#endif
