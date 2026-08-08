import SwiftUI

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(playlistID: UUID, repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do { tracks = try await repository.fetchTracks(playlistID: playlistID); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ track: Track, repository: any MusicRepository) async {
        do { try await repository.deleteTrack(track); tracks.removeAll { $0.id == track.id } }
        catch { errorMessage = error.localizedDescription }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var model = PlaylistDetailViewModel()
    @StateObject private var downloadManager = TrackFileDownloadManager()
    @State private var showingUpload = false
    @State private var showingEdit = false
    @State private var informationTrack: Track?
    let playlist: Playlist

    private var canManage: Bool { playlist.ownerId == session.userID || session.isAdmin }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 18) {
                    PlaylistArtworkView(playlist: playlist).frame(maxWidth: 310).shadow(color: .black.opacity(0.4), radius: 26, y: 16)
                    VStack(spacing: 7) {
                        Text(playlist.title).font(.system(size: 29, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                        Text(playlist.artistName).font(.subheadline).foregroundStyle(YePlyTheme.secondary)
                        if let summary = playlist.summary { Text(summary).font(.footnote).foregroundStyle(YePlyTheme.secondary).multilineTextAlignment(.center).padding(.top, 3) }
                    }
                    HStack(spacing: 12) {
                        Button { if let first = model.tracks.first { play(first) } } label: {
                            Label("Reproduzir", systemImage: "play.fill").fontWeight(.bold).foregroundStyle(.black).padding(.horizontal, 22).frame(height: 46).background(.white, in: Capsule())
                        }
                        .disabled(model.tracks.isEmpty)

                        if playlist.visibility != .privateAccess {
                            ShareLink(item: shareURL) {
                                Image(systemName: "square.and.arrow.up").frame(width: 46, height: 46).background(YePlyTheme.elevatedStrong, in: Circle())
                            }
                        } else {
                            Image(systemName: "lock.fill").foregroundStyle(YePlyTheme.secondary).frame(width: 46, height: 46).background(YePlyTheme.elevatedStrong, in: Circle())
                        }
                        if canManage {
                            Menu {
                                Button("Editar playlist", systemImage: "pencil") { showingEdit = true }
                                Button("Adicionar MP3", systemImage: "plus") { showingUpload = true }
                            } label: { Image(systemName: "ellipsis").frame(width: 46, height: 46).background(YePlyTheme.elevatedStrong, in: Circle()) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Text("FAIXAS").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(YePlyTheme.tertiary)
                    Spacer()
                    Text("\(model.tracks.count)").font(.caption).foregroundStyle(YePlyTheme.tertiary)
                }

                if model.isLoading && model.tracks.isEmpty { ProgressView().frame(maxWidth: .infinity).padding() }
                else if model.tracks.isEmpty {
                    Button { showingUpload = canManage } label: {
                        VStack(spacing: 10) { Image(systemName: "waveform.badge.plus").font(.title2); Text(canManage ? "Adicionar o primeiro MP3" : "Nenhuma faixa publicada") }
                            .foregroundStyle(YePlyTheme.secondary).frame(maxWidth: .infinity).padding(.vertical, 34).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
                    }.disabled(!canManage)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                index: index + 1,
                                track: track,
                                isCurrent: player.currentTrack?.id == track.id,
                                isPlaying: player.isPlaying,
                                isDownloading: downloadManager.downloadingTrackID == track.id,
                                onPlay: { play(track) },
                                onPlayNext: {
                                    player.playNext(track, repository: container.repository, artworkPath: playlist.coverPath, collectionTitle: playlist.title)
                                },
                                onAddToQueue: {
                                    player.addToQueue(track, repository: container.repository, artworkPath: playlist.coverPath, collectionTitle: playlist.title)
                                },
                                onDownload: {
                                    Task { await downloadManager.prepare(track: track, repository: container.repository) }
                                },
                                onInformation: { informationTrack = track },
                                onDelete: canManage ? {
                                    Task { await model.delete(track, repository: container.repository) }
                                } : nil
                            )
                            if track.id != model.tracks.last?.id { Divider().overlay(YePlyTheme.line).padding(.leading, 48) }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { YePlyLogo(size: 25) } }
        .sheet(isPresented: $showingUpload) { UploadTrackView(playlist: playlist, nextPosition: model.tracks.count) { Task { await model.load(playlistID: playlist.id, repository: container.repository) } } }
        .sheet(isPresented: $showingEdit) { PlaylistEditorView(playlist: playlist) }
        .sheet(item: $informationTrack) { track in TrackInformationView(track: track, playlist: playlist) }
        .sheet(item: $downloadManager.exportedFile) { file in ActivityShareSheet(items: [file.url]) }
        .task { await model.load(playlistID: playlist.id, repository: container.repository) }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .alert("Não foi possível baixar", isPresented: Binding(get: { downloadManager.errorMessage != nil }, set: { if !$0 { downloadManager.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(downloadManager.errorMessage ?? "") }
        .yeplyBackground()
    }

    private func play(_ track: Track) {
        Task {
            await player.play(
                track,
                queue: model.tracks,
                repository: container.repository,
                artworkPath: playlist.coverPath,
                collectionTitle: playlist.title
            )
        }
    }

    private var shareURL: URL {
        AppConfiguration.current.universalLinkBase.appending(path: playlist.shareToken.uuidString.lowercased())
    }
}

private struct TrackRow: View {
    let index: Int
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isDownloading: Bool
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onDownload: () -> Void
    let onInformation: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onPlay) {
                HStack(spacing: 13) {
                    ZStack {
                        Text("\(index)").font(.caption).foregroundStyle(YePlyTheme.tertiary).opacity(isCurrent ? 0 : 1)
                        if isCurrent { Image(systemName: isPlaying ? "waveform" : "pause.fill").foregroundStyle(YePlyTheme.accent).symbolEffect(.variableColor.iterative, isActive: isPlaying) }
                    }.frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(isCurrent ? YePlyTheme.accent : .white).lineLimit(1)
                        Text(track.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(track.formattedDuration).font(.caption.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Tocar agora", systemImage: "play.fill", action: onPlay)
                Button("Tocar a seguir", systemImage: "text.line.first.and.arrowtriangle.forward", action: onPlayNext)
                Button("Adicionar ao final da fila", systemImage: "text.badge.plus", action: onAddToQueue)
                Divider()
                Button("Baixar ou salvar MP3", systemImage: "arrow.down.circle", action: onDownload)
                Button("Informações da música", systemImage: "info.circle", action: onInformation)
                if let onDelete {
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Excluir faixa", systemImage: "trash")
                    }
                }
            } label: {
                ZStack {
                    if isDownloading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "ellipsis").foregroundStyle(YePlyTheme.tertiary) }
                }
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
            }
            .disabled(isDownloading)
        }
        .padding(.vertical, 7)
    }
}

private struct TrackInformationView: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let playlist: Playlist

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        PlaylistArtworkView(playlist: playlist).frame(width: 82, height: 82)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.headline).lineLimit(2)
                            Text(track.artistName).foregroundStyle(YePlyTheme.secondary)
                            Text(track.albumName ?? playlist.title).font(.caption).foregroundStyle(YePlyTheme.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section("Detalhes") {
                    LabeledContent("Duração", value: track.formattedDuration)
                    LabeledContent("Posição", value: "\(track.position + 1)")
                    if let size = track.fileSizeBytes { LabeledContent("Tamanho", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                    LabeledContent("Formato", value: "MP3")
                }
            }
            .scrollContentBackground(.hidden)
            .background(YePlyTheme.background)
            .navigationTitle("Informações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
