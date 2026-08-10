import SwiftUI

/// Artist-first entry point for album completion. Selecting an artist opens a
/// dedicated album browser; selecting an album reveals owned cards and locked
/// slots for the ones that are still missing.
struct CardAlbumLibraryBrowser: View {
    let albums: [CardAlbumProgress]
    let cards: [CollectibleCardItem]
    let onSelectCard: (CollectibleCardItem) -> Void

    @State private var selectedArtist: CardBrowserArtistGroup?

    init(
        albums: [CardAlbumProgress],
        cards: [CollectibleCardItem],
        onSelectCard: @escaping (CollectibleCardItem) -> Void
    ) {
        self.albums = albums
        self.cards = cards
        self.onSelectCard = onSelectCard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DISCOGRAFIAS")
                        .font(.caption2.bold())
                        .tracking(1.7)
                        .foregroundStyle(YePlyTheme.accent)
                    Text("Colecione por artista")
                        .font(.title3.bold())
                }
                Spacer()
                Label("\(artistGroups.count)", systemImage: "music.mic")
                    .font(.caption.bold())
                    .foregroundStyle(YePlyTheme.secondary)
            }

            if artistGroups.isEmpty {
                ContentUnavailableView(
                    "Nenhuma discografia disponível",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Sincronize um catálogo oficial para começar.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(artistGroups) { artist in
                        Button { selectedArtist = artist } label: {
                            CardArtistLibraryRow(artist: artist, cards: cards)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedArtist) { artist in
            CardArtistAlbumsSheet(
                artist: artist,
                cards: cards,
                onSelectCard: onSelectCard
            )
        }
    }

    private var artistGroups: [CardBrowserArtistGroup] {
        Dictionary(grouping: albums, by: { CardBrowserNormalization.key($0.artistName) })
            .compactMap { key, albums in
                guard let first = albums.first else { return nil }
                return CardBrowserArtistGroup(
                    id: key,
                    name: first.artistName,
                    albums: albums.sorted { $0.albumTitle.localizedStandardCompare($1.albumTitle) == .orderedAscending }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct CardBrowserArtistGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let albums: [CardAlbumProgress]

    var totalCards: Int { albums.reduce(0) { $0 + $1.totalCards } }
    var ownedCards: Int { albums.reduce(0) { $0 + $1.ownedUnique } }
    var completedAlbums: Int { albums.lazy.filter(\.isComplete).count }
    var progress: Double { totalCards > 0 ? min(Double(ownedCards) / Double(totalCards), 1) : 0 }
}

private struct CardArtistLibraryRow: View {
    let artist: CardBrowserArtistGroup
    let cards: [CollectibleCardItem]

    var body: some View {
        HStack(spacing: 14) {
            CardBrowserArtwork(
                path: representativeArtwork,
                seed: artist.id,
                title: artist.name,
                tint: YePlyTheme.accent,
                cornerRadius: 18
            )
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text(artist.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label("\(artist.albums.count) álbuns", systemImage: "square.stack.fill")
                    Label("\(artist.ownedCards)/\(artist.totalCards)", systemImage: "rectangle.stack.fill")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(YePlyTheme.secondary)

                ProgressView(value: artist.progress)
                    .tint(artist.progress >= 1 ? .green : YePlyTheme.accent)
            }

            Spacer(minLength: 4)

            VStack(spacing: 8) {
                if artist.completedAlbums > 0 {
                    Text("\(artist.completedAlbums)")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(.green, in: Circle())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(YePlyTheme.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(YePlyTheme.elevated)
                .overlay {
                    LinearGradient(
                        colors: [YePlyTheme.accent.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artist.name), \(artist.albums.count) álbuns, \(artist.ownedCards) de \(artist.totalCards) cartas")
    }

    private var representativeArtwork: String? {
        let artistKey = CardBrowserNormalization.key(artist.name)
        return artist.albums.lazy.compactMap(\.artworkPath).first
            ?? cards.first { CardBrowserNormalization.key($0.artistName) == artistKey }?.artworkPath
    }
}

private struct CardArtistAlbumsSheet: View {
    let artist: CardBrowserArtistGroup
    let cards: [CollectibleCardItem]
    let onSelectCard: (CollectibleCardItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    artistHero

                    ForEach(artist.albums) { album in
                        NavigationLink {
                            CardAlbumCollectionDetail(
                                album: album,
                                cards: cardsForAlbum(album),
                                onSelectCard: onSelectCard
                            )
                        } label: {
                            CardAlbumLibraryRow(album: album, cards: cardsForAlbum(album))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 38)
            }
            .navigationTitle(artist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
            .yeplyBackground()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var artistHero: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [YePlyTheme.accent, YePlyTheme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.mic")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text("DISCOGRAFIA")
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(YePlyTheme.accent)
                    Text("\(artist.ownedCards) de \(artist.totalCards) cartas únicas")
                        .font(.headline)
                }

                Spacer()

                Text("\(Int((artist.progress * 100).rounded()))%")
                    .font(.title3.monospacedDigit().bold())
            }

            ProgressView(value: artist.progress)
                .tint(artist.progress >= 1 ? .green : YePlyTheme.accent)
        }
        .padding(16)
        .background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cardsForAlbum(_ album: CardAlbumProgress) -> [CollectibleCardItem] {
        let artistKey = CardBrowserNormalization.key(album.artistName)
        let albumKey = CardBrowserNormalization.key(album.albumTitle)
        return cards.filter {
            CardBrowserNormalization.key($0.artistName) == artistKey
                && CardBrowserNormalization.key($0.albumName) == albumKey
        }
    }
}

private struct CardAlbumLibraryRow: View {
    let album: CardAlbumProgress
    let cards: [CollectibleCardItem]

    var body: some View {
        HStack(spacing: 13) {
            CardBrowserArtwork(
                path: album.artworkPath ?? cards.first?.artworkPath,
                seed: album.id.uuidString,
                title: album.albumTitle,
                tint: album.isComplete ? .green : YePlyTheme.accentSoft,
                cornerRadius: 16
            )
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(album.albumTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if album.isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text("\(album.ownedUnique) de \(album.totalCards) músicas")
                    .font(.caption)
                    .foregroundStyle(YePlyTheme.secondary)

                ProgressView(value: album.progress)
                    .tint(album.isComplete ? .green : YePlyTheme.accent)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(YePlyTheme.tertiary)
        }
        .padding(11)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct CardAlbumCollectionDetail: View {
    @Environment(\.dismiss) private var dismiss

    let album: CardAlbumProgress
    let cards: [CollectibleCardItem]
    let onSelectCard: (CollectibleCardItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                albumHeader

                Text("SUAS CARTAS")
                    .font(.caption2.bold())
                    .tracking(1.6)
                    .foregroundStyle(YePlyTheme.tertiary)
                    .padding(.top, 8)

                ForEach(ownedGroups) { group in
                    Button { onSelectCard(group.card) } label: {
                        CardAlbumOwnedTrackRow(group: group)
                    }
                    .buttonStyle(.plain)
                }

                if missingCount > 0 {
                    Text("AINDA FALTAM")
                        .font(.caption2.bold())
                        .tracking(1.6)
                        .foregroundStyle(YePlyTheme.tertiary)
                        .padding(.top, 9)

                    ForEach(0..<missingCount, id: \.self) { index in
                        CardAlbumMissingTrackRow(index: album.ownedUnique + index + 1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .navigationTitle(album.albumTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label("Álbuns", systemImage: "chevron.left")
                }
            }
        }
        .yeplyBackground()
    }

    private var albumHeader: some View {
        HStack(spacing: 15) {
            CardBrowserArtwork(
                path: album.artworkPath ?? cards.first?.artworkPath,
                seed: album.id.uuidString,
                title: album.albumTitle,
                tint: album.isComplete ? .green : YePlyTheme.accentSoft,
                cornerRadius: 20
            )
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 7) {
                Text(album.albumTitle)
                    .font(.title3.bold())
                    .lineLimit(2)
                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(YePlyTheme.secondary)
                Text("\(album.ownedUnique)/\(album.totalCards) completas")
                    .font(.caption.bold())
                    .foregroundStyle(album.isComplete ? .green : YePlyTheme.accent)
                ProgressView(value: album.progress)
                    .tint(album.isComplete ? .green : YePlyTheme.accent)
            }
        }
        .padding(14)
        .background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var ownedGroups: [CardBrowserOwnedGroup] {
        Dictionary(grouping: cards, by: \.definitionId)
            .compactMap { _, copies in
                guard let representative = copies.sorted(by: { $0.serialNumber < $1.serialNumber }).first else { return nil }
                return CardBrowserOwnedGroup(card: representative, copyCount: copies.count)
            }
            .sorted { $0.card.title.localizedStandardCompare($1.card.title) == .orderedAscending }
    }

    private var missingCount: Int {
        max(album.totalCards - album.ownedUnique, 0)
    }
}

private struct CardBrowserOwnedGroup: Identifiable {
    let card: CollectibleCardItem
    let copyCount: Int
    var id: UUID { card.definitionId }
}

private struct CardAlbumOwnedTrackRow: View {
    let group: CardBrowserOwnedGroup

    var body: some View {
        HStack(spacing: 12) {
            CardBrowserArtwork(
                path: group.card.artworkPath,
                seed: group.card.definitionId.uuidString,
                title: group.card.title,
                tint: group.card.rarity.accentColor,
                cornerRadius: 13
            )
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.card.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Label(group.card.rarity.title, systemImage: group.card.rarity.symbolName)
                    .font(.caption2.bold())
                    .foregroundStyle(group.card.rarity.accentColor)
            }

            Spacer()

            if group.copyCount > 1 {
                Text("×\(group.copyCount)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(YePlyTheme.elevatedStrong, in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(YePlyTheme.tertiary)
        }
        .padding(10)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct CardAlbumMissingTrackRow: View {
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(YePlyTheme.elevatedStrong)
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(YePlyTheme.tertiary)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("Carta não encontrada")
                    .font(.subheadline.bold())
                    .foregroundStyle(YePlyTheme.secondary)
                Text("Abra packs ou faça uma troca")
                    .font(.caption2)
                    .foregroundStyle(YePlyTheme.tertiary)
            }

            Spacer()

            Text("#\(index)")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(YePlyTheme.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(YePlyTheme.elevated.opacity(0.66))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(YePlyTheme.line)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Carta ainda não obtida")
    }
}

private enum CardBrowserNormalization {
    static func key(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
