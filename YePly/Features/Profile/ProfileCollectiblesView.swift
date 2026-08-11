import SwiftUI

private enum ProfileCollectiblesSection: String, CaseIterable, Identifiable, Sendable {
    case badges = "Badges"
    case achievements = "Conquistas"
    case featured = "Destaque"
    var id: String { rawValue }
}

@MainActor
private final class ProfileCollectiblesModel: ObservableObject {
    @Published var badges: [ProfileCollectibleBadge] = []
    @Published var achievements: [CardAchievement] = []
    @Published var inventory: [CollectibleCardItem] = []
    @Published var featuredCard: CollectibleCardItem?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(profileID: UUID, repository: any MusicRepository, includeInventory: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        async let badgeRequest = repository.fetchOwnedProfileBadges(profileID: profileID)
        async let achievementRequest = repository.fetchCardAchievements()
        async let featuredRequest = repository.fetchFeaturedProfileCard(profileID: profileID)
        let loadedBadges = try? await badgeRequest
        let loadedAchievements = try? await achievementRequest
        let loadedFeatured = try? await featuredRequest

        if let loadedBadges { badges = loadedBadges }
        if let loadedAchievements { achievements = loadedAchievements }
        featuredCard = loadedFeatured

        if includeInventory, inventory.isEmpty {
            do { inventory = try await repository.fetchCardInventory() }
            catch let error where error.isYePlyCancellation { return }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func equip(_ badge: ProfileCollectibleBadge, slot: Int, profileID: UUID, repository: any MusicRepository) async {
        do {
            _ = try await repository.equipCardBadge(id: badge.badgeId, slot: slot)
            badges = try await repository.fetchOwnedProfileBadges(profileID: profileID)
        } catch { errorMessage = error.localizedDescription }
    }

    func setFeatured(_ card: CollectibleCardItem?, repository: any MusicRepository) async {
        do {
            _ = try await repository.setFeaturedProfileCard(instanceID: card?.instanceId)
            featuredCard = card
        } catch { errorMessage = error.localizedDescription }
    }
}

/// Unified profile customisation for album, achievement and discography badges,
/// plus an owned card selected as the profile's featured song.
struct ProfileCollectiblesView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = ProfileCollectiblesModel()
    @State private var section: ProfileCollectiblesSection = .badges
    @State private var showingCardPicker = false

    private var profileID: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overview
                Picker("Seção", selection: $section) {
                    ForEach(ProfileCollectiblesSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch section {
                case .badges: badgesContent
                case .achievements: achievementsContent
                case .featured: featuredContent
                }
            }
            .padding(18)
            .padding(.bottom, 70)
        }
        .navigationTitle("Perfil colecionável")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(isPresented: $showingCardPicker) {
            FeaturedCardPicker(
                cards: model.inventory,
                selectedID: model.featuredCard?.instanceId,
                onSelect: { card in
                    showingCardPicker = false
                    Task { await model.setFeatured(card, repository: container.repository) }
                }
            )
        }
        .alert("Perfil", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .overlay { if model.isLoading && model.badges.isEmpty && model.achievements.isEmpty { ProgressView() } }
        .yeplyBackground()
    }

    private var overview: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [YePlyTheme.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("🏅").font(.title)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sua vitrine").font(.title3.bold())
                Text("\(model.badges.count) badges liberadas · 4 espaços no perfil")
                    .font(.caption).foregroundStyle(YePlyTheme.secondary)
            }
            Spacer()
        }
        .padding(15)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var badgesContent: some View {
        if model.badges.isEmpty {
            ContentUnavailableView("Nenhuma badge ainda", systemImage: "seal", description: Text("Complete álbuns, discografias e conquistas para liberar badges."))
                .frame(maxWidth: .infinity).padding(.top, 30)
        } else {
            ForEach(ProfileBadgeKind.allCases, id: \.self) { kind in
                let items = model.badges.filter { $0.kind == kind }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(kind.label.uppercased()).font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.accent)
                        ForEach(items) { badge in
                            ProfileCollectibleBadgeRow(badge: badge) { slot in
                                guard let profileID else { return }
                                Task { await model.equip(badge, slot: slot, profileID: profileID, repository: container.repository) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var achievementsContent: some View {
        if model.achievements.isEmpty {
            ContentUnavailableView("Conquistas indisponíveis", systemImage: "trophy", description: Text("Puxe para atualizar."))
        } else {
            ForEach(achievementCategories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(categoryEmoji(category)) \(category.uppercased())").font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.accent)
                    ForEach(model.achievements.filter { $0.categoryTitle == category }) { achievement in
                        ProfileAchievementRow(achievement: achievement)
                    }
                }
            }
        }
    }

    private var featuredContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MÚSICA EM DESTAQUE").font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.accent)
            if let card = model.featuredCard {
                ProfileFeaturedCardPanel(card: card)
                Button(role: .destructive) {
                    Task { await model.setFeatured(nil, repository: container.repository) }
                } label: { Label("Remover destaque", systemImage: "xmark.circle") }
            } else {
                ContentUnavailableView("Escolha uma música", systemImage: "music.note", description: Text("Você pode destacar qualquer música cuja carta esteja na sua coleção."))
            }
            Button {
                Task {
                    guard let profileID else { return }
                    await model.load(profileID: profileID, repository: container.repository, includeInventory: true)
                    showingCardPicker = true
                }
            } label: {
                Label(model.featuredCard == nil ? "Escolher da coleção" : "Trocar música", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
        }
    }

    private var achievementCategories: [String] {
        let preferred = ["Jornada", "Audição", "Coleção", "Packs", "Trocas", "Comunidade"]
        let available = Set(model.achievements.map(\.categoryTitle))
        return preferred.filter(available.contains) + available.filter { !preferred.contains($0) }.sorted()
    }

    private func categoryEmoji(_ category: String) -> String {
        switch category {
        case "Jornada": "🔥"
        case "Audição": "🎧"
        case "Coleção": "💿"
        case "Packs": "📦"
        case "Trocas": "🤝"
        case "Comunidade": "🌐"
        default: "🏅"
        }
    }

    private func reload() async {
        guard let profileID else { return }
        await model.load(profileID: profileID, repository: container.repository)
    }
}

private struct ProfileCollectibleBadgeRow: View {
    let badge: ProfileCollectibleBadge
    let onEquip: (Int) -> Void

    var body: some View {
        HStack(spacing: 13) {
            ProfileBadgeArtwork(kind: badge.kind, artworkPath: badge.artworkPath, emoji: badge.emoji, seed: badge.badgeId.uuidString, title: badge.title, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title).font(.subheadline.bold()).lineLimit(1)
                Text(badge.subtitle ?? badge.kind.label).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(1...4, id: \.self) { slot in Button("Espaço \(slot)") { onEquip(slot) } }
            } label: {
                Text(badge.slot.map { "Posição \($0)" } ?? "Equipar").font(.caption.bold())
                    .padding(.horizontal, 10).frame(height: 34).background(YePlyTheme.elevatedStrong, in: Capsule())
            }
        }
        .padding(13).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct ProfileAchievementRow: View {
    let achievement: CardAchievement
    var body: some View {
        HStack(spacing: 12) {
            Text(achievement.displayEmoji).font(.title2).frame(width: 42, height: 42).background(YePlyTheme.elevatedStrong, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(achievement.title).font(.subheadline.bold()); Spacer(); Text("\(min(achievement.progress, achievement.target))/\(achievement.target)").font(.caption2).foregroundStyle(YePlyTheme.tertiary) }
                Text(achievement.description).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(2)
                ProgressView(value: achievement.completion).tint(achievement.isUnlocked ? .green : YePlyTheme.accent)
            }
        }
        .padding(13).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
        .opacity(achievement.isUnlocked ? 1 : 0.72)
    }
}

struct ProfileBadgeArtwork: View {
    let kind: ProfileBadgeKind
    let artworkPath: String?
    let emoji: String?
    let seed: String
    let title: String
    let size: CGFloat

    var body: some View {
        Group {
            if kind != .achievement, artworkPath != nil {
                CardBrowserArtwork(path: artworkPath, seed: seed, title: title, tint: YePlyTheme.accent, cornerRadius: size / 2)
            } else if kind == .achievement, title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == "day one" {
                TimelineView(.animation) { context in
                    let rotation = Angle.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) * 45)
                    ZStack {
                        Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center, angle: rotation))
                        Circle().fill(.black.opacity(0.28)).padding(4)
                        Text(emoji ?? "🗿").font(.system(size: size * 0.46))
                    }
                }
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: kind == .discography ? [Color.orange, YePlyTheme.accentSoft] : [YePlyTheme.accentSoft, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(emoji ?? (kind == .discography ? "👑" : "🏅")).font(.system(size: size * 0.46))
                }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1.5))
    }
}

struct ProfileFeaturedCardPanel: View {
    let card: CollectibleCardItem
    var body: some View {
        HStack(spacing: 14) {
            CardBrowserArtwork(path: card.artworkPath, seed: card.definitionId.uuidString, title: card.title, tint: card.rarity.accentColor, cornerRadius: 14)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("EM DESTAQUE").font(.caption2.bold()).tracking(1.4).foregroundStyle(card.rarity.accentColor)
                Text(card.title).font(.headline).lineLimit(1)
                Text(card.artistName).font(.subheadline).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                Text("\(card.rarity.title) · \(card.albumName)").font(.caption2).foregroundStyle(YePlyTheme.tertiary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "music.note").foregroundStyle(card.rarity.accentColor)
        }
        .padding(14).background(card.rarity.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(card.rarity.accentColor.opacity(0.35)))
    }
}

private struct FeaturedCardPicker: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [CollectibleCardItem]
    let selectedID: UUID?
    let onSelect: (CollectibleCardItem) -> Void
    @State private var query = ""

    private var filtered: [CollectibleCardItem] {
        let unique = Dictionary(grouping: cards, by: \.definitionId).compactMap { $0.value.first }
        guard !query.isEmpty else { return unique.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
        return unique.filter { "\($0.title) \($0.artistName) \($0.albumName)".localizedCaseInsensitiveContains(query) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { card in
                Button { onSelect(card) } label: {
                    HStack(spacing: 12) {
                        CardBrowserArtwork(path: card.artworkPath, seed: card.definitionId.uuidString, title: card.title, tint: card.rarity.accentColor, cornerRadius: 10).frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                            Text("\(card.artistName) · \(card.albumName)").font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                        }
                        Spacer()
                        if selectedID == card.instanceId { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
                .buttonStyle(.plain).listRowBackground(YePlyTheme.elevated)
            }
            .searchable(text: $query, prompt: "Música, artista ou álbum")
            .scrollContentBackground(.hidden).background(YePlyTheme.background)
            .navigationTitle("Música em destaque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
