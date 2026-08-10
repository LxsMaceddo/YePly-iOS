import SwiftUI

private enum CardsHubSection: String, CaseIterable, Identifiable {
    case packs, collection, albums, achievements, trades
    var id: String { rawValue }
    var title: String {
        switch self {
        case .packs: "Packs"
        case .collection: "Coleção"
        case .albums: "Álbuns"
        case .achievements: "Conquistas"
        case .trades: "Trocas"
        }
    }
}

@MainActor
private final class CardsHubViewModel: ObservableObject {
    @Published var dashboard = CardGameDashboard.empty
    @Published var inventory: [CollectibleCardItem] = []
    @Published var packs: [CardPackSummary] = []
    @Published var albums: [CardAlbumProgress] = []
    @Published var achievements: [CardAchievement] = []
    @Published var artists: [CardArtistOption] = []
    @Published var trades: [CardTradeSummary] = []
    @Published var revealedCards: [CollectibleCardItem] = []
    @Published var rewardMessage: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isOpeningPack = false

    func load(repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let dashboard = repository.fetchCardDashboard()
            async let inventory = repository.fetchCardInventory()
            async let packs = repository.fetchCardPacks()
            async let albums = repository.fetchCardAlbumProgress()
            async let achievements = repository.fetchCardAchievements()
            async let artists = repository.fetchCardArtists()
            async let trades = repository.fetchCardTrades()
            self.dashboard = try await dashboard
            self.inventory = try await inventory
            self.packs = try await packs
            self.albums = try await albums
            self.achievements = try await achievements
            self.artists = try await artists
            self.trades = try await trades
            errorMessage = nil
        } catch let error where error.isYePlyCancellation { return }
        catch { errorMessage = error.localizedDescription }
    }

    func claimDaily(repository: any MusicRepository) async {
        guard dashboard.dailyClaimAvailable else { return }
        do {
            let reward = try await repository.claimDailyCardReward()
            rewardMessage = reward.message ?? "Recompensa diária recebida."
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func redeem(code: String, repository: any MusicRepository) async -> Bool {
        do {
            let reward = try await repository.redeemPackCode(code)
            rewardMessage = reward.message ?? "Código resgatado."
            await load(repository: repository)
            return reward.success ?? true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func open(_ pack: CardPackSummary, repository: any MusicRepository) async {
        guard !isOpeningPack else { return }
        isOpeningPack = true
        defer { isOpeningPack = false }
        do {
            revealedCards = try await repository.openCardPack(id: pack.id)
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func equip(_ album: CardAlbumProgress, repository: any MusicRepository) async {
        guard let badgeID = album.badgeId else { return }
        do {
            let reward = try await repository.equipCardBadge(id: badgeID, slot: 1)
            rewardMessage = reward.message ?? "Badge equipada no perfil."
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func claim(_ achievement: CardAchievement, artistKey: String, repository: any MusicRepository) async {
        do {
            let reward = try await repository.claimCardAchievement(key: achievement.achievementKey, artistKey: artistKey)
            rewardMessage = reward.message ?? "Pack especial de cinco cartas recebido."
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func respond(_ trade: CardTradeSummary, accept: Bool, repository: any MusicRepository) async {
        do {
            let reward = try await repository.respondToCardTrade(id: trade.id, accept: accept)
            rewardMessage = reward.message ?? (accept ? "Troca concluída." : "Troca recusada.")
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func syncKanye(repository: any MusicRepository) async {
        do {
            let reward = try await repository.syncCollectibleCatalog(artistName: "Kanye West")
            _ = try await repository.refreshCardRarities()
            rewardMessage = reward.message ?? "Catálogo de Kanye West sincronizado."
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct CardsHubView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var model = CardsHubViewModel()
    @State private var section: CardsHubSection = .packs
    @State private var code = ""
    @State private var selectedCard: CollectibleCardItem?
    @State private var showingFavorites = false
    @State private var showingTradeCreator = false
    @State private var showingPackCodeCreator = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if offlineLibrary.isOfflineMode {
                    ContentUnavailableView("Cartas indisponíveis offline", systemImage: "rectangle.stack.badge.minus", description: Text("Conecte-se para abrir packs, atualizar conquistas e realizar trocas."))
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else if model.isLoading && model.inventory.isEmpty && model.packs.isEmpty {
                    ProgressView("Carregando coleção…").frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    levelCard
                    Picker("Seção", selection: $section) {
                        ForEach(CardsHubSection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    content
                }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 120)
        }
        .navigationBarHidden(true)
        .refreshable { await model.load(repository: container.repository) }
        .task(id: session.userID) {
            guard offlineLibrary.isConnected else { return }
            await model.load(repository: container.repository)
            if model.dashboard.dailyClaimAvailable { await model.claimDaily(repository: container.repository) }
            if model.dashboard.favoriteArtists.isEmpty { showingFavorites = true }
        }
        .sheet(item: $selectedCard) { card in
            NavigationStack { CardDetailSheet(card: card) }
        }
        .sheet(isPresented: $showingFavorites) {
            FavoriteCardArtistsView(onSaved: { Task { await model.load(repository: container.repository) } })
        }
        .sheet(isPresented: $showingTradeCreator) {
            CreateCardTradeView(ownCards: model.inventory, onCreated: { Task { await model.load(repository: container.repository) } })
        }
        .sheet(isPresented: $showingPackCodeCreator) {
            CreatePackCodeView(artists: model.artists) { createdCode in
                model.rewardMessage = "Código \(createdCode) criado e pronto para compartilhar."
            }
        }
        .sheet(isPresented: Binding(get: { !model.revealedCards.isEmpty }, set: { if !$0 { model.revealedCards = [] } })) {
            CardPackRevealView(cards: model.revealedCards) { model.revealedCards = [] }
        }
        .alert("Cartas", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if let message = model.rewardMessage {
                Label(message, systemImage: "gift.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(minHeight: 46)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8).onTapGesture { model.rewardMessage = nil }
                    .task { try? await Task.sleep(for: .seconds(4)); model.rewardMessage = nil }
            }
        }
        .yeplyBackground()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("YEPLY CARDS").font(.caption2.bold()).tracking(2).foregroundStyle(YePlyTheme.tertiary)
                Text("Sua coleção").font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-1)
            }
            Spacer()
            Button { showingFavorites = true } label: {
                Image(systemName: "star.circle.fill").font(.title2).frame(width: 42, height: 42)
                    .background(YePlyTheme.elevated, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Artistas favoritos")
        }
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NÍVEL \(model.dashboard.level)").font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.accent)
                    Text("\(model.dashboard.xp.formatted()) XP").font(.title2.bold())
                }
                Spacer()
                Label("\(model.dashboard.currentStreak) dias", systemImage: "flame.fill")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
            }
            ProgressView(value: model.dashboard.levelProgress).tint(YePlyTheme.accent)
            HStack {
                Label("\(model.dashboard.totalCards) cartas", systemImage: "rectangle.stack.fill")
                Spacer()
                Label("\(model.dashboard.unopenedPacks) packs", systemImage: "shippingbox.fill")
                Spacer()
                Label("\(model.dashboard.completedAlbums) álbuns", systemImage: "checkmark.seal.fill")
            }
            .font(.caption).foregroundStyle(YePlyTheme.secondary)
        }
        .padding(16).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .packs: packsSection
        case .collection: collectionSection
        case .albums: albumsSection
        case .achievements: achievementsSection
        case .trades: tradesSection
        }
    }

    private var packsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                TextField("Código do pack", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(.horizontal, 13).frame(height: 44).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                Button("Resgatar") {
                    let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { if await model.redeem(code: clean, repository: container.repository) { code = "" } }
                }
                .buttonStyle(.borderedProminent).tint(YePlyTheme.accent).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.packs.isEmpty {
                ContentUnavailableView("Nenhum pack disponível", systemImage: "shippingbox", description: Text("Ouça músicas, mantenha seu streak ou use um código para ganhar packs."))
                    .padding(.top, 25)
            } else {
                ForEach(model.packs) { pack in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [YePlyTheme.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "rectangle.stack.fill").font(.title).foregroundStyle(.black.opacity(0.7))
                        }.frame(width: 66, height: 76)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PACK · \(pack.cardCount) CARTAS").font(.caption2.bold()).tracking(1.2).foregroundStyle(YePlyTheme.accent)
                            Text(pack.source).font(.headline).lineLimit(1)
                            Text(pack.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(YePlyTheme.secondary)
                        }
                        Spacer()
                        Button(model.isOpeningPack ? "Abrindo…" : "Abrir") { Task { await model.open(pack, repository: container.repository) } }
                            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).disabled(model.isOpeningPack)
                    }
                    .padding(12).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            Text("As raridades usam reproduções verificadas dentro do YePly. O Spotify não fornece contagem pública de plays por faixa.")
                .font(.caption2).foregroundStyle(YePlyTheme.tertiary).padding(.top, 4)
            if session.isAdmin {
                VStack(spacing: 9) {
                    Button { Task { await model.syncKanye(repository: container.repository) } } label: {
                        Label("Sincronizar catálogo de Kanye West", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                    Button { showingPackCodeCreator = true } label: {
                        Label("Criar código de pack", systemImage: "ticket.fill")
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                }
                .buttonStyle(.bordered).tint(YePlyTheme.accent)
            }
        }
    }

    private var collectionSection: some View {
        Group {
            if model.inventory.isEmpty {
                ContentUnavailableView("Sua coleção está vazia", systemImage: "rectangle.stack", description: Text("Abra seu primeiro pack para receber três cartas."))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(model.inventory) { card in
                        Button { selectedCard = card } label: { ResolvedCollectibleCard(card: card, style: .compact) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(model.albums) { album in
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.albumTitle).font(.headline)
                            Text(album.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary)
                        }
                        Spacer()
                        if album.isComplete {
                            Button(album.badgeEquipped ? "Equipada" : "Usar badge") { Task { await model.equip(album, repository: container.repository) } }
                                .font(.caption.bold()).buttonStyle(.bordered).tint(YePlyTheme.accent).disabled(album.badgeEquipped)
                        }
                    }
                    ProgressView(value: album.progress).tint(album.isComplete ? .green : YePlyTheme.accent)
                    HStack {
                        Text("\(album.ownedUnique)/\(album.totalCards) cartas únicas").font(.caption).foregroundStyle(YePlyTheme.secondary)
                        Spacer()
                        if album.isComplete { Label("Badge liberada", systemImage: "checkmark.seal.fill").font(.caption.bold()).foregroundStyle(.green) }
                    }
                }
                .padding(15).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
            }
        }
    }

    private var achievementsSection: some View {
        LazyVStack(spacing: 11) {
            ForEach(model.achievements) { achievement in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: achievement.symbolName).font(.title2).foregroundStyle(achievement.isUnlocked ? YePlyTheme.accent : YePlyTheme.tertiary).frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(achievement.title).font(.headline)
                            Text(achievement.description).font(.caption).foregroundStyle(YePlyTheme.secondary)
                        }
                        Spacer()
                    }
                    ProgressView(value: achievement.completion).tint(achievement.isUnlocked ? .green : YePlyTheme.accent)
                    HStack {
                        Text("\(min(achievement.progress, achievement.target).formatted()) / \(achievement.target.formatted())").font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                        Spacer()
                        if achievement.canClaimReward {
                            Menu("Escolher pack · 5 cartas") {
                                ForEach(model.artists.filter { model.dashboard.favoriteArtists.contains($0.artistKey) }) { artist in
                                    Button(artist.artistName) { Task { await model.claim(achievement, artistKey: artist.artistKey, repository: container.repository) } }
                                }
                                Button("Escolher favoritos…") { showingFavorites = true }
                            }
                            .font(.caption.bold()).foregroundStyle(YePlyTheme.accent)
                        } else if achievement.rewardClaimedAt != nil {
                            Label("Resgatada", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                        }
                    }
                }
                .padding(14).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
            }
        }
    }

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingTradeCreator = true } label: {
                Label("Propor nova troca", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.borderedProminent).tint(YePlyTheme.accent)
            if model.trades.isEmpty {
                ContentUnavailableView("Nenhuma troca", systemImage: "arrow.left.arrow.right", description: Text("Procure um usuário e ofereça suas cartas repetidas."))
                    .padding(.top, 22)
            } else {
                ForEach(model.trades) { trade in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text("@\(trade.counterpartyUsername)").font(.headline); Spacer(); Text(trade.status.uppercased()).font(.caption2.bold()).foregroundStyle(YePlyTheme.accent) }
                        Text("Você oferece: \(trade.offeredTitles.joined(separator: ", "))").font(.caption).foregroundStyle(YePlyTheme.secondary)
                        Text("Você recebe: \(trade.requestedTitles.joined(separator: ", "))").font(.caption).foregroundStyle(YePlyTheme.secondary)
                        if trade.canRespond && trade.status == "pending" {
                            HStack {
                                Button("Recusar", role: .destructive) { Task { await model.respond(trade, accept: false, repository: container.repository) } }.buttonStyle(.bordered)
                                Button("Aceitar troca") { Task { await model.respond(trade, accept: true, repository: container.repository) } }.buttonStyle(.borderedProminent).tint(.green)
                            }
                        }
                    }
                    .padding(14).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
                }
            }
        }
    }
}

private struct ResolvedCollectibleCard: View {
    @EnvironmentObject private var container: AppContainer
    let card: CollectibleCardItem
    let style: CollectibleCardStyle
    @State private var artworkURL: URL?

    var body: some View {
        CollectibleCardView(model: displayModel, style: style)
            .task(id: card.artworkPath) {
                guard let path = card.artworkPath else { return }
                artworkURL = try? await container.repository.signedCoverURL(path: path)
            }
    }

    private var displayModel: CollectibleCardDisplayModel {
        CollectibleCardDisplayModel(
            id: card.id.uuidString, title: card.title, artistName: card.artistName,
            albumName: card.albumName, rarity: card.rarity, serialNumber: card.serialNumber,
            artworkURL: artworkURL
        )
    }
}

private struct CardDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: CollectibleCardItem
    var body: some View {
        ScrollView { ResolvedCollectibleCard(card: card, style: .detailed).padding(18) }
            .navigationTitle("Carta #\(card.serialNumber)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } } }
            .yeplyBackground()
    }
}

private struct CardPackRevealView: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [CollectibleCardItem]
    let onClose: () -> Void
    @State private var index = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("NOVAS CARTAS").font(.caption2.bold()).tracking(2).foregroundStyle(YePlyTheme.accent)
                TabView(selection: $index) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { entry in
                        ResolvedCollectibleCard(card: entry.element, style: .detailed)
                            .padding(.horizontal, 20).tag(entry.offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button(index + 1 < cards.count ? "Próxima carta" : "Guardar na coleção") {
                    if index + 1 < cards.count { withAnimation(.snappy) { index += 1 } }
                    else { onClose(); dismiss() }
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).padding(.bottom, 18)
            }
            .padding(.top, 14).yeplyBackground()
        }
        .interactiveDismissDisabled(index + 1 < cards.count)
    }
}

struct FavoriteCardArtistsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    var onSaved: (() -> Void)?
    @State private var artists: [CardArtistOption] = []
    @State private var selected: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(artists) { artist in
                Button { if selected.contains(artist.artistKey) { selected.remove(artist.artistKey) } else if selected.count < 5 { selected.insert(artist.artistKey) } } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(artist.artistName).foregroundStyle(.white); Text("\(artist.cardCount) cartas disponíveis").font(.caption).foregroundStyle(YePlyTheme.secondary) }
                        Spacer(); Image(systemName: selected.contains(artist.artistKey) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(artist.artistKey) ? YePlyTheme.accent : YePlyTheme.tertiary)
                    }
                }.buttonStyle(.plain).listRowBackground(YePlyTheme.elevated)
            }
            .scrollContentBackground(.hidden).background(YePlyTheme.background)
            .navigationTitle("Artistas favoritos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Salvando…" : "Salvar") { save() }.disabled(isSaving || selected.isEmpty) }
            }
            .task {
                do {
                    async let artists = container.repository.fetchCardArtists()
                    async let dashboard = container.repository.fetchCardDashboard()
                    self.artists = try await artists
                    let loadedDashboard = try await dashboard
                    selected = Set(loadedDashboard.favoriteArtists)
                }
                catch { errorMessage = error.localizedDescription }
            }
            .alert("Não foi possível salvar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do { _ = try await container.repository.setFavoriteCardArtists(Array(selected)); onSaved?(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

@MainActor
private final class CardProfileShowcaseModel: ObservableObject {
    @Published var dashboard = CardGameDashboard.empty
    @Published var albums: [CardAlbumProgress] = []
    @Published var achievements: [CardAchievement] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let dashboard = repository.fetchCardDashboard()
            async let albums = repository.fetchCardAlbumProgress()
            async let achievements = repository.fetchCardAchievements()
            self.dashboard = try await dashboard
            self.albums = try await albums
            self.achievements = try await achievements
            errorMessage = nil
        } catch let error where error.isYePlyCancellation { return }
        catch { errorMessage = error.localizedDescription }
    }

    func equip(_ album: CardAlbumProgress, slot: Int, repository: any MusicRepository) async {
        guard let badgeID = album.badgeId else { return }
        do {
            _ = try await repository.equipCardBadge(id: badgeID, slot: slot)
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct CardProfileShowcaseView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = CardProfileShowcaseModel()

    private var completedAlbums: [CardAlbumProgress] { model.albums.filter(\.isComplete) }
    private var unlockedAchievements: [CardAchievement] { model.achievements.filter(\.isUnlocked) }

    var body: some View {
        ScrollView {
            showcaseContent
        }
        .navigationTitle("Badges e conquistas")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(repository: container.repository) }
        .task { await model.load(repository: container.repository) }
        .overlay { if model.isLoading && model.achievements.isEmpty { ProgressView() } }
        .alert("Cartas", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .yeplyBackground()
    }

    private var showcaseContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            profileSummary
            albumBadgesSection
            achievementsSection
        }
        .padding(18)
        .padding(.bottom, 90)
    }

    @ViewBuilder
    private var albumBadgesSection: some View {
        sectionTitle("Badges de álbuns", detail: "Escolha até três posições no seu perfil")
        if completedAlbums.isEmpty {
            ContentUnavailableView(
                "Nenhuma badge ainda",
                systemImage: "seal",
                description: Text("Complete todas as cartas de um álbum para liberar a badge.")
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 11) {
                ForEach(completedAlbums) { album in
                    CardAlbumBadgeRow(album: album) { slot in
                        Task { await model.equip(album, slot: slot, repository: container.repository) }
                    }
                }
            }
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                "Conquistas",
                detail: "\(unlockedAchievements.count) de \(model.achievements.count) liberadas"
            )
            LazyVStack(spacing: 10) {
                ForEach(model.achievements) { achievement in
                    CardAchievementProgressRow(achievement: achievement)
                }
            }
        }
    }

    private var profileSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [YePlyTheme.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "medal.star.fill").font(.title).foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nível \(model.dashboard.level)").font(.title3.bold())
                Text("\(model.dashboard.xp.formatted()) XP · \(model.dashboard.totalCards) cartas")
                    .font(.subheadline).foregroundStyle(YePlyTheme.secondary)
            }
            Spacer()
        }
        .padding(16).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 20))
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold())
            Text(detail).font(.caption).foregroundStyle(YePlyTheme.secondary)
        }
    }
}

private struct CardAlbumBadgeRow: View {
    let album: CardAlbumProgress
    let onEquip: (Int) -> Void

    var body: some View {
        HStack(spacing: 13) {
            badgeIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(album.albumTitle).font(.headline)
                Text("\(album.totalCards) cartas · \(album.artistName)")
                    .font(.caption)
                    .foregroundStyle(YePlyTheme.secondary)
            }
            Spacer()
            Menu {
                ForEach(1...3, id: \.self) { slot in
                    Button("Posição \(slot)") { onEquip(slot) }
                }
            } label: {
                Text(album.badgeEquipped ? "Alterar" : "Equipar")
                    .font(.caption.bold())
            }
        }
        .padding(14)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
    }

    private var badgeIcon: some View {
        Image(systemName: album.badgeEquipped ? "checkmark.seal.fill" : "seal.fill")
            .font(.title2)
            .foregroundStyle(album.badgeEquipped ? Color.green : YePlyTheme.accent)
            .frame(width: 42, height: 42)
            .background(YePlyTheme.surface, in: Circle())
    }
}

private struct CardAchievementProgressRow: View {
    let achievement: CardAchievement

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.symbolName)
                .font(.title3)
                .foregroundStyle(achievement.isUnlocked ? YePlyTheme.accent : YePlyTheme.tertiary)
                .frame(width: 36, height: 36)
                .background(YePlyTheme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.title).font(.subheadline.bold())
                    Spacer()
                    Text("\(min(achievement.progress, achievement.target))/\(achievement.target)")
                        .font(.caption2)
                        .foregroundStyle(YePlyTheme.tertiary)
                }
                ProgressView(value: achievement.completion)
                    .tint(achievement.isUnlocked ? Color.green : YePlyTheme.accent)
            }
        }
        .padding(13)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CreatePackCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    let artists: [CardArtistOption]
    let onCreated: (String) -> Void
    @State private var code = ""
    @State private var label = ""
    @State private var maxRedemptions = 25
    @State private var cardCount = 3
    @State private var rarity: CollectibleCardRarity = .common
    @State private var artistKey = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Código") {
                    TextField("Ex.: YEPLY-KANYE-01", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Descrição opcional", text: $label)
                }
                Section("Conteúdo") {
                    Stepper("\(cardCount) cartas por pack", value: $cardCount, in: 1...5)
                    Stepper("\(maxRedemptions) resgates", value: $maxRedemptions, in: 1...10_000)
                    Picker("Raridade mínima", selection: $rarity) {
                        ForEach(CollectibleCardRarity.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Artista", selection: $artistKey) {
                        Text("Aleatório").tag("")
                        ForEach(artists) { Text($0.artistName).tag($0.artistKey) }
                    }
                }
                Section {
                    Text("O código não fica armazenado em texto puro: o servidor salva somente o hash. Guarde e compartilhe o valor digitado acima.")
                        .font(.caption).foregroundStyle(YePlyTheme.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(YePlyTheme.background)
            .navigationTitle("Novo código de pack").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isWorking ? "Criando…" : "Criar") { create() }.disabled(cleanCode.count < 6 || isWorking) }
            }
            .alert("Não foi possível criar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var cleanCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        isWorking = true
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedArtistKey: String? = artistKey.isEmpty ? nil : artistKey
        Task {
            defer { isWorking = false }
            do {
                _ = try await container.repository.createCardPackCode(
                    cleanCode,
                    label: cleanLabel.isEmpty ? nil : cleanLabel,
                    maxRedemptions: maxRedemptions,
                    artistKey: selectedArtistKey,
                    cardCount: cardCount,
                    rarityFloor: rarity
                )
                onCreated(cleanCode.uppercased())
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct CreateCardTradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    let ownCards: [CollectibleCardItem]
    let onCreated: () -> Void
    @State private var username = ""
    @State private var profile: UserProfile?
    @State private var theirCards: [CollectibleCardItem] = []
    @State private var offered: Set<UUID> = []
    @State private var requested: Set<UUID> = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Usuário") {
                    HStack { TextField("@username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("Buscar") { search() }.disabled(username.isEmpty || isWorking) }
                    if let profile { Label("@\(profile.username) · \(profile.displayName)", systemImage: "person.crop.circle.fill").foregroundStyle(YePlyTheme.accent) }
                }
                if profile != nil {
                    cardSelectionSection("Suas cartas oferecidas", cards: ownCards, selection: $offered)
                    cardSelectionSection("Cartas que você quer", cards: theirCards, selection: $requested)
                }
            }
            .scrollContentBackground(.hidden).background(YePlyTheme.background)
            .navigationTitle("Nova troca").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enviar") { create() }.disabled(profile == nil || offered.isEmpty || requested.isEmpty || isWorking) }
            }
            .alert("Troca", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func cardSelectionSection(_ title: String, cards: [CollectibleCardItem], selection: Binding<Set<UUID>>) -> some View {
        Section(title) {
            ForEach(cards) { card in
                Button {
                    var updated = selection.wrappedValue
                    if updated.contains(card.id) { updated.remove(card.id) }
                    else if updated.count < 5 { updated.insert(card.id) }
                    selection.wrappedValue = updated
                } label: {
                    HStack { Text(card.title).foregroundStyle(.white); Spacer(); Text(card.rarity.title).font(.caption).foregroundStyle(YePlyTheme.secondary); Image(systemName: selection.wrappedValue.contains(card.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(YePlyTheme.accent) }
                }.buttonStyle(.plain)
            }
        }
    }

    private func search() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let clean = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
                let profiles = try await container.repository.searchProfiles(query: clean)
                guard let match = profiles.first(where: { $0.username.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else { throw YePlyError.message("Usuário não encontrado.") }
                profile = match; theirCards = try await container.repository.fetchTradeableCards(username: match.username)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func create() {
        guard let profile else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { _ = try await container.repository.createCardTrade(receiverID: profile.id, offeredCardIDs: Array(offered), requestedCardIDs: Array(requested)); onCreated(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
