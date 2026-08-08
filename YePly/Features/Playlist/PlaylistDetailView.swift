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
    @State private var showingUpload = false
    @State private var showingEdit = false
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
                        Button { if let first = model.tracks.first { Task { await player.play(first, queue: model.tracks, repository: container.repository) } } } label: {
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
                            TrackRow(index: index + 1, track: track, isCurrent: player.currentTrack?.id == track.id, isPlaying: player.isPlaying) {
                                Task { await player.play(track, queue: model.tracks, repository: container.repository) }
                            }
                            .contextMenu {
                                if canManage { Button("Excluir faixa", systemImage: "trash", role: .destructive) { Task { await model.delete(track, repository: container.repository) } } }
                            }
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
        .task { await model.load(playlistID: playlist.id, repository: container.repository) }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .yeplyBackground()
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                Image(systemName: "ellipsis").foregroundStyle(YePlyTheme.tertiary)
            }.padding(.vertical, 13)
        }.buttonStyle(.plain)
    }
}
