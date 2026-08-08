import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ZStack { YePlyTheme.background.ignoresSafeArea(); YePlyLogo(size: 58) }
            case .signedOut:
                AuthView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var links: DeepLinkRouter
    @State private var selection = 0
    @State private var showingNowPlaying = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { LibraryView(initialScope: .all) }
                .tabItem { Label("Biblioteca", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            NavigationStack { LibraryView(initialScope: .shared) }
                .tabItem { Label("Compartilhadas", systemImage: "person.2.fill") }
                .tag(1)
            if session.isAdmin {
                NavigationStack { AdminDashboardView() }
                    .tabItem { Label("Admin", systemImage: "slider.horizontal.3") }
                    .tag(2)
            }
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .tint(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                MiniPlayerView { showingNowPlaying = true }
                    .padding(.horizontal, 10).padding(.bottom, 2)
            }
        }
        .fullScreenCover(isPresented: $showingNowPlaying) { NowPlayingView() }
        .sheet(isPresented: Binding(get: { links.pendingShareToken != nil }, set: { if !$0 { links.clearShare() } })) {
            if let token = links.pendingShareToken { SharedPlaylistImportView(token: token) }
        }
        .alert("Reprodução", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(player.errorMessage ?? "") }
        .yeplyBackground()
    }
}

private struct SharedPlaylistImportView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var links: DeepLinkRouter
    let token: UUID
    @State private var playlist: Playlist?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let playlist { PlaylistDetailView(playlist: playlist) }
                else if let error { ContentUnavailableView("Link indisponível", systemImage: "link.badge.plus", description: Text(error)) }
                else { ProgressView("Abrindo playlist…") }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { links.clearShare() } } }
        }
        .presentationDragIndicator(.visible)
        .task {
            do { playlist = try await container.repository.acceptSharedPlaylist(token: token) }
            catch { self.error = error.localizedDescription }
        }
    }
}
