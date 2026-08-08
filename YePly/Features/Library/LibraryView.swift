import SwiftUI
import UIKit

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(scope: LibraryScope, repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do { playlists = try await repository.fetchLibrary(scope: scope); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func useOffline(_ playlists: [Playlist]) {
        self.playlists = playlists
        isLoading = false
        errorMessage = nil
    }
}

struct LibraryView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @StateObject private var model = LibraryViewModel()
    @State private var scope: LibraryScope
    @State private var searchText = ""
    @State private var showingCreate = false
    @State private var sortMode: SortMode = .recent

    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top)
    ]

    init(initialScope: LibraryScope) { _scope = State(initialValue: initialScope) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                scopePicker

                if model.isLoading && model.playlists.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 90)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        scope == .shared ? "Nada compartilhado ainda" : "Sua biblioteca está vazia",
                        systemImage: scope == .shared ? "person.2" : "music.note.house",
                        description: Text(emptyDescription)
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(filtered) { playlist in
                            NavigationLink(value: playlist) {
                                PlaylistCard(playlist: playlist)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                                .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .navigationBarHidden(true)
        .refreshable { await loadLibrary() }
        .sheet(isPresented: $showingCreate) { CreatePlaylistView { Task { await model.load(scope: scope, repository: container.repository) } } }
        .task(id: loadKey) { await loadLibrary() }
        .alert("Não foi possível carregar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .yeplyBackground()
    }

    private var loadKey: String { "\(scope.rawValue)-\(offlineLibrary.isConnected)-\(offlineLibrary.downloadedPlaylistCount)" }

    private var emptyDescription: String {
        if offlineLibrary.isOfflineMode { return "Conecte-se à internet e baixe uma playlist para ouvi-la sem conexão." }
        return scope == .shared ? "Abra um link do YePly para guardar uma playlist aqui." : "Crie uma playlist e adicione seus primeiros MP3."
    }

    private func loadLibrary() async {
        if offlineLibrary.isOfflineMode {
            model.useOffline(offlineLibrary.playlists(for: scope))
        } else {
            await model.load(scope: scope, repository: container.repository)
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("BIBLIOTECA").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(YePlyTheme.tertiary)
                    Text("Olá, \(greetingUsername)")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1.2)
                }
                Spacer()
                Button { showingCreate = true } label: {
                    Image(systemName: "plus").font(.headline.weight(.bold)).foregroundStyle(.black).frame(width: 44, height: 44).background(.white, in: Circle())
                }
                .disabled(offlineLibrary.isOfflineMode)
                .opacity(offlineLibrary.isOfflineMode ? 0.45 : 1)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(YePlyTheme.tertiary)
                TextField("Buscar playlist ou artista", text: $searchText).textInputAutocapitalization(.never)
                if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(YePlyTheme.tertiary) } }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 18)
    }

    private var greetingUsername: String {
        let rawUsername = session.profile?.username ?? ""
        let username = rawUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return username.isEmpty ? "você" : username.uppercased()
    }

    private var scopePicker: some View {
        HStack(spacing: 5) {
            ForEach(LibraryScope.allCases) { item in
                Button(item.title) { withAnimation(.snappy) { scope = item } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scope == item ? .black : YePlyTheme.secondary)
                    .padding(.horizontal, 15).frame(height: 36)
                    .background(scope == item ? .white : .clear, in: Capsule())
            }
            Spacer()
            Menu {
                Picker("Ordenar", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in Label(mode.title, systemImage: mode.icon).tag(mode) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down").foregroundStyle(YePlyTheme.secondary).frame(width: 36, height: 36).background(YePlyTheme.elevated, in: Circle()) }
        }
    }

    private var filtered: [Playlist] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? model.playlists : model.playlists.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.artistName.localizedCaseInsensitiveContains(query)
        }
        switch sortMode {
        case .recent: return matching.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .name: return matching.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return matching.sorted { $0.artistName.localizedStandardCompare($1.artistName) == .orderedAscending }
        }
    }
}

private enum SortMode: String, CaseIterable, Identifiable {
    case recent, name, artist
    var id: String { rawValue }
    var title: String { switch self { case .recent: "Mais recentes"; case .name: "Nome"; case .artist: "Artista" } }
    var icon: String { switch self { case .recent: "clock"; case .name: "textformat"; case .artist: "person" } }
}

struct PlaylistCard: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaylistArtworkView(playlist: playlist)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if offlineLibrary.isPlaylistDownloaded(playlist.id) {
                        Label("Offline", systemImage: "arrow.down.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(7)
                            .background(.white, in: Circle())
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                Text(metadata).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: String {
        guard let count = playlist.trackCount else { return playlist.artistName }
        return "\(playlist.artistName) • \(count) faixa\(count == 1 ? "" : "s")"
    }
}

struct PlaylistArtworkView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    let playlist: Playlist
    @State private var coverURL: URL?
    @State private var localCoverImage: UIImage?

    var body: some View {
        Group {
            if let localCoverImage {
                Image(uiImage: localCoverImage).resizable().scaledToFill()
            } else if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { CoverArtwork(playlist: playlist) }
                }
            } else { CoverArtwork(playlist: playlist) }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: "\(playlist.coverPath ?? "none")-\(offlineLibrary.isPlaylistDownloaded(playlist.id))") {
            coverURL = nil
            localCoverImage = nil
            if let localURL = offlineLibrary.localCoverURL(for: playlist.id) {
                localCoverImage = UIImage(contentsOfFile: localURL.path)
            } else if offlineLibrary.isConnected, let path = playlist.coverPath {
                coverURL = try? await container.repository.signedCoverURL(path: path)
            }
        }
    }
}
