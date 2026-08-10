import SwiftUI

@MainActor
private final class TrackCommentsViewModel: ObservableObject {
    @Published var comments: [TrackComment] = []
    @Published var summary = TrackSocialSummary(likeCount: 0, commentCount: 0, isLiked: false)
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?

    func load(trackID: UUID, repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let comments = repository.fetchTrackComments(trackID: trackID)
            async let summary = repository.fetchTrackSocialSummary(trackID: trackID)
            self.comments = try await comments
            self.summary = try await summary
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func send(trackID: UUID, userID: UUID, body: String, timestampSeconds: Double?, repository: any MusicRepository) async -> Bool {
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty, cleanBody.count <= 1_000 else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await repository.addTrackComment(trackID: trackID, userID: userID, body: cleanBody, timestampSeconds: timestampSeconds)
            await load(trackID: trackID, repository: repository)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func toggleTrackLike(trackID: UUID, repository: any MusicRepository) async {
        do {
            let previous = summary.isLiked
            let liked = try await repository.toggleTrackLike(trackID: trackID)
            summary = TrackSocialSummary(
                likeCount: max(0, summary.likeCount + (liked && !previous ? 1 : !liked && previous ? -1 : 0)),
                commentCount: summary.commentCount,
                isLiked: liked
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleCommentLike(_ comment: TrackComment, repository: any MusicRepository) async {
        do {
            let liked = try await repository.toggleCommentLike(commentID: comment.id)
            guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
            let previous = comments[index].isLiked
            comments[index].isLiked = liked
            comments[index].likeCount = max(0, comments[index].likeCount + (liked && !previous ? 1 : !liked && previous ? -1 : 0))
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ comment: TrackComment, trackID: UUID, repository: any MusicRepository) async {
        do {
            try await repository.deleteTrackComment(commentID: comment.id)
            comments.removeAll { $0.id == comment.id }
            summary = TrackSocialSummary(likeCount: summary.likeCount, commentCount: max(0, summary.commentCount - 1), isLiked: summary.isLiked)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct TrackCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var model = TrackCommentsViewModel()
    @State private var draft = ""
    @State private var selectedTimestamp: Double?
    let track: Track

    init(track: Track, initialTimestamp: Double? = nil) {
        self.track = track
        _selectedTimestamp = State(initialValue: initialTimestamp.map { max(0, $0.rounded()) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if offlineLibrary.isOfflineMode {
                    ContentUnavailableView("Comentários indisponíveis offline", systemImage: "wifi.slash", description: Text("Conecte-se para conversar e curtir esta música."))
                } else {
                    VStack(spacing: 0) {
                        socialHeader
                        Divider().overlay(YePlyTheme.line)
                        commentsList
                        Divider().overlay(YePlyTheme.line)
                        composer
                    }
                }
            }
            .background(YePlyTheme.background)
            .navigationTitle("Comentários")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { dismiss() } } }
        }
        .task { if offlineLibrary.isConnected { await model.load(trackID: track.id, repository: container.repository) } }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var socialHeader: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.headline).lineLimit(1)
                Text(track.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
            }
            Spacer()
            Button { Task { await model.toggleTrackLike(trackID: track.id, repository: container.repository) } } label: {
                Label("\(model.summary.likeCount)", systemImage: model.summary.isLiked ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.summary.isLiked ? Color.red : Color.white)
                    .padding(.horizontal, 13).frame(height: 38)
                    .background(YePlyTheme.elevatedStrong, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var commentsList: some View {
        if model.isLoading && model.comments.isEmpty {
            ProgressView("Carregando…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.comments.isEmpty {
            ContentUnavailableView("Nenhum comentário", systemImage: "bubble.left", description: Text("Seja a primeira pessoa a comentar."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.comments) { comment in
                        CommentRow(
                            comment: comment,
                            canDelete: comment.userId == session.userID || session.isAdmin,
                            onLike: { Task { await model.toggleCommentLike(comment, repository: container.repository) } },
                            onDelete: { Task { await model.delete(comment, trackID: track.id, repository: container.repository) } },
                            onSeek: comment.timestampSeconds != nil && player.currentTrack?.id == track.id ? {
                                if let seconds = comment.timestampSeconds { player.seek(toSeconds: seconds) }
                            } : nil
                        )
                        if comment.id != model.comments.last?.id { Divider().overlay(YePlyTheme.line).padding(.leading, 62) }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedTimestamp {
                Button { self.selectedTimestamp = nil } label: {
                    Label("Comentando em \(formatTime(selectedTimestamp))", systemImage: "clock.badge.checkmark")
                        .font(.caption.weight(.semibold)).foregroundStyle(YePlyTheme.accent)
                        .padding(.horizontal, 11).frame(height: 30)
                        .background(YePlyTheme.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Adicione um comentário", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: draft) { _, value in if value.count > 1_000 { draft = String(value.prefix(1_000)) } }
                Button {
                    Task {
                        guard let userID = session.userID else { return }
                        if await model.send(trackID: track.id, userID: userID, body: draft, timestampSeconds: selectedTimestamp, repository: container.repository) {
                            draft = ""; selectedTimestamp = nil
                        }
                    }
                } label: {
                    ZStack {
                        Circle().fill(.white)
                        if model.isSending { ProgressView().tint(.black) }
                        else { Image(systemName: "arrow.up").fontWeight(.bold).foregroundStyle(.black) }
                    }
                    .frame(width: 42, height: 42)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
            }
        }
        .padding(12)
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct CommentRow: View {
    @EnvironmentObject private var container: AppContainer
    let comment: TrackComment
    let canDelete: Bool
    let onLike: () -> Void
    let onDelete: () -> Void
    let onSeek: (() -> Void)?
    @State private var avatarURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(comment.displayName).font(.caption.weight(.bold))
                    Text("@\(comment.username)").font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                    Text("· \(relativeDate)").font(.caption2).foregroundStyle(YePlyTheme.tertiary)
                }
                Text(comment.body).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 14) {
                    if let timestamp = comment.timestampSeconds {
                        Button(action: { onSeek?() }) {
                            Label(formatTime(timestamp), systemImage: "play.circle.fill")
                                .font(.caption2.weight(.bold)).foregroundStyle(YePlyTheme.accent)
                        }
                        .buttonStyle(.plain).disabled(onSeek == nil)
                    }
                    Button(action: onLike) {
                        Label("\(comment.likeCount)", systemImage: comment.isLiked ? "heart.fill" : "heart")
                            .font(.caption2.weight(.semibold)).foregroundStyle(comment.isLiked ? Color.red : YePlyTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if canDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) { Label("Excluir comentário", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").foregroundStyle(YePlyTheme.tertiary).frame(width: 30, height: 30) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .task(id: comment.avatarPath) {
            guard let path = comment.avatarPath else { return }
            avatarURL = try? await container.repository.signedAvatarURL(path: path)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(YePlyTheme.elevatedStrong)
            if let avatarURL {
                YePlyRemoteImage(url: avatarURL) { phase in
                    if case let .success(image) = phase { image.resizable().scaledToFill() }
                    else { initials }
                }
            } else { initials }
        }
        .frame(width: 38, height: 38).clipShape(Circle())
    }

    private var initials: some View {
        Text(comment.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.caption.bold()).foregroundStyle(.white)
    }

    private var relativeDate: String {
        RelativeDateTimeFormatter().localizedString(for: comment.createdAt, relativeTo: .now)
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
