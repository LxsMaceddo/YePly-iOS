import SwiftUI

@MainActor
private final class CardYePlyTrackSearchModel: ObservableObject {
    @Published var results: [PublicTrackRankingItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func search(_ query: String, repository: any MusicRepository) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { results = []; return }
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await repository.searchPublicTracks(query: clean, limit: 40)
            errorMessage = nil
        } catch let error where error.isYePlyCancellation { return }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Procura a música exclusivamente no catálogo de playlists públicas do YePly.
struct CardYePlyTrackSearchView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var model = CardYePlyTrackSearchModel()
    @State private var query: String
    private let card: CollectibleCardItem

    init(card: CollectibleCardItem) {
        self.card = card
        _query = State(initialValue: card.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField

                if model.isLoading && model.results.isEmpty {
                    ProgressView("Procurando no YePly…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if model.results.isEmpty {
                    ContentUnavailableView(
                        "Ainda não está em uma playlist",
                        systemImage: "music.note.list",
                        description: Text("Tente pesquisar pelo título ou pelo artista. Só aparecem músicas de playlists públicas.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)
                } else {
                    Text("RESULTADOS NO YEPLY")
                        .font(.caption2.bold())
                        .tracking(1.6)
                        .foregroundStyle(YePlyTheme.tertiary)

                    LazyVStack(spacing: 10) {
                        ForEach(model.results) { item in
                            Button { play(item) } label: { resultRow(item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 36)
        }
        .navigationTitle("Buscar no YePly")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.search(query, repository: container.repository)
        }
        .alert("Não foi possível buscar", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .yeplyBackground()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(YePlyTheme.tertiary)
            TextField("Música, artista ou playlist", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(YePlyTheme.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func resultRow(_ item: PublicTrackRankingItem) -> some View {
        HStack(spacing: 12) {
            PlayerArtworkView(track: item.track, artworkPath: item.playlistCoverPath)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                Text(item.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                Label(item.playlistTitle, systemImage: "music.note.list")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(YePlyTheme.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Image(systemName: player.currentTrack?.id == item.id && player.isPlaying ? "waveform" : "play.fill")
                .foregroundStyle(YePlyTheme.accent)
                .frame(width: 34, height: 34)
                .background(YePlyTheme.elevatedStrong, in: Circle())
        }
        .padding(10)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func play(_ item: PublicTrackRankingItem) {
        Task {
            await player.play(
                item.track,
                queue: model.results.map(\.track),
                repository: container.repository,
                artworkPath: item.playlistCoverPath,
                collectionTitle: item.playlistTitle
            )
        }
    }
}
