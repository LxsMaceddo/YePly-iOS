import SwiftUI

private enum CardsHubSection: String, CaseIterable, Identifiable {
    case packs, store, collection, albums, folders, achievements, wishlist, offers, trades
    var id: String { rawValue }
    var title: String {
        switch self {
        case .packs: "Packs"
        case .store: "Loja"
        case .collection: "Coleção"
        case .albums: "Álbuns"
        case .folders: "Pastas"
        case .achievements: "Conquistas"
        case .wishlist: "Desejadas"
        case .offers: "Ofertas"
        case .trades: "Trocas"
        }
    }

    var symbolName: String {
        switch self {
        case .packs: "shippingbox.fill"
        case .store: "bag.fill"
        case .collection: "rectangle.stack.fill"
        case .albums: "square.stack.fill"
        case .folders: "folder.fill"
        case .achievements: "trophy.fill"
        case .wishlist: "heart.fill"
        case .offers: "megaphone.fill"
        case .trades: "arrow.left.arrow.right"
        }
    }
}

private struct CardsHubSectionBar: View {
    @Binding var selection: CardsHubSection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CardsHubSection.allCases) { section in
                    Button {
                        withAnimation(.snappy) { selection = section }
                    } label: {
                        Label(section.title, systemImage: section.symbolName)
                            .font(.caption.bold())
                            .foregroundStyle(selection == section ? .black : .white.opacity(0.76))
                            .padding(.horizontal, 13)
                            .frame(height: 38)
                            .background(
                                selection == section ? YePlyTheme.accent : YePlyTheme.elevated,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

@MainActor
private final class CardsHubViewModel: ObservableObject {
    @Published var dashboard = CardGameDashboard.empty
    @Published var inventory: [CollectibleCardItem] = []
    @Published var packs: [CardPackSummary] = []
    @Published var albums: [CardAlbumProgress] = []
    @Published var albumCatalog: [CardAlbumCatalogItem] = []
    @Published var achievements: [CardAchievement] = []
    @Published var artists: [CardArtistOption] = []
    @Published var trades: [CardTradeSummary] = []
    @Published var wishlist: [CardWishlistItem] = []
    @Published var folders: [CardFolder] = []
    @Published var publicOffers: [CardPublicOffer] = []
    @Published var storeProducts = CardPackProductKind.allCases.map { CardPackStoreProduct(kind: $0) }
    @Published var openedPack: YePlyOpenedPack?
    @Published var openedPacks: [YePlyOpenedPack] = []
    @Published var rewardMessage: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isOpeningPack = false
    @Published var purchasingProduct: CardPackProductKind?

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
            async let folders = repository.fetchCardFolders(profileID: nil)
            async let offers = repository.fetchPublicCardOffers(profileID: nil)
            self.dashboard = try await dashboard
            self.inventory = try await inventory
            self.packs = try await packs
            self.albums = try await albums
            self.albumCatalog = try await repository.fetchCardAlbumCatalog()
            self.achievements = try await achievements
            self.artists = try await artists
            self.trades = try await trades
            self.folders = (try? await folders) ?? []
            self.publicOffers = (try? await offers) ?? []
            do {
                let loadedWishlist = try await repository.fetchCardWishlist()
                self.wishlist = loadedWishlist
            } catch {
                self.wishlist = []
            }
            do {
                let loadedStore = try await repository.fetchCardPackStore()
                if !loadedStore.isEmpty {
                    self.storeProducts = loadedStore.sorted { ($0.sortOrder ?? 999) < ($1.sortOrder ?? 999) }
                }
            } catch {
                self.storeProducts = CardPackProductKind.allCases.map { CardPackStoreProduct(kind: $0) }
            }
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
            let cards = try await repository.openCardPack(id: pack.id)
            openedPack = YePlyOpenedPack(pack: pack, cards: cards)
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func openAll(repository: any MusicRepository) async {
        guard !isOpeningPack, !packs.isEmpty else { return }
        isOpeningPack = true
        let packsToOpen = packs
        var results: [YePlyOpenedPack] = []
        defer { isOpeningPack = false }

        do {
            for pack in packsToOpen {
                let cards = try await repository.openCardPack(id: pack.id)
                results.append(YePlyOpenedPack(pack: pack, cards: cards))
            }
            openedPacks = results
            await load(repository: repository)
        } catch {
            if !results.isEmpty {
                openedPacks = results
                rewardMessage = "Alguns packs foram abertos; os demais continuam guardados."
                await load(repository: repository)
            } else {
                errorMessage = error.localizedDescription
            }
        }
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

    func buy(_ product: CardPackProductKind, repository: any MusicRepository) async {
        guard purchasingProduct == nil else { return }
        purchasingProduct = product
        defer { purchasingProduct = nil }
        do {
            let result = try await repository.buyCardPack(product: product)
            rewardMessage = result.message ?? "\(product.title) adicionado aos seus packs."
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleWishlist(definitionID: UUID, repository: any MusicRepository) async {
        do {
            _ = try await repository.toggleCardWishlist(definitionID: definitionID)
            await load(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func createFolder(name: String, repository: any MusicRepository) async {
        do { _ = try await repository.createCardFolder(name: name, emoji: "📁", isPublic: true); await load(repository: repository) }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteFolder(_ folder: CardFolder, repository: any MusicRepository) async {
        do { _ = try await repository.deleteCardFolder(id: folder.id); await load(repository: repository) }
        catch { errorMessage = error.localizedDescription }
    }

    func syncKanye(repository: any MusicRepository) async {
        do {
            let reward = try await repository.syncCollectibleCatalog(artistName: "Kanye West")
            rewardMessage = reward.message ?? "Discografia oficial de Kanye West sincronizada."
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
    @State private var showingFolderCreator = false
    @State private var folderName = ""
    @State private var tradeTargetUsername: String?
    @State private var selectedTrade: CardTradeSummary?

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
                    CardsHubSectionBar(selection: $section)
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
        .fullScreenCover(item: $selectedCard) { card in
            NavigationStack { CardDetailSheet(card: card) }
        }
        .sheet(isPresented: $showingFavorites) {
            FavoriteCardArtistsView(onSaved: { Task { await model.load(repository: container.repository) } })
        }
        .sheet(isPresented: $showingTradeCreator) {
            CreateCardTradeView(
                ownCards: model.inventory,
                coinBalance: model.dashboard.coinBalance ?? 0,
                onCreated: { Task { await model.load(repository: container.repository) } }
            )
        }
        .sheet(isPresented: Binding(get: { tradeTargetUsername != nil }, set: { if !$0 { tradeTargetUsername = nil } })) {
            CreateCardTradeView(ownCards: model.inventory, coinBalance: model.dashboard.coinBalance ?? 0, initialUsername: tradeTargetUsername, onCreated: { Task { await model.load(repository: container.repository) } })
        }
        .sheet(item: $selectedTrade) { trade in
            CardTradeInspectionView(trade: trade) { accept in
                Task { await model.respond(trade, accept: accept, repository: container.repository); selectedTrade = nil }
            }
        }
        .sheet(isPresented: $showingPackCodeCreator) {
            CreatePackCodeView(artists: model.artists) { createdCode in
                model.rewardMessage = "Código \(createdCode) criado e pronto para compartilhar."
            }
        }
        .fullScreenCover(item: $model.openedPack) { result in
            YePlyPackOpeningView(
                pack: result.pack,
                cards: result.cards,
                artworkResolver: cardArtworkResolver,
                onComplete: { model.openedPack = nil; section = .collection }
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { !model.openedPacks.isEmpty },
            set: { if !$0 { model.openedPacks = [] } }
        )) {
            YePlyBulkPackOpeningView(
                openedPacks: model.openedPacks,
                artworkResolver: cardArtworkResolver,
                onComplete: { model.openedPacks = []; section = .collection }
            )
        }
        .alert("Cartas", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .alert("Nova pasta pública", isPresented: $showingFolderCreator) {
            TextField("Nome da pasta", text: $folderName)
            Button("Criar") { let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines); folderName = ""; Task { await model.createFolder(name: name, repository: container.repository) } }.disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancelar", role: .cancel) { folderName = "" }
        } message: { Text("Organize suas cartas e mostre esta pasta no seu perfil.") }
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

    private var cardArtworkResolver: YePlyCardArtworkResolver {
        { card in
            let primary: URL?
            if let path = card.artworkPath,
               let direct = URL(string: path),
               direct.scheme?.lowercased() == "https" {
                primary = direct
            } else if let path = card.artworkPath {
                primary = try? await container.repository.signedCoverURL(path: path)
            } else {
                primary = nil
            }
            let candidates = YePlyArtworkFallbacks.candidates(primary: primary, albumName: card.albumName)
            for candidate in candidates {
                if await YePlyRemoteImageLoader.shared.data(for: candidate) != nil { return candidate }
            }
            return candidates.first
        }
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
            Divider().overlay(YePlyTheme.line)
            HStack {
                Label("CARTEIRA", systemImage: "yensign.circle.fill")
                    .font(.caption2.bold()).tracking(1.2).foregroundStyle(YePlyTheme.tertiary)
                Spacer()
                Text("\((model.dashboard.coinBalance ?? 0).formatted()) moedas")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(YePlyTheme.accent)
            }
        }
        .padding(16).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .packs: packsSection
        case .store: storeSection
        case .collection: collectionSection
        case .albums: albumsSection
        case .folders: foldersSection
        case .achievements: achievementsSection
        case .wishlist: wishlistSection
        case .offers: publicOffersSection
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
                YePlyOpenAllPacksButton(packCount: model.packs.count, isOpening: model.isOpeningPack) {
                    Task { await model.openAll(repository: container.repository) }
                }
                ForEach(model.packs) { pack in
                    HStack(spacing: 14) {
                        YePlyCardPackView(pack: pack, compact: true)
                            .frame(width: 66, height: 88)
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
            if session.isAdmin {
                VStack(spacing: 9) {
                    Button { Task { await model.syncKanye(repository: container.repository) } } label: {
                        Label("Sincronizar discografia oficial de Kanye West", systemImage: "arrow.triangle.2.circlepath")
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
        CardCollectionBrowser(cards: model.inventory) { selectedCard = $0 }
    }

    private var storeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardStoreHero(balance: model.dashboard.coinBalance ?? 0)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PACK LAB").font(.caption2.bold()).tracking(1.8).foregroundStyle(YePlyTheme.accent)
                    Text("Escolha sua próxima abertura").font(.title3.bold())
                }
                Spacer()
            }

            LazyVStack(spacing: 12) {
                ForEach(model.storeProducts) { product in
                    CardStoreProductTile(
                        product: product,
                        balance: model.dashboard.coinBalance ?? 0,
                        isBuying: model.purchasingProduct == product.productKey
                    ) {
                        Task { await model.buy(product.productKey, repository: container.repository) }
                    }
                }
            }

        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading) { Text("ARQUIVO PESSOAL").font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.accent); Text("Suas pastas de cartas").font(.title3.bold()) }; Spacer(); Button { showingFolderCreator = true } label: { Image(systemName: "folder.badge.plus").font(.title2) } }
            if model.folders.isEmpty {
                ContentUnavailableView("Nenhuma pasta", systemImage: "folder", description: Text("Crie uma pasta e adicione cartas pelo painel de detalhes."))
            } else {
                ForEach(model.folders) { folder in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack { Text(folder.emoji).font(.title2); VStack(alignment: .leading) { Text(folder.name).font(.headline); Text("\(folder.itemCount) cartas · \(folder.isPublic ? "Pública" : "Privada")").font(.caption).foregroundStyle(YePlyTheme.secondary) }; Spacer(); Menu { Button("Excluir pasta", role: .destructive) { Task { await model.deleteFolder(folder, repository: container.repository) } } } label: { Image(systemName: "ellipsis") } }
                        if !folder.items.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 9) { ForEach(folder.items.prefix(10)) { card in Button { selectedCard = card } label: { CardBrowserArtwork(path: card.artworkPath, seed: card.definitionId.uuidString, title: card.title, tint: card.rarity.accentColor, cornerRadius: 12).frame(width: 84, height: 84) }.buttonStyle(.plain) } } } }
                    }.padding(15).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    private var publicOffersSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("MERCADO DA COMUNIDADE").font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.accent)
            Text("Ofertas públicas").font(.title3.bold())
            if model.publicOffers.isEmpty { ContentUnavailableView("Nenhuma oferta pública", systemImage: "megaphone", description: Text("Proteja o que não troca e anuncie as outras cartas pelo detalhe da carta.")) }
            else { ForEach(model.publicOffers) { offer in
                HStack(spacing: 12) {
                    CardBrowserArtwork(path: offer.artworkPath, seed: offer.definitionId.uuidString, title: offer.title, tint: offer.rarity.accentColor, cornerRadius: 13).frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 4) { Text(offer.title).font(.headline).lineLimit(1); Text("@\(offer.username) · \(offer.albumName)").font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1); if offer.askingCoins > 0 { Label(offer.askingCoins.formatted(), systemImage: "yensign.circle.fill").font(.caption.bold()).foregroundStyle(YePlyTheme.accent) } }
                    Spacer(); Button("Trocar") { tradeTargetUsername = offer.username }.buttonStyle(.borderedProminent).tint(YePlyTheme.accent)
                }.padding(12).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
            } }
        }
    }

    private var albumsSection: some View {
        CardAlbumLibraryBrowser(
            albums: model.albums,
            cards: model.inventory,
            catalog: model.albumCatalog,
            wishlistDefinitionIDs: Set(model.wishlist.map(\.definitionId)),
            onSelectCard: { selectedCard = $0 },
            onToggleWishlist: { definitionID in
                Task { await model.toggleWishlist(definitionID: definitionID, repository: container.repository) }
            }
        )
    }

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RADAR DE CARTAS").font(.caption2.bold()).tracking(1.6).foregroundStyle(YePlyTheme.accent)
                    Text("Cartas que você quer").font(.title3.bold())
                }
                Spacer()
                Text(model.wishlist.count.formatted())
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(YePlyTheme.elevated, in: Capsule())
            }

            if model.wishlist.isEmpty {
                ContentUnavailableView(
                    "Sua lista está vazia",
                    systemImage: "heart.text.square",
                    description: Text("Abra um álbum e toque no coração de uma carta que ainda falta.")
                )
                .padding(.top, 28)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.wishlist) { item in
                        CardWishlistRow(item: item) {
                            Task { await model.toggleWishlist(definitionID: item.definitionId, repository: container.repository) }
                        }
                    }
                }
            }
        }
    }

    private var achievementsSection: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(achievementGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(group.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title.uppercased()).font(.caption.bold()).tracking(1.4)
                            Text("\(group.items.filter(\.isUnlocked).count)/\(group.items.count) liberadas")
                                .font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                        }
                    }
                    ForEach(group.items) { achievement in
                        CardHubAchievementRow(achievement: achievement) {
                            Menu("Escolher pack · 5 cartas") {
                                ForEach(model.artists.filter { model.dashboard.favoriteArtists.contains($0.artistKey) }) { artist in
                                    Button(artist.artistName) {
                                        Task { await model.claim(achievement, artistKey: artist.artistKey, repository: container.repository) }
                                    }
                                }
                                Button("Escolher favoritos…") { showingFavorites = true }
                            }
                        }
                    }
                }
            }
        }
    }

    private var achievementGroups: [CardHubAchievementGroup] {
        let order = ["Coleção", "Audição", "Jornada", "Packs", "Trocas", "Comunidade"]
        let grouped = Dictionary(grouping: model.achievements, by: \.categoryTitle)
        return grouped.keys.sorted {
            let leftIndex = order.firstIndex(of: $0) ?? Int.max
            let rightIndex = order.firstIndex(of: $1) ?? Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }.map { title in
            let emoji: String
            switch title {
            case "Coleção": emoji = "💿"
            case "Audição": emoji = "🎧"
            case "Jornada": emoji = "🔥"
            case "Packs": emoji = "📦"
            case "Trocas": emoji = "🤝"
            case "Comunidade": emoji = "🌐"
            default: emoji = "🏅"
            }
            return CardHubAchievementGroup(title: title, emoji: emoji, items: grouped[title] ?? [])
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
                        TradeSummaryLine(
                            title: "Você oferece",
                            cardTitles: trade.offeredTitles,
                            coins: trade.offeredCoins ?? 0,
                            tint: .orange
                        )
                        TradeSummaryLine(
                            title: "Você recebe",
                            cardTitles: trade.requestedTitles,
                            coins: trade.requestedCoins ?? 0,
                            tint: .green
                        )
                        Button { selectedTrade = trade } label: { Label("Inspecionar proposta", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(trade.canRespond ? YePlyTheme.accent : .gray)
                    }
                    .padding(14).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
                }
            }
        }
    }
}

private struct CardTradeInspectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    let trade: CardTradeSummary
    let respond: (Bool) -> Void
    @State private var items: [CardTradeDetailItem] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 48)).foregroundStyle(YePlyTheme.accent)
                        Text("Proposta com @\(trade.counterpartyUsername)").font(.title2.bold())
                        Text(trade.status.uppercased()).font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.secondary)
                    }.frame(maxWidth: .infinity)
                    tradeSide(title: "Você entrega", side: "offered", coins: trade.offeredCoins ?? 0, tint: .orange)
                    tradeSide(title: "Você recebe", side: "requested", coins: trade.requestedCoins ?? 0, tint: .green)
                    if trade.canRespond && trade.status == "pending" {
                        HStack(spacing: 10) {
                            Button("Recusar", role: .destructive) { respond(false) }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                            Button("Aceitar troca") { respond(true) }.buttonStyle(.borderedProminent).tint(.green).frame(maxWidth: .infinity)
                        }
                    }
                }.padding(18).padding(.bottom, 30)
            }
            .navigationTitle("Detalhes da troca").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } } }
            .task { do { items = try await container.repository.fetchTradeDetail(id: trade.id) } catch { errorMessage = error.localizedDescription } }
            .alert("Não foi possível carregar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
            .yeplyBackground()
        }
    }

    private func tradeSide(title: String, side: String, coins: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.headline); Spacer(); if coins > 0 { Label(coins.formatted(), systemImage: "yensign.circle.fill").font(.subheadline.bold()).foregroundStyle(tint) } }
            let cards = items.filter { $0.side == side }
            if cards.isEmpty { Text("Nenhuma carta").font(.caption).foregroundStyle(YePlyTheme.secondary) }
            else { ForEach(cards) { item in
                HStack(spacing: 11) {
                    CardBrowserArtwork(path: item.artworkPath, seed: item.definitionId.uuidString, title: item.title, tint: item.rarity.accentColor, cornerRadius: 11).frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) { Text(item.title).font(.subheadline.bold()); Text("\(item.artistName) · \(item.albumName)").font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1) }
                    Spacer(); Text("#\(item.serialNumber)").font(.caption2.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary)
                }
            } }
        }.padding(15).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.2)))
    }
}

private struct CardHubAchievementGroup: Identifiable {
    let title: String
    let emoji: String
    let items: [CardAchievement]
    var id: String { title }
}

private struct CardHubAchievementRow<ClaimMenu: View>: View {
    let achievement: CardAchievement
    let claimMenu: () -> ClaimMenu

    init(achievement: CardAchievement, @ViewBuilder claimMenu: @escaping () -> ClaimMenu) {
        self.achievement = achievement
        self.claimMenu = claimMenu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(achievement.displayEmoji)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(YePlyTheme.elevatedStrong, in: Circle())
                    .saturation(achievement.isUnlocked ? 1 : 0)
                    .opacity(achievement.isUnlocked ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 3) {
                    Text(achievement.title).font(.headline)
                    Text(achievement.description).font(.caption).foregroundStyle(YePlyTheme.secondary)
                }
                Spacer()
            }
            ProgressView(value: achievement.completion)
                .tint(achievement.isUnlocked ? .green : YePlyTheme.accent)
            HStack {
                Text("\(min(achievement.progress, achievement.target).formatted()) / \(achievement.target.formatted())")
                    .font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                Spacer()
                if achievement.canClaimReward {
                    claimMenu().font(.caption.bold()).foregroundStyle(YePlyTheme.accent)
                } else if achievement.rewardClaimedAt != nil {
                    Label("Resgatada", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct CardStoreHero: View {
    let balance: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [YePlyTheme.accent.opacity(0.92), Color.purple.opacity(0.72), Color.black.opacity(0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle().fill(.white.opacity(0.13)).frame(width: 150).blur(radius: 4).offset(x: 115, y: -58)
            Circle().fill(YePlyTheme.accent.opacity(0.24)).frame(width: 190).blur(radius: 25).offset(x: -105, y: 90)

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("YEPLY VAULT", systemImage: "sparkles")
                        .font(.caption2.bold()).tracking(1.6)
                    Spacer()
                    Image(systemName: "lock.shield.fill").font(.title3)
                }
                .foregroundStyle(.white.opacity(0.82))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Seu saldo").font(.caption).foregroundStyle(.white.opacity(0.66))
                    Text(balance.formatted())
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .contentTransition(.numericText())
                    Text("MOEDAS").font(.caption2.bold()).tracking(2).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(20)
        }
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.13)))
    }
}

private struct CardStoreProductTile: View {
    let product: CardPackStoreProduct
    let balance: Int
    let isBuying: Bool
    let onBuy: () -> Void

    private var canBuy: Bool { balance >= product.price && !isBuying }

    private var palette: [Color] {
        if let accentHex = product.accentHex, let color = Color(yeplyHex: accentHex) {
            return [color, color.opacity(0.48), .black]
        }
        return switch product.productKey {
        case .common: [Color.blue.opacity(0.64), Color.black]
        case .epic: [Color.purple.opacity(0.8), Color.black]
        case .favoriteArtists: [Color.pink.opacity(0.8), Color.purple.opacity(0.45)]
        case .booster: [YePlyTheme.accent, Color.orange.opacity(0.6), Color.black]
        case .mythicBoost: [Color(red: 0.9, green: 0.15, blue: 0.45), Color.purple.opacity(0.8), Color.black]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(0.14))
                    if let emoji = product.emoji, !emoji.isEmpty {
                        Text(emoji).font(.title2)
                    } else {
                        Image(systemName: product.productKey.symbolName)
                            .font(.title2.bold()).foregroundStyle(.white)
                    }
                }
                .frame(width: 50, height: 50)
                Spacer()
                Text("\(product.cardCount)x")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 9).frame(height: 27)
                    .background(.black.opacity(0.28), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title).font(.headline).lineLimit(1)
                Text(product.subtitle)
                    .font(.caption).foregroundStyle(.white.opacity(0.67))
                    .lineLimit(2)
                    .frame(minHeight: 34, alignment: .top)
            }

            Button(action: onBuy) {
                HStack(spacing: 7) {
                    if isBuying { ProgressView().tint(.black) }
                    Image(systemName: "yensign.circle.fill")
                    Text(product.price.formatted()).monospacedDigit()
                }
                .font(.subheadline.bold())
                .foregroundStyle(canBuy ? .black : .white.opacity(0.5))
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(canBuy ? Color.white : Color.black.opacity(0.3), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canBuy)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
        .background(
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.12)))
    }
}

private struct CardWishlistRow: View {
    let item: CardWishlistItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CardBrowserArtwork(
                path: item.artworkPath,
                seed: item.definitionId.uuidString,
                title: item.title,
                albumName: item.albumName,
                tint: item.rarity.accentColor,
                cornerRadius: 14
            )
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.bold()).lineLimit(1)
                Text("\(item.artistName) · \(item.albumName)")
                    .font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                Label(item.rarity.title, systemImage: item.rarity.symbolName)
                    .font(.caption2.bold()).foregroundStyle(item.rarity.accentColor)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "heart.fill")
                    .font(.headline).foregroundStyle(YePlyTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(YePlyTheme.accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remover \(item.title) da lista de desejos")
        }
        .padding(11)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TradeSummaryLine: View {
    let title: String
    let cardTitles: [String]
    let coins: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(cardTitles.isEmpty ? "Nenhuma carta" : cardTitles.joined(separator: ", "))
                    .font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(2)
                if coins > 0 {
                    Spacer(minLength: 4)
                    Label(coins.formatted(), systemImage: "yensign.circle.fill")
                        .font(.caption2.bold()).foregroundStyle(YePlyTheme.accent)
                }
            }
        }
        .padding(10)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ResolvedCollectibleCard: View {
    @EnvironmentObject private var container: AppContainer
    let card: CollectibleCardItem
    let style: CollectibleCardStyle
    @State private var artworkURL: URL?

    init(card: CollectibleCardItem, style: CollectibleCardStyle) {
        self.card = card
        self.style = style
        let directURL = card.artworkPath
            .flatMap { URL(string: $0) }
            .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        _artworkURL = State(initialValue: directURL)
    }

    var body: some View {
        CollectibleCardView(model: displayModel, style: style)
            .task(id: card.artworkPath) {
                if artworkURL != nil { return }
                guard let path = card.artworkPath else { return }
                artworkURL = try? await container.repository.signedCoverURL(path: path)
            }
    }

    private var displayModel: CollectibleCardDisplayModel {
        CollectibleCardDisplayModel(
            id: card.id.uuidString, title: card.title, artistName: card.artistName,
            albumName: card.albumName, rarity: card.rarity, serialNumber: card.serialNumber,
            editionNumber: card.editionNumber, editionTotal: card.editionTotal,
            artworkURL: artworkURL
        )
    }
}

private struct CardCollectionListRow: View {
    let card: CollectibleCardItem

    var body: some View {
        HStack(spacing: 13) {
            CardBrowserArtwork(path: card.artworkPath, seed: card.definitionId.uuidString, title: card.title, tint: card.rarity.accentColor, cornerRadius: 14)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(card.rarity.accentColor.opacity(0.75), lineWidth: 1.5)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: card.rarity.symbolName).font(.caption2)
                    Text(card.rarity.title.uppercased()).font(.caption2.bold()).tracking(1)
                }
                .foregroundStyle(card.rarity.accentColor)

                Text(card.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text("\(card.artistName) · \(card.albumName)")
                    .font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                if card.isProtected == true { Image(systemName: "lock.shield.fill").foregroundStyle(YePlyTheme.accent) }
                if let edition = card.editionNumber, let total = card.editionTotal {
                    Text("#\(edition.formatted()) / \(total.formatted())")
                        .font(.caption2.monospacedDigit().bold()).foregroundStyle(YePlyTheme.secondary)
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(YePlyTheme.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(YePlyTheme.elevated)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(card.rarity.accentColor)
                        .frame(width: 3).padding(.vertical, 18)
                }
        }
        .contentShape(Rectangle())
    }
}

struct CardDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    let card: CollectibleCardItem
    @State private var isProtected: Bool
    @State private var folders: [CardFolder] = []
    @State private var isPublicOffer = false
    @State private var askingCoins = 0
    @State private var actionMessage: String?

    init(card: CollectibleCardItem) {
        self.card = card
        _isProtected = State(initialValue: card.isProtected ?? false)
    }
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [card.rarity.accentColor.opacity(0.32), Color.black.opacity(0.96), .black],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 5) {
                        Text("YEPLY ARCHIVE").font(.caption2.bold()).tracking(2).foregroundStyle(card.rarity.accentColor)
                        Text("Uma edição da sua coleção").font(.caption).foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.top, 10)

                    ResolvedCollectibleCard(card: card, style: .detailed)

                    if card.catalogSource != nil {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Métrica manual do álbum", systemImage: "chart.bar.xaxis.ascending")
                                .font(.headline)
                            HStack {
                                metric("Visualizações", value: card.globalListenCount)
                                Divider().frame(height: 34)
                                metricText("Percentil", value: card.popularityScore.map { "\(Int($0.rounded()))%" } ?? "—")
                                Divider().frame(height: 34)
                                metric("No álbum", value: card.artistPopularityRank, suffix: card.artistCatalogSize.map { "/\($0)" })
                            }
                            NavigationLink {
                                CardYePlyTrackSearchView(card: card)
                            } label: {
                                Label("Encontrar no YePly", systemImage: "magnifyingglass")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                            }
                            .buttonStyle(.borderedProminent).tint(card.rarity.accentColor)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.09)))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("ORGANIZAR E NEGOCIAR").font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.accent)
                        Button { toggleProtection() } label: {
                            Label(isProtected ? "Carta protegida" : "Proteger esta carta", systemImage: isProtected ? "lock.shield.fill" : "lock.shield")
                                .frame(maxWidth: .infinity).frame(height: 48)
                        }.buttonStyle(.bordered).tint(isProtected ? .green : YePlyTheme.accent)
                        Menu {
                            if folders.isEmpty { Text("Crie uma pasta na aba Pastas") }
                            ForEach(folders) { folder in
                                Button { toggleFolder(folder) } label: {
                                    let contains = folder.items.contains(where: { $0.id == card.id })
                                    Label("\(folder.emoji) \(folder.name)", systemImage: contains ? "checkmark" : "plus")
                                }
                            }
                        } label: {
                            Label("Adicionar a uma pasta", systemImage: "folder.badge.plus").frame(maxWidth: .infinity).frame(height: 48)
                        }.buttonStyle(.bordered)
                        HStack {
                            TextField("Moedas pedidas", value: $askingCoins, format: .number).keyboardType(.numberPad)
                            Button(isPublicOffer ? "Remover oferta" : "Publicar oferta") { toggleOffer() }.buttonStyle(.borderedProminent).tint(isPublicOffer ? .red : YePlyTheme.accent)
                        }
                        .disabled(isProtected)
                    }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 38)
            }
        }
        .navigationTitle("Carta #\(card.serialNumber.formatted())").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fechar") { dismiss() }.fontWeight(.semibold)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            folders = (try? await container.repository.fetchCardFolders(profileID: nil)) ?? []
            let offers = (try? await container.repository.fetchPublicCardOffers(profileID: nil)) ?? []
            if let current = offers.first(where: { $0.cardInstanceId == card.id }) { isPublicOffer = true; askingCoins = current.askingCoins }
        }
        .alert("Carta", isPresented: Binding(get: { actionMessage != nil }, set: { if !$0 { actionMessage = nil } })) { Button("OK") {} } message: { Text(actionMessage ?? "") }
    }

    private func metric(_ title: String, value: Int?, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { $0.formatted(.number.notation(.compactName)) + (suffix ?? "") } ?? "—").font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(YePlyTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricText(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(YePlyTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleProtection() {
        Task { do { _ = try await container.repository.toggleCardProtection(instanceID: card.id); isProtected.toggle(); actionMessage = isProtected ? "Carta protegida contra trocas." : "Proteção removida." } catch { actionMessage = error.localizedDescription } }
    }

    private func toggleFolder(_ folder: CardFolder) {
        Task { do { _ = try await container.repository.toggleCardFolderItem(folderID: folder.id, instanceID: card.id); folders = (try? await container.repository.fetchCardFolders(profileID: nil)) ?? folders } catch { actionMessage = error.localizedDescription } }
    }

    private func toggleOffer() {
        Task { do { _ = try await container.repository.togglePublicCardOffer(instanceID: card.id, askingCoins: max(0, askingCoins), note: nil); isPublicOffer.toggle(); actionMessage = isPublicOffer ? "Oferta publicada na comunidade." : "Oferta removida." } catch { actionMessage = error.localizedDescription } }
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
        sectionTitle("Badges de álbuns", detail: "Escolha até quatro posições no seu perfil")
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
                ForEach(1...4, id: \.self) { slot in
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
        CardBrowserArtwork(
            path: album.artworkPath,
            seed: album.albumId.uuidString,
            title: album.albumTitle,
            tint: album.badgeEquipped ? .green : YePlyTheme.accent,
            cornerRadius: 23
        )
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(album.badgeEquipped ? Color.green : YePlyTheme.accent.opacity(0.75), lineWidth: 2)
        }
        .overlay(alignment: .bottomTrailing) {
            if album.badgeEquipped {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white, .green)
                    .background(.black, in: Circle())
            }
        }
    }
}

private struct CardAchievementProgressRow: View {
    let achievement: CardAchievement

    var body: some View {
        HStack(spacing: 12) {
            Text(achievement.displayEmoji)
                .font(.title3)
                .saturation(achievement.isUnlocked ? 1 : 0)
                .opacity(achievement.isUnlocked ? 1 : 0.55)
                .frame(width: 36, height: 36)
                .background(YePlyTheme.elevatedStrong, in: Circle())
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
                    TextField("Ex.: BETA!", text: $code)
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
                ToolbarItem(placement: .confirmationAction) { Button(isWorking ? "Criando…" : "Criar") { create() }.disabled(cleanCode.count < 3 || isWorking) }
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

struct CreateCardTradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    let ownCards: [CollectibleCardItem]
    let coinBalance: Int
    let initialUsername: String?
    let onCreated: () -> Void
    @State private var username = ""
    @State private var profile: UserProfile?
    @State private var theirCards: [CollectibleCardItem] = []
    @State private var offered: Set<UUID> = []
    @State private var requested: Set<UUID> = []
    @State private var offeredCoins = 0
    @State private var requestedCoins = 0
    @State private var selectionSide: TradeSelectionSide = .offered
    @State private var ownQuery = ""
    @State private var theirQuery = ""
    @State private var ownSort: CardTradeSort = .newest
    @State private var theirSort: CardTradeSort = .newest
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var availableOwnCards: [CollectibleCardItem]
    @State private var availableCoinBalance: Int
    @State private var isLoadingOwnData = false

    init(ownCards: [CollectibleCardItem], coinBalance: Int, initialUsername: String? = nil, onCreated: @escaping () -> Void) {
        self.ownCards = ownCards
        self.coinBalance = coinBalance
        self.initialUsername = initialUsername
        self.onCreated = onCreated
        _username = State(initialValue: initialUsername ?? "")
        _availableOwnCards = State(initialValue: ownCards)
        _availableCoinBalance = State(initialValue: coinBalance)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                recipientSearch

                if profile == nil {
                    ContentUnavailableView(
                        "Encontre quem vai trocar",
                        systemImage: "person.2.badge.gearshape.fill",
                        description: Text("Busque pelo @ do usuário para comparar as duas coleções.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    Picker("Lado da troca", selection: $selectionSide) {
                        ForEach(TradeSelectionSide.allCases) { side in Text(side.title).tag(side) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    tradeSelectionContent
                }
            }
            .background(YePlyTheme.background)
            .navigationTitle("Montar troca").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { tradeFooter }
            .alert("Troca", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
            .task(id: initialUsername) {
                await refreshOwnSide()
                if initialUsername != nil, profile == nil { search() }
            }
        }
    }

    private var recipientSearch: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "at").foregroundStyle(YePlyTheme.secondary)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { search() }
                Button("Buscar", action: search).font(.subheadline.bold())
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            .padding(.horizontal, 13).frame(height: 46)
            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))

            if let profile {
                HStack {
                    Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(YePlyTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName).font(.subheadline.bold())
                        Text("@\(profile.username) · \(theirCards.count) cartas negociáveis")
                            .font(.caption).foregroundStyle(YePlyTheme.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(YePlyTheme.background)
    }

    @ViewBuilder private var tradeSelectionContent: some View {
        let isOwn = selectionSide == .offered
        let query = isOwn ? ownQuery : theirQuery
        let sort = isOwn ? ownSort : theirSort
        let sourceCards = isOwn ? availableOwnCards : theirCards
        let visibleCards = filteredCards(sourceCards, query: query, sort: sort)

        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(YePlyTheme.secondary)
                TextField("Música, artista ou álbum", text: isOwn ? $ownQuery : $theirQuery)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Menu {
                    ForEach(CardTradeSort.allCases) { option in
                        Button {
                            if isOwn { ownSort = option } else { theirSort = option }
                        } label: {
                            if sort == option { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle.fill").font(.title3)
                }
            }
            .padding(.horizontal, 13).frame(height: 44)
            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            coinSelector(isOwn: isOwn)
                .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(visibleCards) { card in
                        let blocked = isBlocked(card, onOwnSide: isOwn)
                        CardTradeSelectionRow(
                            card: card,
                            isSelected: (isOwn ? offered : requested).contains(card.id),
                            isBlocked: blocked,
                            blockedReason: blocked ? (isOwn ? "O usuário já possui esta carta" : "Você já possui esta carta") : nil
                        ) {
                            toggle(card: card, onOwnSide: isOwn)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
    }

    private func coinSelector(isOwn: Bool) -> some View {
        let amount = isOwn ? offeredCoins : requestedCoins
        let limit = isOwn ? availableCoinBalance : 10_000_000
        return HStack(spacing: 11) {
            Image(systemName: "yensign.circle.fill").font(.title3).foregroundStyle(YePlyTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOwn ? "Moedas que você oferece" : "Moedas que você pede").font(.caption.bold())
                Text(isOwn ? "Saldo: \(availableCoinBalance.formatted())" : "Digite qualquer valor exato")
                    .font(.caption2).foregroundStyle(YePlyTheme.secondary)
            }
            Spacer()
            TextField("0", value: Binding(
                get: { amount },
                set: { setCoins(min(max($0, 0), limit), isOwn: isOwn) }
            ), format: .number.grouping(.never))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.subheadline.monospacedDigit().bold())
            .frame(width: 104)
            .padding(.horizontal, 10).frame(height: 36)
            .background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var tradeFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(offered.count) cartas + \(offeredCoins.formatted()) moedas")
                Spacer()
                Image(systemName: "arrow.right")
                Spacer()
                Text("\(requested.count) cartas + \(requestedCoins.formatted()) moedas")
            }
            .font(.caption2.bold()).foregroundStyle(YePlyTheme.secondary)
            Button(action: create) {
                if isWorking { ProgressView().tint(.black) }
                else { Label("Enviar proposta", systemImage: "paperplane.fill") }
            }
            .font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(YePlyTheme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSubmit: Bool {
        guard profile != nil, !isWorking else { return false }
        return (!offered.isEmpty || offeredCoins > 0) && (!requested.isEmpty || requestedCoins > 0)
    }

    private func filteredCards(_ cards: [CollectibleCardItem], query: String, sort: CardTradeSort) -> [CollectibleCardItem] {
        let unique = Dictionary(grouping: cards, by: \.definitionId).compactMap { $0.value.min { $0.serialNumber < $1.serialNumber } }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = unique.filter {
            clean.isEmpty || $0.title.localizedCaseInsensitiveContains(clean)
                || $0.artistName.localizedCaseInsensitiveContains(clean)
                || $0.albumName.localizedCaseInsensitiveContains(clean)
        }
        return filtered.sorted { left, right in
            switch sort {
            case .newest: return (left.acquiredAt ?? .distantPast) > (right.acquiredAt ?? .distantPast)
            case .title: return left.title.localizedStandardCompare(right.title) == .orderedAscending
            case .artist: return left.artistName.localizedStandardCompare(right.artistName) == .orderedAscending
            case .album: return left.albumName.localizedStandardCompare(right.albumName) == .orderedAscending
            case .rarity: return rarityRank(left.rarity) > rarityRank(right.rarity)
            }
        }
    }

    private func rarityRank(_ rarity: CollectibleCardRarity) -> Int {
        switch rarity {
        case .common, .rare: 0
        case .epic, .legendary: 1
        case .mythic: 2
        }
    }

    private func isBlocked(_ card: CollectibleCardItem, onOwnSide: Bool) -> Bool {
        let otherDefinitions = Set((onOwnSide ? theirCards : availableOwnCards).map(\.definitionId))
        return otherDefinitions.contains(card.definitionId)
    }

    private func toggle(card: CollectibleCardItem, onOwnSide: Bool) {
        guard !isBlocked(card, onOwnSide: onOwnSide) else { return }
        if onOwnSide {
            if offered.contains(card.id) { offered.remove(card.id) }
            else if offered.count < 5 { offered.insert(card.id) }
        } else {
            if requested.contains(card.id) { requested.remove(card.id) }
            else if requested.count < 5 { requested.insert(card.id) }
        }
    }

    private func setCoins(_ amount: Int, isOwn: Bool) {
        if isOwn { offeredCoins = amount } else { requestedCoins = amount }
    }

    @MainActor private func refreshOwnSide() async {
        isLoadingOwnData = true
        defer { isLoadingOwnData = false }
        do { availableOwnCards = try await container.repository.fetchCardInventory() } catch { }
        do {
            let dashboard = try await container.repository.fetchCardDashboard()
            availableCoinBalance = dashboard.coinBalance ?? 0
            offeredCoins = min(offeredCoins, availableCoinBalance)
        } catch { }
    }

    private func search() {
        isWorking = true
        profile = nil
        theirCards = []
        offered.removeAll()
        requested.removeAll()
        Task {
            defer { isWorking = false }
            do {
                let clean = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
                let profiles = try await container.repository.searchProfiles(query: clean)
                guard let match = profiles.first(where: { $0.username.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else { throw YePlyError.message("Usuário não encontrado.") }
                profile = match
                theirCards = try await container.repository.fetchTradeableCards(username: match.username)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func create() {
        guard let profile else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await container.repository.createCardTrade(
                    receiverID: profile.id,
                    offeredCardIDs: Array(offered),
                    requestedCardIDs: Array(requested),
                    offeredCoins: offeredCoins,
                    requestedCoins: requestedCoins
                )
                onCreated()
                dismiss()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private enum TradeSelectionSide: String, CaseIterable, Identifiable {
    case offered, requested
    var id: String { rawValue }
    var title: String { self == .offered ? "Você entrega" : "Você recebe" }
}

private enum CardTradeSort: String, CaseIterable, Identifiable {
    case newest, title, artist, album, rarity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: "Mais recentes"
        case .title: "Nome"
        case .artist: "Artista"
        case .album: "Álbum"
        case .rarity: "Raridade"
        }
    }
}

private struct CardTradeSelectionRow: View {
    let card: CollectibleCardItem
    let isSelected: Bool
    let isBlocked: Bool
    let blockedReason: String?
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 11) {
                CardBrowserArtwork(
                    path: card.artworkPath,
                    seed: card.definitionId.uuidString,
                    title: card.title,
                    albumName: card.albumName,
                    tint: card.rarity.accentColor,
                    cornerRadius: 12
                )
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title).font(.subheadline.bold()).lineLimit(1)
                    Text("\(card.artistName) · \(card.albumName)")
                        .font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                    if let blockedReason {
                        Text(blockedReason).font(.caption2.bold()).foregroundStyle(.orange)
                    } else {
                        Label(card.rarity.title, systemImage: card.rarity.symbolName)
                            .font(.caption2.bold()).foregroundStyle(card.rarity.accentColor)
                    }
                }
                Spacer()
                Image(systemName: isBlocked ? "lock.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3).foregroundStyle(isSelected ? YePlyTheme.accent : YePlyTheme.tertiary)
            }
            .padding(10)
            .background(isSelected ? YePlyTheme.accent.opacity(0.10) : YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? YePlyTheme.accent.opacity(0.8) : .clear))
            .opacity(isBlocked ? 0.52 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
    }
}

private extension Color {
    init?(yeplyHex: String) {
        let clean = yeplyHex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
