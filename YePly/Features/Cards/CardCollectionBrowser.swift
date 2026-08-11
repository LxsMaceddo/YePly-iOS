import SwiftUI

enum CardCollectionSort: String, CaseIterable, Identifiable {
    case acquiredAt
    case title
    case artist
    case album
    case rarity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acquiredAt: "Data"
        case .title: "Música"
        case .artist: "Artista"
        case .album: "Álbum"
        case .rarity: "Raridade"
        }
    }

    var symbolName: String {
        switch self {
        case .acquiredAt: "calendar"
        case .title: "textformat"
        case .artist: "music.mic"
        case .album: "square.stack.fill"
        case .rarity: "sparkles"
        }
    }
}

/// A one-card-per-row collection browser with search, rarity filtering and
/// deterministic sorting. It intentionally owns no navigation or persistence.
struct CardCollectionBrowser: View {
    let cards: [CollectibleCardItem]
    let onSelect: (CollectibleCardItem) -> Void

    @State private var query = ""
    @State private var sort: CardCollectionSort = .acquiredAt
    @State private var ascending = false
    @State private var selectedRarity: CollectibleCardRarity?

    init(cards: [CollectibleCardItem], onSelect: @escaping (CollectibleCardItem) -> Void) {
        self.cards = cards
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            collectionHeader
            searchAndSort
            rarityFilters

            if filteredCards.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Nenhuma carta nesta categoria" : "Nenhuma carta encontrada",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text(query.isEmpty ? "Abra packs para aumentar sua coleção." : "Tente outro nome, artista ou álbum.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredCards) { card in
                        Button { onSelect(card) } label: {
                            CardCollectionBrowserRow(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.24), value: sort)
        .animation(.snappy(duration: 0.24), value: ascending)
        .animation(.snappy(duration: 0.24), value: selectedRarity)
    }

    private var collectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ARQUIVO DE CARTAS")
                    .font(.caption2.bold())
                    .tracking(1.7)
                    .foregroundStyle(YePlyTheme.accent)
                Text("Todas em um só lugar")
                    .font(.title3.bold())
            }

            Spacer()

            Text("\(filteredCards.count)")
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(YePlyTheme.elevatedStrong, in: Capsule())
                .contentTransition(.numericText())
        }
    }

    private var searchAndSort: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(YePlyTheme.tertiary)
                TextField("Música, artista ou álbum", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(YePlyTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            Menu {
                Picker("Ordenar por", selection: $sort) {
                    ForEach(CardCollectionSort.allCases) { option in
                        Label(option.title, systemImage: option.symbolName).tag(option)
                    }
                }
            } label: {
                Image(systemName: sort.symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .accessibilityLabel("Ordenar por \(sort.title)")

            Button { ascending.toggle() } label: {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(YePlyTheme.accent)
                    .frame(width: 38, height: 46)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ascending ? "Ordem crescente" : "Ordem decrescente")
        }
    }

    private var rarityFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                rarityChip(title: "Todas", rarity: nil, count: cards.count)
                ForEach(availableRarities) { rarity in
                    rarityChip(
                        title: rarity.title,
                        rarity: rarity,
                        count: cards.lazy.filter { $0.rarity == rarity }.count
                    )
                }
            }
        }
    }

    private func rarityChip(title: String, rarity: CollectibleCardRarity?, count: Int) -> some View {
        let isSelected = selectedRarity == rarity
        return Button { selectedRarity = rarity } label: {
            HStack(spacing: 6) {
                if let rarity {
                    Image(systemName: rarity.symbolName)
                        .font(.caption2.bold())
                }
                Text(title).font(.caption.bold())
                Text("\(count)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(isSelected ? .white.opacity(0.72) : YePlyTheme.tertiary)
            }
            .foregroundStyle(isSelected ? .white : (rarity?.accentColor ?? YePlyTheme.secondary))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                isSelected ? (rarity?.accentColor ?? YePlyTheme.accent) : YePlyTheme.elevated,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var availableRarities: [CollectibleCardRarity] {
        let present = Set(cards.map(\.rarity))
        return CollectibleCardRarity.allCases.filter(present.contains)
    }

    private var filteredCards: [CollectibleCardItem] {
        let needle = normalized(query)
        return cards
            .filter { card in
                let matchesRarity = selectedRarity.map { card.rarity == $0 } ?? true
                let matchesQuery = needle.isEmpty || [card.title, card.artistName, card.albumName]
                    .contains { normalized($0).contains(needle) }
                return matchesRarity && matchesQuery
            }
            .sorted(by: compare)
    }

    private func compare(_ lhs: CollectibleCardItem, _ rhs: CollectibleCardItem) -> Bool {
        let result: ComparisonResult
        switch sort {
        case .acquiredAt:
            result = (lhs.acquiredAt ?? .distantPast).compare(rhs.acquiredAt ?? .distantPast)
        case .title:
            result = localizedCompare(lhs.title, rhs.title)
        case .artist:
            result = localizedCompare(lhs.artistName, rhs.artistName, fallback: (lhs.albumName, rhs.albumName))
        case .album:
            result = localizedCompare(lhs.albumName, rhs.albumName, fallback: (lhs.title, rhs.title))
        case .rarity:
            result = rarityRank(lhs.rarity) == rarityRank(rhs.rarity)
                ? localizedCompare(lhs.title, rhs.title)
                : (rarityRank(lhs.rarity) < rarityRank(rhs.rarity) ? .orderedAscending : .orderedDescending)
        }

        if result == .orderedSame { return lhs.serialNumber < rhs.serialNumber }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private func localizedCompare(
        _ lhs: String,
        _ rhs: String,
        fallback: (String, String)? = nil
    ) -> ComparisonResult {
        let comparison = lhs.localizedStandardCompare(rhs)
        guard comparison == .orderedSame, let fallback else { return comparison }
        return fallback.0.localizedStandardCompare(fallback.1)
    }

    private func rarityRank(_ rarity: CollectibleCardRarity) -> Int {
        switch rarity.rawValue {
        case "mythic": 3
        case "legendary", "epic": 2
        default: 1
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct CardCollectionBrowserRow: View {
    let card: CollectibleCardItem

    var body: some View {
        HStack(spacing: 13) {
            CardBrowserArtwork(
                path: card.artworkPath,
                seed: card.definitionId.uuidString,
                title: card.title,
                albumName: card.albumName,
                tint: card.rarity.accentColor,
                cornerRadius: 14
            )
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(card.artistName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(YePlyTheme.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(card.rarity.title, systemImage: card.rarity.symbolName)
                        .foregroundStyle(card.rarity.accentColor)
                    Text("•")
                    Text(card.albumName)
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(YePlyTheme.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 11) {
                Text("#\(card.serialNumber)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(YePlyTheme.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(YePlyTheme.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(YePlyTheme.elevated)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(card.rarity.accentColor)
                        .frame(width: 3, height: 48)
                        .padding(.leading, 1)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title), \(card.artistName), \(card.albumName), raridade \(card.rarity.title)")
    }
}
