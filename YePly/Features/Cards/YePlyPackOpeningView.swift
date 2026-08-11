import SwiftUI

/// Resolve a capa da carta durante a revelação. Para capas do Supabase, passe
/// `container.repository.signedCoverURL(path:)` na integração.
typealias YePlyCardArtworkResolver = (CollectibleCardItem) async -> URL?

struct YePlyOpenedPack: Identifiable, Hashable, Sendable {
    let pack: CardPackSummary
    let cards: [CollectibleCardItem]

    var id: UUID { pack.id }
}

/// Experiência completa para um único pack: rasgo, revelação carta a carta,
/// ação de pular e resumo final.
struct YePlyPackOpeningView: View {
    let pack: CardPackSummary
    let cards: [CollectibleCardItem]
    var artworkResolver: YePlyCardArtworkResolver = YePlyPackOpeningView.defaultArtworkResolver
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = OpeningStage.sealed
    @State private var tearProgress = 0.0
    @State private var dragStarted = false
    @State private var revealIndex = 0

    var body: some View {
        ZStack {
            ambientBackground

            switch stage {
            case .sealed, .tearing:
                sealedPack
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            case .revealing:
                revealView
                    .transition(.asymmetric(insertion: .scale(scale: 0.82).combined(with: .opacity), removal: .opacity))
            case .summary:
                summaryView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .preferredColorScheme(.dark)
        .background(YePlyTheme.background.ignoresSafeArea())
        .interactiveDismissDisabled(stage != .summary)
        .task(id: cards.map(\.id)) {
            await preloadArtwork()
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage == .summary ? "PACK ABERTO" : "ABRINDO PACK")
                    .font(.caption2.bold())
                    .tracking(1.8)
                    .foregroundStyle(YePlyTheme.accent)
                if stage == .revealing, !cards.isEmpty {
                    Text("Carta \(min(revealIndex + 1, cards.count)) de \(cards.count)")
                        .font(.caption)
                        .foregroundStyle(YePlyTheme.secondary)
                }
            }

            Spacer()

            if stage != .summary {
                Button("Pular") { skipToSummary() }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.10), in: Capsule())
                    .accessibilityHint("Mostra todas as cartas imediatamente")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var sealedPack: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            YePlyCardPackView(
                pack: pack,
                state: tearProgress <= 0 ? .sealed : .tearing(progress: tearProgress)
            )
            .frame(maxWidth: 280)
            .scaleEffect(dragStarted && !reduceMotion ? 1.025 : 1)
            .gesture(tearGesture)

            VStack(spacing: 7) {
                Label("Deslize para rasgar", systemImage: "hand.draw.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Puxe o lacre para a direita ou toque no botão")
                    .font(.caption)
                    .foregroundStyle(YePlyTheme.secondary)
            }

            Button(action: openPack) {
                Label(stage == .tearing ? "Abrindo…" : "Rasgar pack", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(stage == .tearing)
            .padding(.horizontal, 24)

            Spacer(minLength: 16)
        }
    }

    private var revealView: some View {
        VStack(spacing: 14) {
            if cards.indices.contains(revealIndex) {
                ScrollView {
                    ResolvedPackCard(card: cards[revealIndex], artworkResolver: artworkResolver)
                        .id(cards[revealIndex].id)
                        .frame(maxWidth: 390)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }

                Button(revealIndex + 1 < cards.count ? "Revelar próxima" : "Ver resumo") {
                    advanceReveal()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            } else {
                ContentUnavailableView(
                    "Pack vazio",
                    systemImage: "shippingbox",
                    description: Text("Nenhuma carta foi retornada para este pack.")
                )
                Button("Fechar", action: onComplete)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summaryView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundStyle(YePlyTheme.accent)
                Text("Cartas guardadas")
                    .font(.title2.bold())
                Text(summarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(YePlyTheme.secondary)
            }
            .padding(.vertical, 18)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(cards) { card in
                        ResolvedPackCard(card: card, style: .compact, artworkResolver: artworkResolver)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onComplete) {
                Text("Ir para a coleção")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var ambientBackground: some View {
        ZStack {
            YePlyTheme.background
            RadialGradient(
                colors: [YePlyTheme.accentSoft.opacity(0.24), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }

    private var tearGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard stage == .sealed else { return }
                dragStarted = true
                tearProgress = min(max(value.translation.width / 180, 0), 1)
            }
            .onEnded { value in
                dragStarted = false
                if value.translation.width > 105 {
                    openPack()
                } else {
                    withAnimation(.snappy) { tearProgress = 0 }
                }
            }
    }

    private func openPack() {
        guard stage == .sealed else { return }
        stage = .tearing
        withAnimation(.easeIn(duration: reduceMotion ? 0.05 : 0.42)) {
            tearProgress = 1
        }

        Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(470))
            }
            guard stage == .tearing else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
                stage = cards.isEmpty ? .summary : .revealing
            }
        }
    }

    private func advanceReveal() {
        if revealIndex + 1 < cards.count {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                revealIndex += 1
            }
        } else {
            withAnimation(.snappy) { stage = .summary }
        }
    }

    private func skipToSummary() {
        withAnimation(reduceMotion ? nil : .snappy) {
            tearProgress = 1
            stage = .summary
        }
    }

    private var summarySubtitle: String {
        cards.count == 1 ? "1 nova carta na sua coleção" : "\(cards.count) novas cartas na sua coleção"
    }

    private func preloadArtwork() async {
        for card in cards {
            guard !Task.isCancelled else { return }
            guard let url = await artworkResolver(card) else { continue }
            _ = await YePlyRemoteImageLoader.shared.data(for: url)
        }
    }

    static func defaultArtworkResolver(for card: CollectibleCardItem) async -> URL? {
        guard let path = card.artworkPath else { return nil }
        return URL(string: path)
    }
}

/// Resultado visual para uma operação de "abrir todos". A abertura dos packs
/// deve ser feita pela camada de serviço antes de apresentar esta tela.
struct YePlyBulkPackOpeningView: View {
    let openedPacks: [YePlyOpenedPack]
    var artworkResolver: YePlyCardArtworkResolver = YePlyPackOpeningView.defaultArtworkResolver
    var onComplete: () -> Void

    @State private var showCards = false

    private var allCards: [CollectibleCardItem] { openedPacks.flatMap(\.cards) }

    var body: some View {
        ZStack {
            YePlyTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [YePlyTheme.accent.opacity(0.18), YePlyTheme.accentSoft.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 480
            )
            .ignoresSafeArea()

            if showCards {
                bulkSummary
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                bulkIntro
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .task(id: allCards.map(\.id)) {
            await preloadArtwork()
        }
    }

    private var bulkIntro: some View {
        VStack(spacing: 26) {
            Spacer()

            ZStack {
                ForEach(Array(openedPacks.prefix(3).enumerated()), id: \.element.id) { entry in
                    YePlyCardPackView(pack: entry.element.pack, compact: true)
                        .frame(width: 175)
                        .rotationEffect(.degrees(Double(entry.offset - 1) * 9))
                        .offset(x: CGFloat(entry.offset - 1) * 34, y: CGFloat(abs(entry.offset - 1)) * 12)
                }
            }
            .frame(height: 300)

            VStack(spacing: 7) {
                Text("\(openedPacks.count) PACKS ABERTOS")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(YePlyTheme.accent)
                Text("Sua maior abertura")
                    .font(.largeTitle.bold())
                Text("\(allCards.count) cartas estão prontas para revelar")
                    .font(.subheadline)
                    .foregroundStyle(YePlyTheme.secondary)
            }

            VStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.56, dampingFraction: 0.82)) { showCards = true }
                } label: {
                    Label("Revelar todas", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Button("Pular animação e guardar", action: onComplete)
                    .font(.subheadline.bold())
                    .foregroundStyle(YePlyTheme.secondary)
                    .frame(height: 42)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var bulkSummary: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("ABERTURA CONCLUÍDA")
                    .font(.caption2.bold())
                    .tracking(1.8)
                    .foregroundStyle(YePlyTheme.accent)
                Text("\(allCards.count) cartas encontradas")
                    .font(.title2.bold())
                raritySummary
            }
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(allCards) { card in
                        ResolvedPackCard(card: card, style: .compact, artworkResolver: artworkResolver)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onComplete) {
                Text("Guardar tudo na coleção")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var raritySummary: some View {
        HStack(spacing: 10) {
            ForEach(CollectibleCardRarity.allCases) { rarity in
                let count = allCards.filter { $0.rarity == rarity }.count
                if count > 0 {
                    Label("\(count)", systemImage: rarity.symbolName)
                        .font(.caption.bold())
                        .foregroundStyle(rarity.accentColor)
                }
            }
        }
        .padding(.top, 5)
    }

    private func preloadArtwork() async {
        for card in allCards {
            guard !Task.isCancelled else { return }
            guard let url = await artworkResolver(card) else { continue }
            _ = await YePlyRemoteImageLoader.shared.data(for: url)
        }
    }
}

/// Botão consistente para iniciar a operação de abertura em lote na tela de
/// packs. Mantém o estado assíncrono fora do componente visual.
struct YePlyOpenAllPacksButton: View {
    let packCount: Int
    let isOpening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title3.bold())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOpening ? "Abrindo packs…" : "Abrir todos")
                        .font(.headline)
                    Text(packCount == 1 ? "1 pack disponível" : "\(packCount) packs disponíveis")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                }
                Spacer()
                if isOpening {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill").font(.title2)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(
                LinearGradient(
                    colors: [YePlyTheme.accent, YePlyTheme.accentSoft],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOpening || packCount == 0)
        .opacity(packCount == 0 ? 0.45 : 1)
    }
}

private enum OpeningStage: Equatable {
    case sealed
    case tearing
    case revealing
    case summary
}

private struct ResolvedPackCard: View {
    let card: CollectibleCardItem
    var style: CollectibleCardStyle = .detailed
    let artworkResolver: YePlyCardArtworkResolver

    @State private var artworkURL: URL?

    init(
        card: CollectibleCardItem,
        style: CollectibleCardStyle = .detailed,
        artworkResolver: @escaping YePlyCardArtworkResolver
    ) {
        self.card = card
        self.style = style
        self.artworkResolver = artworkResolver
        let directURL = card.artworkPath
            .flatMap { URL(string: $0) }
            .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        _artworkURL = State(initialValue: directURL)
    }

    var body: some View {
        CollectibleCardView(model: displayModel, style: style)
            .task(id: card.artworkPath) {
                if artworkURL != nil { return }
                artworkURL = await artworkResolver(card)
            }
    }

    private var displayModel: CollectibleCardDisplayModel {
        CollectibleCardDisplayModel(
            id: card.id.uuidString,
            title: card.title,
            artistName: card.artistName,
            albumName: card.albumName,
            rarity: card.rarity,
            serialNumber: card.serialNumber,
            artworkURL: artworkURL
        )
    }
}

#if DEBUG
#Preview("Botão abrir todos") {
    YePlyOpenAllPacksButton(packCount: 8, isOpening: false) {}
        .padding()
        .yeplyBackground()
}
#endif
