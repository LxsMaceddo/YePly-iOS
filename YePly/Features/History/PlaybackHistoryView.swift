import SwiftUI

@MainActor
private final class PlaybackHistoryViewModel: ObservableObject {
    @Published var items: [PlaybackHistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do { items = try await repository.fetchPlaybackHistory(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func clear(repository: any MusicRepository) async {
        do { try await repository.clearPlaybackHistory(); items.removeAll() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct PlaybackHistoryView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var model = PlaybackHistoryViewModel()
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if offlineLibrary.isOfflineMode {
                ContentUnavailableView("Histórico indisponível offline", systemImage: "clock.arrow.circlepath", description: Text("Conecte-se para sincronizar o histórico da sua conta."))
            } else if model.isLoading && model.items.isEmpty {
                ProgressView("Carregando histórico…")
            } else if model.items.isEmpty {
                ContentUnavailableView("Nenhuma reprodução ainda", systemImage: "music.note.list", description: Text("As músicas tocadas aparecerão aqui."))
            } else {
                List(model.items) { item in
                    Button { play(item) } label: {
                        HStack(spacing: 13) {
                            PlayerArtworkView(track: item.track, artworkPath: item.playlistCoverPath)
                                .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                                Text("\(relativeDate(item.lastPlayedAt)) · \(item.playCount)x")
                                    .font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                            }
                            Spacer()
                            Image(systemName: "play.fill").foregroundStyle(YePlyTheme.accent)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(YePlyTheme.elevated)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(YePlyTheme.background)
        .navigationTitle("Histórico")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Limpar", role: .destructive) { confirmingClear = true } }
            }
        }
        .task { if offlineLibrary.isConnected { await model.load(repository: container.repository) } }
        .refreshable { await model.load(repository: container.repository) }
        .confirmationDialog("Limpar todo o histórico?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Limpar histórico", role: .destructive) { Task { await model.clear(repository: container.repository) } }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Não foi possível carregar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private func play(_ item: PlaybackHistoryItem) {
        let tracks = model.items.map(\.track)
        Task { await player.play(item.track, queue: tracks, repository: container.repository, artworkPath: item.playlistCoverPath, collectionTitle: item.playlistTitle) }
    }

    private func relativeDate(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}
