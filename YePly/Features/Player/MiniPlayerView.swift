import Foundation
import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    let onOpen: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 11) {
                        PlayerArtworkView(track: track, artworkPath: player.currentArtworkPath)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(track.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 36, height: 36)
                }
                Button(action: player.next) {
                    Image(systemName: "forward.fill").frame(width: 32, height: 36)
                }
                .disabled(!player.hasNext)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(alignment: .top) {
                Capsule().fill(.white.opacity(0.32)).frame(width: 28, height: 3).padding(.top, 3)
            }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Capsule().fill(YePlyTheme.accent)
                        .frame(width: geometry.size.width * player.progress, height: 2)
                }
                .frame(height: 2)
            }
        }
    }
}

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var downloadManager = TrackFileDownloadManager()
    @State private var showingQueue = false
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var commentMoment: PlayerCommentMoment?
    @State private var isCurrentArtistVerified = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.13, blue: 0.20), YePlyTheme.background, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let track = player.currentTrack {
                ScrollView {
                    VStack(spacing: 0) {
                        topBar(track: track)

                        PlayerArtworkView(track: track, artworkPath: player.currentArtworkPath)
                            .frame(maxWidth: 380)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 35, y: 24)
                            .padding(.horizontal, 28)
                            .padding(.top, 20)

                        VStack(spacing: 24) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(track.title)
                                        .font(.title2.bold()).lineLimit(2)
                                    HStack(spacing: 5) {
                                        Text(track.artistName).font(.subheadline).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                                        if isCurrentArtistVerified { VerifiedArtistBadge() }
                                    }
                                }
                                Spacer()
                                Image(systemName: "waveform.circle.fill")
                                    .font(.title2).foregroundStyle(YePlyTheme.accent)
                            }

                            VStack(spacing: 7) {
                                WaveformScrubber(samples: player.currentWaveform, progress: isScrubbing ? scrubValue : player.progress) { value, editing in
                                    scrubValue = value
                                    isScrubbing = editing
                                    if !editing { player.seek(to: value) }
                                }
                                HStack {
                                    Text(formatTime(isScrubbing ? scrubValue * player.duration : player.elapsedTime))
                                    Spacer()
                                    Text("-\(formatTime(max(0, player.duration - (isScrubbing ? scrubValue * player.duration : player.elapsedTime))))")
                                }
                                .font(.caption2.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary)
                            }

                            if !player.isPlaying {
                                Button {
                                    commentMoment = PlayerCommentMoment(track: track, seconds: player.elapsedTime)
                                } label: {
                                    Label("Comentar em \(formatTime(player.elapsedTime))", systemImage: "bubble.left.and.text.bubble.right")
                                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 46)
                                        .background(YePlyTheme.elevatedStrong, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                            }

                            HStack(spacing: 0) {
                                Button(action: player.toggleRepeatOne) {
                                    Image(systemName: player.isRepeatingOne ? "repeat.1" : "repeat")
                                        .foregroundStyle(player.isRepeatingOne ? YePlyTheme.accent : YePlyTheme.secondary)
                                        .frame(maxWidth: .infinity)
                                }
                                Button(action: player.previous) {
                                    Image(systemName: "backward.end.fill").font(.title).frame(maxWidth: .infinity)
                                }
                                .disabled(!player.hasPrevious)
                                Button(action: player.toggle) {
                                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 72, height: 72)
                                        .background(.white, in: Circle())
                                }
                                Button(action: player.next) {
                                    Image(systemName: "forward.end.fill").font(.title).frame(maxWidth: .infinity)
                                }
                                .disabled(!player.hasNext)
                                Button { showingQueue = true } label: {
                                    Image(systemName: "list.bullet").frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)

                            Button { showingQueue = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                        .foregroundStyle(YePlyTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("A seguir").font(.subheadline.weight(.semibold))
                                        Text(queueDescription).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(YePlyTheme.tertiary)
                                }
                                .padding(16)
                                .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                        .padding(.bottom, 34)
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: player.progress) { _, value in if !isScrubbing { scrubValue = value } }
                .task(id: track.artistName) {
                    guard offlineLibrary.isConnected else { return }
                    let artists = try? await container.repository.searchArtists(query: track.artistName)
                    isCurrentArtistVerified = artists?.first(where: { $0.artistName.localizedCaseInsensitiveCompare(track.artistName) == .orderedSame })?.isVerified ?? false
                }
                .sheet(isPresented: $showingQueue) { PlaybackQueueView() }
                .sheet(item: $commentMoment) { moment in TrackCommentsView(track: moment.track, initialTimestamp: moment.seconds) }
                .sheet(item: $downloadManager.exportedFile) { file in ActivityShareSheet(items: [file.url]) }
                .alert("Não foi possível salvar", isPresented: Binding(
                    get: { downloadManager.errorMessage != nil },
                    set: { if !$0 { downloadManager.errorMessage = nil } }
                )) { Button("OK", role: .cancel) {} } message: { Text(downloadManager.errorMessage ?? "") }
            }
        }
    }

    @ViewBuilder
    private func topBar(track: Track) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.headline)
                    .frame(width: 42, height: 42).background(.black.opacity(0.18), in: Circle())
            }
            Spacer()
            VStack(spacing: 3) {
                Text("TOCANDO AGORA").font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.tertiary)
                Text(player.currentCollectionTitle ?? track.albumName ?? "YePly").font(.caption.weight(.semibold)).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Baixar ou compartilhar MP3", systemImage: "arrow.down.circle") {
                    Task { await downloadManager.prepare(track: track, repository: container.repository, localURL: offlineLibrary.localAudioURL(for: track)) }
                }
                Button("Ver fila de reprodução", systemImage: "list.bullet") { showingQueue = true }
                Button("Comentar neste momento", systemImage: "bubble.left") {
                    commentMoment = PlayerCommentMoment(track: track, seconds: player.elapsedTime)
                }
            } label: {
                Image(systemName: "ellipsis").font(.headline)
                    .frame(width: 42, height: 42).background(.black.opacity(0.18), in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var queueDescription: String {
        guard let next = player.upcomingTracks.first else { return "Nenhuma música depois desta" }
        let remaining = player.upcomingTracks.count
        return remaining == 1 ? next.title : "\(next.title) e mais \(remaining - 1)"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct PlayerCommentMoment: Identifiable {
    let id = UUID()
    let track: Track
    let seconds: Double
}

private struct PlaybackQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentTrack {
                    Section("Tocando agora") {
                        queueRow(current, isCurrent: true)
                    }
                }
                Section("Próximas") {
                    if player.upcomingTracks.isEmpty {
                        ContentUnavailableView("Fim da fila", systemImage: "music.note", description: Text("Adicione músicas pelo menu de três pontos."))
                    } else {
                        ForEach(Array(player.upcomingTracks.enumerated()), id: \.element.id) { index, track in
                            Button { player.playFromQueue(track); dismiss() } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary).frame(width: 22)
                                    queueRow(track, isCurrent: false)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { player.removeFromQueue(track) } label: {
                                    Label("Remover", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(YePlyTheme.background)
            .navigationTitle("Fila")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                if !player.upcomingTracks.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Limpar") { player.clearUpcoming() } }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func queueRow(_ track: Track, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(YePlyTheme.elevatedStrong)
                Image(systemName: isCurrent && player.isPlaying ? "waveform" : "music.note")
                    .foregroundStyle(isCurrent ? YePlyTheme.accent : YePlyTheme.secondary)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(isCurrent ? YePlyTheme.accent : .white).lineLimit(1)
                Text(track.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.formattedDuration).font(.caption.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary)
        }
    }
}

struct PlayerArtworkView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    let track: Track
    let artworkPath: String?
    @State private var coverURL: URL?
    @State private var localCoverImage: UIImage?

    var body: some View {
        Group {
            if let localCoverImage {
                Image(uiImage: localCoverImage).resizable().scaledToFill()
            } else if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { fallback }
                }
            } else { fallback }
        }
        .clipped()
        .task(id: "\(artworkPath ?? track.artworkPath ?? "none")-\(offlineLibrary.isTrackDownloaded(track))") {
            coverURL = nil
            localCoverImage = nil
            if let localURL = offlineLibrary.localCoverURL(for: track.playlistId) {
                localCoverImage = UIImage(contentsOfFile: localURL.path)
            } else if offlineLibrary.isConnected, let path = artworkPath ?? track.artworkPath {
                coverURL = try? await container.repository.signedCoverURL(path: path)
            }
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [YePlyTheme.accent, YePlyTheme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "waveform").font(.system(size: 42, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
        }
    }
}

struct ExportedTrackFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class TrackFileDownloadManager: ObservableObject {
    @Published var exportedFile: ExportedTrackFile?
    @Published var isDownloading = false
    @Published private(set) var downloadingTrackID: UUID?
    @Published var errorMessage: String?

    func prepare(track: Track, repository: any MusicRepository, localURL: URL? = nil) async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadingTrackID = track.id
        errorMessage = nil
        defer { isDownloading = false; downloadingTrackID = nil }
        do {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(safeFilename(for: track))
            try? FileManager.default.removeItem(at: destination)
            if let localURL {
                try FileManager.default.copyItem(at: localURL, to: destination)
            } else {
                let remoteURL = try await repository.signedAudioURL(for: track)
                let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw YePlyError.message("O servidor recusou o download (código \(http.statusCode)).")
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            }
            exportedFile = ExportedTrackFile(url: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func safeFilename(for track: Track) -> String {
        let raw = "\(track.artistName) - \(track.title)"
        let clean = raw.folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(clean.isEmpty ? "YePly" : clean).mp3"
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
