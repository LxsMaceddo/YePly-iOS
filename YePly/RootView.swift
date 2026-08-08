import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore

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
        .task(id: session.userID) { offlineLibrary.activate(userID: session.userID) }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var links: DeepLinkRouter
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @State private var selection = 0
    @State private var showingNowPlaying = false
    @State private var isMiniPlayerHidden = false
    @GestureState private var miniPlayerDragOffset: CGFloat = 0

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
        .safeAreaInset(edge: .top, spacing: 0) {
            if offlineLibrary.isOfflineMode {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text("MODO OFFLINE").font(.caption2.bold()).tracking(1.3)
                    Text("Somente downloads").font(.caption2).foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.88))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) { playerOverlay }
        .onChange(of: player.currentTrack?.id) { oldTrackID, newTrackID in
            if oldTrackID != newTrackID { withAnimation(.snappy) { isMiniPlayerHidden = false } }
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

    @ViewBuilder
    private var playerOverlay: some View {
        if player.currentTrack != nil {
            Group {
                if isMiniPlayerHidden {
                    Button {
                        withAnimation(.snappy) { isMiniPlayerHidden = false }
                    } label: {
                        Label("Mostrar player", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    MiniPlayerView { showingNowPlaying = true }
                        .offset(y: miniPlayerDragOffset)
                        .opacity(1 - Double(min(miniPlayerDragOffset / 180, 0.55)))
                        .simultaneousGesture(miniPlayerDismissGesture)
                        .accessibilityHint("Deslize para baixo para esconder o player")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .safeAreaPadding(.bottom, 52)
        }
    }

    private var miniPlayerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($miniPlayerDragOffset) { value, offset, _ in
                offset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard value.translation.height > 45 || value.predictedEndTranslation.height > 100 else { return }
                withAnimation(.snappy) { isMiniPlayerHidden = true }
            }
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
