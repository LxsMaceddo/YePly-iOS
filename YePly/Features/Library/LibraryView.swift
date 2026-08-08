import SwiftUI

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
}

struct LibraryView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = LibraryViewModel()
    @State private var scope: LibraryScope
    @State private var searchText = ""
    @State private var showingCreate = false

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
                        description: Text(scope == .shared ? "Abra um link do YePly para guardar uma playlist aqui." : "Crie uma playlist e adicione seus primeiros MP3.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 22) {
                        ForEach(filtered) { playlist in
                            NavigationLink(value: playlist) { PlaylistCard(playlist: playlist) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .navigationBarHidden(true)
        .refreshable { await model.load(scope: scope, repository: container.repository) }
        .sheet(isPresented: $showingCreate) { CreatePlaylistView { Task { await model.load(scope: scope, repository: container.repository) } } }
        .task(id: scope) { await model.load(scope: scope, repository: container.repository) }
        .alert("Não foi possível carregar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .yeplyBackground()
    }

    private var header: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("BIBLIOTECA").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(YePlyTheme.tertiary)
                    Text("Olá, \(session.profile?.displayName.components(separatedBy: " ").first ?? "você")")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1.2)
                }
                Spacer()
                Button { showingCreate = true } label: {
                    Image(systemName: "plus").font(.headline.weight(.bold)).foregroundStyle(.black).frame(width: 44, height: 44).background(.white, in: Circle())
                }
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
                Button("Mais recentes") {}
                Button("Nome") {}
            } label: { Image(systemName: "arrow.up.arrow.down").foregroundStyle(YePlyTheme.secondary).frame(width: 36, height: 36).background(YePlyTheme.elevated, in: Circle()) }
        }
    }

    private var filtered: [Playlist] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.playlists }
        return model.playlists.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.artistName.localizedCaseInsensitiveContains(query) }
    }
}

struct PlaylistCard: View {
    @EnvironmentObject private var container: AppContainer
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaylistArtworkView(playlist: playlist)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 5) {
                    Text(playlist.artistName).lineLimit(1)
                    if let count = playlist.trackCount { Text("• \(count) faixa\(count == 1 ? "" : "s")") }
                }
                .font(.caption).foregroundStyle(YePlyTheme.secondary)
            }
        }
    }
}

struct PlaylistArtworkView: View {
    @EnvironmentObject private var container: AppContainer
    let playlist: Playlist
    @State private var coverURL: URL?

    var body: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { CoverArtwork(playlist: playlist) }
                }
            } else { CoverArtwork(playlist: playlist) }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: playlist.coverPath) {
            guard let path = playlist.coverPath else { return }
            coverURL = try? await container.repository.signedCoverURL(path: path)
        }
    }
}
