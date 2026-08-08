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
        catch let error where error.isYePlyCancellation { return }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ track: Track, repository: any MusicRepository) async {
        do { try await repository.deleteTrack(track); tracks.removeAll { $0.id == track.id } }
        catch { errorMessage = error.localizedDescription }
    }

    func toggleLike(_ track: Track, repository: any MusicRepository) async {
        do {
            let liked = try await repository.toggleTrackLike(trackID: track.id)
            guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
            let previous = tracks[index].isLiked ?? false
            tracks[index].isLiked = liked
            tracks[index].likeCount = max(0, (tracks[index].likeCount ?? 0) + (liked && !previous ? 1 : !liked && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }

    func useOffline(_ tracks: [Track]) {
        self.tracks = tracks
        isLoading = false
        errorMessage = nil
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var model = PlaylistDetailViewModel()
    @StateObject private var downloadManager = TrackFileDownloadManager()
    @State private var showingUpload = false
    @State private var showingEdit = false
    @State private var informationTrack: Track?
    @State private var commentsTrack: Track?
    @State private var isPlaylistFollowed: Bool
    @State private var playlistFollowerCount: Int
    @State private var playlistViewCount: Int
    @State private var didRecordView = false
    @State private var isArtistVerified = false
    let playlist: Playlist

    private var canManage: Bool { playlist.ownerId == session.userID || session.isAdmin }

    init(playlist: Playlist) {
        self.playlist = playlist
        _isPlaylistFollowed = State(initialValue: playlist.isFollowed ?? false)
        _playlistFollowerCount = State(initialValue: playlist.followerCount ?? 0)
        _playlistViewCount = State(initialValue: playlist.viewCount ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 18) {
                    PlaylistArtworkView(playlist: playlist).frame(maxWidth: 310).shadow(color: .black.opacity(0.4), radius: 26, y: 16)
                    VStack(spacing: 7) {
                        Text(playlist.title).font(.system(size: 29, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                        HStack(spacing: 5) {
                            Text(playlist.artistName).font(.subheadline).foregroundStyle(YePlyTheme.secondary)
                            if isArtistVerified { VerifiedArtistBadge() }
                        }
                        if let summary = playlist.summary { Text(summary).font(.footnote).foregroundStyle(YePlyTheme.secondary).multilineTextAlignment(.center).padding(.top, 3) }
                        HStack(spacing: 14) {
                            Label("\(playlistViewCount)", systemImage: "eye.fill")
                            Label("\(playlistFollowerCount)", systemImage: "person.2.fill")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(YePlyTheme.tertiary).padding(.top, 3)
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
                        Menu {
                            if !canManage {
                                Button {
                                    Task { await togglePlaylistFollow() }
                                } label: {
                                    Label(isPlaylistFollowed ? "Deixar de seguir playlist" : "Seguir playlist", systemImage: isPlaylistFollowed ? "person.badge.minus" : "person.badge.plus")
                                }
                                .disabled(!offlineLibrary.isConnected)
                                Divider()
                            }
                            switch offlineLibrary.state(for: playlist.id) {
                            case .notDownloaded, .failed:
                                Button {
                                    Task { await offlineLibrary.downloadPlaylist(playlist, tracks: model.tracks, repository: container.repository) }
                                } label: {
                                    Label("Baixar para ouvir offline", systemImage: "arrow.down.circle")
                                }
                                .disabled(model.tracks.isEmpty || !offlineLibrary.isConnected)
                            case .downloading(let progress):
                                Button {} label: {
                                    Label("Baixando… \(Int(progress * 100))%", systemImage: "arrow.down.circle")
                                }
                                .disabled(true)
                            case .downloaded:
                                Button {
                                    Task { await offlineLibrary.downloadPlaylist(playlist, tracks: model.tracks, repository: container.repository) }
                                } label: {
                                    Label("Atualizar download", systemImage: "arrow.clockwise.circle")
                                }
                                .disabled(model.tracks.isEmpty || !offlineLibrary.isConnected)
                                Button(role: .destructive) { offlineLibrary.removeDownload(for: playlist.id) } label: {
                                    Label("Remover download", systemImage: "trash")
                                }
                            }
                            if canManage {
                                Divider()
                                Button("Editar playlist", systemImage: "pencil") { showingEdit = true }.disabled(!offlineLibrary.isConnected)
                                Button("Adicionar MP3", systemImage: "plus") { showingUpload = true }.disabled(!offlineLibrary.isConnected)
                            }
                        } label: {
                            ZStack {
                                Image(systemName: "ellipsis")
                                if case .downloading(let progress) = offlineLibrary.state(for: playlist.id) {
                                    Circle().trim(from: 0, to: progress).stroke(YePlyTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.25), value: progress)
                                }
                            }
                            .frame(width: 46, height: 46)
                            .background(YePlyTheme.elevatedStrong, in: Circle())
                        }
                    }

                    offlineStatus
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
                                isAvailableOffline: offlineLibrary.isTrackDownloaded(track),
                                isDownloading: downloadManager.downloadingTrackID == track.id,
                                canUseSocial: offlineLibrary.isConnected,
                                onPlay: { play(track) },
                                onPlayNext: {
                                    player.playNext(track, repository: container.repository, artworkPath: playlist.coverPath, collectionTitle: playlist.title)
                                },
                                onAddToQueue: {
                                    player.addToQueue(track, repository: container.repository, artworkPath: playlist.coverPath, collectionTitle: playlist.title)
                                },
                                onDownload: {
                                    Task { await downloadManager.prepare(track: track, repository: container.repository, localURL: offlineLibrary.localAudioURL(for: track)) }
                                },
                                onInformation: { informationTrack = track },
                                onLike: { Task { await model.toggleLike(track, repository: container.repository) } },
                                onComments: { commentsTrack = track },
                                onDelete: canManage && offlineLibrary.isConnected ? {
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
        .sheet(item: $commentsTrack, onDismiss: { Task { await loadTracks() } }) { track in TrackCommentsView(track: track) }
        .sheet(item: $downloadManager.exportedFile) { file in ActivityShareSheet(items: [file.url]) }
        .task(id: detailLoadKey) { await loadTracks() }
        .task(id: playlist.id) { await recordView() }
        .task(id: playlist.artistName) {
            guard offlineLibrary.isConnected else { return }
            let artists = try? await container.repository.searchArtists(query: playlist.artistName)
            isArtistVerified = artists?.first(where: { $0.artistName.localizedCaseInsensitiveCompare(playlist.artistName) == .orderedSame })?.isVerified ?? false
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .alert("Não foi possível baixar", isPresented: Binding(get: { downloadManager.errorMessage != nil }, set: { if !$0 { downloadManager.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(downloadManager.errorMessage ?? "") }
        .alert("Download offline", isPresented: Binding(get: { offlineLibrary.errorMessage != nil }, set: { if !$0 { offlineLibrary.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(offlineLibrary.errorMessage ?? "") }
        .yeplyBackground()
    }

    @ViewBuilder
    private var offlineStatus: some View {
        switch offlineLibrary.state(for: playlist.id) {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Preparando para ouvir offline", systemImage: "arrow.down.circle")
                    Spacer()
                    Text("\(Int(progress * 100))%").monospacedDigit().contentTransition(.numericText())
                }
                .font(.caption.weight(.semibold))
                ProgressView(value: progress).tint(YePlyTheme.accent).animation(.easeInOut(duration: 0.25), value: progress)
            }
            .padding(14)
            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        case .downloaded:
            Label("Disponível offline neste iPhone", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(YePlyTheme.accent)
                .padding(.horizontal, 14).frame(height: 40)
                .background(YePlyTheme.accent.opacity(0.1), in: Capsule())
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.leading)
        case .notDownloaded:
            EmptyView()
        }
    }

    private var detailLoadKey: String {
        "\(offlineLibrary.isConnected)-\(offlineLibrary.isPlaylistDownloaded(playlist.id))"
    }

    private func loadTracks() async {
        if offlineLibrary.isOfflineMode {
            model.useOffline(offlineLibrary.tracks(for: playlist.id) ?? [])
        } else {
            await model.load(playlistID: playlist.id, repository: container.repository)
            if model.errorMessage != nil, let cached = offlineLibrary.tracks(for: playlist.id) { model.useOffline(cached) }
        }
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

    private func togglePlaylistFollow() async {
        do {
            let previous = isPlaylistFollowed
            let followed = try await container.repository.togglePlaylistFollow(playlistID: playlist.id)
            isPlaylistFollowed = followed
            playlistFollowerCount = max(0, playlistFollowerCount + (followed && !previous ? 1 : !followed && previous ? -1 : 0))
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func recordView() async {
        guard !didRecordView, offlineLibrary.isConnected else { return }
        didRecordView = true
        do { playlistViewCount = try await container.repository.recordPlaylistView(playlistID: playlist.id) }
        catch { didRecordView = false }
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
    let isAvailableOffline: Bool
    let isDownloading: Bool
    let canUseSocial: Bool
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onDownload: () -> Void
    let onInformation: () -> Void
    let onLike: () -> Void
    let onComments: () -> Void
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAvailableOffline {
                Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(YePlyTheme.accent)
            }
            Button(action: onComments) {
                Label("\(track.commentCount ?? 0)", systemImage: "bubble.left")
                    .labelStyle(.titleAndIcon).font(.caption2).foregroundStyle(YePlyTheme.tertiary)
            }
            .buttonStyle(.plain).disabled(!canUseSocial)
            .accessibilityLabel("Comentários, \(track.commentCount ?? 0)")
            Text(track.formattedDuration).font(.caption.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary)

            Menu {
                Button("Tocar agora", systemImage: "play.fill", action: onPlay)
                Button("Tocar a seguir", systemImage: "text.line.first.and.arrowtriangle.forward", action: onPlayNext)
                Button("Adicionar ao final da fila", systemImage: "text.badge.plus", action: onAddToQueue)
                Divider()
                Button(track.isLiked == true ? "Remover curtida" : "Curtir música", systemImage: track.isLiked == true ? "heart.slash" : "heart", action: onLike)
                    .disabled(!canUseSocial)
                Button("Comentários (\(track.commentCount ?? 0))", systemImage: "bubble.left", action: onComments)
                    .disabled(!canUseSocial)
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
                    LabeledContent("Curtidas", value: "\(track.likeCount ?? 0)")
                    LabeledContent("Comentários", value: "\(track.commentCount ?? 0)")
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
