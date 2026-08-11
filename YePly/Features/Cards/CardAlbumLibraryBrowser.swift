import SwiftUI

/// Artist-first entry point for album completion. Selecting an artist opens a
/// dedicated album browser; selecting an album reveals owned cards and locked
/// slots for the ones that are still missing.
struct CardAlbumLibraryBrowser: View {
    let albums: [CardAlbumProgress]
    let cards: [CollectibleCardItem]
    let catalog: [CardAlbumCatalogItem]
    let wishlistDefinitionIDs: Set<UUID>
    let onSelectCard: (CollectibleCardItem) -> Void
    let onToggleWishlist: ((UUID) -> Void)?

    @State private var selectedArtist: CardBrowserArtistGroup?

    init(
        albums: [CardAlbumProgress],
        cards: [CollectibleCardItem],
        catalog: [CardAlbumCatalogItem],
        wishlistDefinitionIDs: Set<UUID> = [],
        onSelectCard: @escaping (CollectibleCardItem) -> Void,
        onToggleWishlist: ((UUID) -> Void)? = nil
    ) {
        self.albums = albums
        self.cards = cards
        self.catalog = catalog
        self.wishlistDefinitionIDs = wishlistDefinitionIDs
        self.onSelectCard = onSelectCard
        self.onToggleWishlist = onToggleWishlist
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
                catalog: catalog,
                wishlistDefinitionIDs: wishlistDefinitionIDs,
                onSelectCard: onSelectCard,
                onToggleWishlist: onToggleWishlist
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
                    artworkPath: first.artistArtworkPath,
                    sourceURL: first.artistSourceURL,
                    albums: albums.sorted(by: chronologicalAlbumOrder)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chronologicalAlbumOrder(_ left: CardAlbumProgress, _ right: CardAlbumProgress) -> Bool {
        switch (left.releaseDate, right.releaseDate) {
        case let (leftDate?, rightDate?) where leftDate != rightDate:
            return leftDate < rightDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return left.albumTitle.localizedStandardCompare(right.albumTitle) == .orderedAscending
        }
    }
}

private struct CardBrowserArtistGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let artworkPath: String?
    let sourceURL: String?
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
                cornerRadius: 38
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
        return artist.artworkPath
            ?? artist.albums.lazy.compactMap(\.artworkPath).first
            ?? cards.first { CardBrowserNormalization.key($0.artistName) == artistKey }?.artworkPath
    }
}

private struct CardArtistAlbumsSheet: View {
    let artist: CardBrowserArtistGroup
    let cards: [CollectibleCardItem]
    let catalog: [CardAlbumCatalogItem]
    let wishlistDefinitionIDs: Set<UUID>
    let onSelectCard: (CollectibleCardItem) -> Void
    let onToggleWishlist: ((UUID) -> Void)?

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
                                catalog: catalogForAlbum(album),
                                wishlistDefinitionIDs: wishlistDefinitionIDs,
                                onSelectCard: onSelectCard,
                                onToggleWishlist: onToggleWishlist
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
                CardBrowserArtwork(
                    path: artist.artworkPath,
                    seed: artist.id,
                    title: artist.name,
                    tint: YePlyTheme.accent,
                    cornerRadius: 27
                )
                .frame(width: 54, height: 54)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("ARQUIVO DO ARTISTA")
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(YePlyTheme.accent)
                    Text("\(artist.albums.count) álbuns · \(artist.ownedCards) de \(artist.totalCards) cartas")
                        .font(.headline)
                        .lineLimit(2)
                }

                Spacer()

                Text("\(Int((artist.progress * 100).rounded()))%")
                    .font(.title3.monospacedDigit().bold())
            }

            ProgressView(value: artist.progress)
                .tint(artist.progress >= 1 ? .green : YePlyTheme.accent)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(YePlyTheme.elevatedStrong)
                .overlay {
                    LinearGradient(colors: [YePlyTheme.accent.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
        }
    }

    private func cardsForAlbum(_ album: CardAlbumProgress) -> [CollectibleCardItem] {
        let definitionIDs = Set(catalogForAlbum(album).map(\.definitionId))
        let byDefinition = cards.filter { definitionIDs.contains($0.definitionId) }
        if !byDefinition.isEmpty { return byDefinition }

        // Artist labels on collaborative tracks can be "Kanye West, Ye" while
        // the album owner is simply "Kanye West". Album identity is stable;
        // comparing the full artist string made owned cards look locked.
        let albumKey = CardBrowserNormalization.key(album.albumTitle)
        return cards.filter {
            CardBrowserNormalization.key($0.albumName) == albumKey
        }
    }

    private func catalogForAlbum(_ album: CardAlbumProgress) -> [CardAlbumCatalogItem] {
        let exact = catalog.filter { $0.albumId == album.albumId }
        let candidates: [CardAlbumCatalogItem]
        if !exact.isEmpty {
            candidates = exact
        } else {
            let albumKey = CardBrowserNormalization.key(album.albumTitle)
            let artistKey = CardBrowserNormalization.key(album.artistName)
            candidates = catalog.filter {
                CardBrowserNormalization.key($0.albumTitle) == albumKey
                    && CardBrowserNormalization.key($0.artistName) == artistKey
            }
        }
        return Array(Dictionary(grouping: candidates, by: \.definitionId).compactMap { $0.value.first })
            .sorted {
                let leftDisc = $0.discNumber ?? 1
                let rightDisc = $1.discNumber ?? 1
                if leftDisc != rightDisc { return leftDisc < rightDisc }
                if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
}

private struct CardAlbumLibraryRow: View {
    let album: CardAlbumProgress
    let cards: [CollectibleCardItem]

    var body: some View {
        HStack(spacing: 15) {
            CardBrowserArtwork(
                path: album.artworkPath ?? cards.first?.artworkPath,
                seed: album.id.uuidString,
                title: album.albumTitle,
                tint: album.isComplete ? .green : YePlyTheme.accentSoft,
                cornerRadius: 18
            )
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                Text(album.albumTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(album.artistName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))

                Text("\(album.ownedUnique)/\(album.totalCards) faixas")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(album.isComplete ? .black : .white.opacity(0.78))
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(album.isComplete ? Color.green : Color.white.opacity(0.09), in: Capsule())

                ProgressView(value: album.progress)
                    .tint(album.isComplete ? .green : YePlyTheme.accent)
            }

            Spacer(minLength: 4)

            if album.isComplete {
                Image(systemName: "checkmark")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(.green, in: Circle())
            } else {
                VStack(spacing: 5) {
                    Text("FALTAM")
                        .font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(YePlyTheme.tertiary)
                    Text("\(max(album.totalCards - album.ownedUnique, 0))")
                        .font(.headline.monospacedDigit().bold()).foregroundStyle(YePlyTheme.accent)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(YePlyTheme.tertiary)
                }
                .frame(width: 44)
            }
        }
        .padding(10)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(album.isComplete ? Color.green.opacity(0.20) : Color.white.opacity(0.055))
        }
        .contentShape(Rectangle())
    }
}

private struct CardAlbumCollectionDetail: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCard: CollectibleCardItem?

    let album: CardAlbumProgress
    let cards: [CollectibleCardItem]
    let catalog: [CardAlbumCatalogItem]
    let wishlistDefinitionIDs: Set<UUID>
    let onSelectCard: (CollectibleCardItem) -> Void
    let onToggleWishlist: ((UUID) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                albumHeader

                HStack(alignment: .firstTextBaseline) {
                    Text("TRACKLIST COMPLETA")
                        .font(.caption2.bold())
                        .tracking(1.6)
                        .foregroundStyle(YePlyTheme.tertiary)
                    Spacer()
                    Text("\(completeTrackRows.count) faixas")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(YePlyTheme.accent)
                }
                .padding(.top, 8)

                if completeTrackRows.isEmpty {
                    Label(
                        "O catálogo deste álbum ainda não retornou as faixas. Atualize a discografia e tente novamente.",
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(YePlyTheme.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                } else {
                    ForEach(completeTrackRows) { row in
                        if let owned = row.owned {
                            Button { selectedCard = owned.card } label: {
                                CardAlbumOwnedTrackRow(group: owned, trackNumber: row.trackNumber)
                            }
                            .buttonStyle(.plain)
                        } else if let catalog = row.catalog {
                            CardAlbumMissingTrackRow(
                                card: catalog,
                                isWishlisted: wishlistDefinitionIDs.contains(catalog.definitionId),
                                onToggleWishlist: onToggleWishlist.map { action in
                                    { action(catalog.definitionId) }
                                }
                            )
                        }
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
        .fullScreenCover(item: $selectedCard) { card in
            NavigationStack { CardDetailSheet(card: card) }
        }
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

    private var completeTrackRows: [CardAlbumCompleteTrackRow] {
        let groups = Dictionary(uniqueKeysWithValues: ownedGroups.map { ($0.card.definitionId, $0) })
        let groupsByTitle = Dictionary(grouping: ownedGroups, by: { CardBrowserNormalization.key($0.card.title) })
        var result = catalog.map { item in
            CardAlbumCompleteTrackRow(
                id: item.definitionId,
                trackNumber: item.trackNumber,
                discNumber: item.discNumber ?? 1,
                catalog: item,
                owned: groups[item.definitionId] ?? groupsByTitle[CardBrowserNormalization.key(item.title)]?.first
            )
        }
        let catalogIDs = Set(catalog.map(\.definitionId))
        result.append(contentsOf: ownedGroups.filter { !catalogIDs.contains($0.card.definitionId) }.map { group in
            CardAlbumCompleteTrackRow(
                id: group.card.definitionId,
                trackNumber: Int.max,
                discNumber: 1,
                catalog: nil,
                owned: group
            )
        })
        return result.sorted {
            if $0.discNumber != $1.discNumber { return $0.discNumber < $1.discNumber }
            if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

private struct CardAlbumCompleteTrackRow: Identifiable {
    let id: UUID
    let trackNumber: Int
    let discNumber: Int
    let catalog: CardAlbumCatalogItem?
    let owned: CardBrowserOwnedGroup?

    var title: String { catalog?.title ?? owned?.card.title ?? "" }
}

private struct CardBrowserOwnedGroup: Identifiable {
    let card: CollectibleCardItem
    let copyCount: Int
    var id: UUID { card.definitionId }
}

private struct CardAlbumOwnedTrackRow: View {
    let group: CardBrowserOwnedGroup
    var trackNumber: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let trackNumber, trackNumber != Int.max {
                Text(trackNumber.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(YePlyTheme.tertiary)
                    .frame(width: 22, alignment: .trailing)
            }
            CardBrowserArtwork(
                path: group.card.artworkPath,
                seed: group.card.definitionId.uuidString,
                title: group.card.title,
                albumName: group.card.albumName,
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
    let card: CardAlbumCatalogItem
    var isWishlisted = false
    var onToggleWishlist: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                CardBrowserArtwork(
                    path: card.artworkPath,
                    seed: card.definitionId.uuidString,
                    title: card.title,
                    albumName: card.albumTitle,
                    tint: card.rarity.accentColor,
                    cornerRadius: 13
                )
                .saturation(0.25)
                .opacity(0.48)

                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.black.opacity(0.28))
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Label(card.rarity.title, systemImage: card.rarity.symbolName)
                    .font(.caption2)
                    .foregroundStyle(card.rarity.accentColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text((card.discNumber ?? 1) > 1 ? "Disco \(card.discNumber ?? 1)" : "Faixa")
                    .font(.caption2)
                    .foregroundStyle(YePlyTheme.tertiary)
                Text("#\(card.trackNumber)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(YePlyTheme.secondary)
            }

            if let onToggleWishlist {
                Button(action: onToggleWishlist) {
                    Image(systemName: isWishlisted ? "heart.fill" : "heart")
                        .font(.subheadline.bold())
                        .foregroundStyle(isWishlisted ? YePlyTheme.accent : YePlyTheme.secondary)
                        .frame(width: 34, height: 34)
                        .background(YePlyTheme.elevatedStrong, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isWishlisted ? "Remover da lista de desejos" : "Adicionar à lista de desejos")
            }
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
        .accessibilityLabel("Carta ainda não obtida: \(card.title), raridade \(card.rarity.title)")
    }
}

private enum CardBrowserNormalization {
    static func key(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
