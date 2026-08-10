import SwiftUI

@MainActor
final class YePlyNotificationStore: ObservableObject {
    @Published private(set) var items: [SocialNotification] = []
    @Published var toast: SocialNotification?
    @Published var showingCenter = false
    @Published var errorMessage: String?
    private var knownIDs: Set<UUID> = []
    private var didLoad = false
    private var toastTask: Task<Void, Never>?

    var unreadCount: Int { items.filter(\.isUnread).count }

    func monitor(repository: any MusicRepository) async {
        while !Task.isCancelled {
            await refresh(repository: repository)
            try? await Task.sleep(for: .seconds(12))
        }
    }

    func refresh(repository: any MusicRepository) async {
        do {
            let latest = try await repository.fetchNotifications()
            if didLoad, let newest = latest.first(where: { $0.isUnread && !knownIDs.contains($0.id) }) { showToast(newest) }
            items = latest
            knownIDs.formUnion(latest.map(\.id))
            didLoad = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func markAllRead(repository: any MusicRepository) async {
        do {
            try await repository.markAllNotificationsRead()
            await refresh(repository: repository)
        } catch { errorMessage = error.localizedDescription }
    }

    func openCenter() {
        toast = nil
        showingCenter = true
    }

    func dismissToast() { toast = nil }

    private func showToast(_ notification: SocialNotification) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = notification }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.toast = nil }
        }
    }
}

struct NotificationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var notifications: YePlyNotificationStore

    var body: some View {
        NavigationStack {
            Group {
                if notifications.items.isEmpty {
                    ContentUnavailableView("Nenhuma notificação", systemImage: "bell", description: Text("Curtidas, comentários e novos seguidores aparecerão aqui."))
                } else {
                    List(notifications.items) { notification in
                        NotificationRow(notification: notification)
                            .listRowBackground(notification.isUnread ? YePlyTheme.accent.opacity(0.09) : YePlyTheme.elevated)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(YePlyTheme.background)
            .navigationTitle("Notificações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                if notifications.unreadCount > 0 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Marcar lidas") { Task { await notifications.markAllRead(repository: container.repository) } }
                    }
                }
            }
        }
        .task { await notifications.refresh(repository: container.repository) }
    }
}

struct NotificationToast: View {
    let notification: SocialNotification
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.headline).foregroundStyle(YePlyTheme.accent)
                .frame(width: 38, height: 38).background(YePlyTheme.elevatedStrong, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.actorDisplayName).font(.subheadline.bold()).foregroundStyle(.white)
                Text(notification.message).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(2)
            }
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(YePlyTheme.tertiary).frame(width: 30, height: 30) }
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var icon: String {
        switch notification.kind {
        case .newFollower: "person.badge.plus"
        case .playlistFollow: "rectangle.stack.badge.plus"
        case .trackLike: "heart.fill"
        case .trackComment: "bubble.left.fill"
        }
    }
}

private struct NotificationRow: View {
    @EnvironmentObject private var container: AppContainer
    let notification: SocialNotification
    @State private var avatarURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(YePlyTheme.elevatedStrong)
                if let avatarURL {
                    YePlyRemoteImage(url: avatarURL) { phase in
                        if case let .success(image) = phase { image.resizable().scaledToFill() }
                        else { initials }
                    }
                } else { initials }
            }
            .frame(width: 46, height: 46).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.actorDisplayName).font(.subheadline.bold()) + Text(" \(notification.message)").font(.subheadline)
                Text(RelativeDateTimeFormatter().localizedString(for: notification.createdAt, relativeTo: .now))
                    .font(.caption2).foregroundStyle(YePlyTheme.tertiary)
            }
            Spacer()
            if notification.isUnread { Circle().fill(YePlyTheme.accent).frame(width: 8, height: 8).padding(.top, 5) }
        }
        .padding(.vertical, 5)
        .task(id: notification.actorAvatarPath) {
            guard let path = notification.actorAvatarPath else { return }
            avatarURL = try? await container.repository.signedAvatarURL(path: path)
        }
    }

    private var initials: some View {
        Text(notification.actorDisplayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.caption.bold()).foregroundStyle(.white)
    }
}
