import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let session: SessionStore
    let repository: any MusicRepository
    let player: AudioPlayer
    let links: DeepLinkRouter
    let offlineLibrary: OfflineLibraryStore
    let isDemoBackend: Bool

    init() {
        offlineLibrary = OfflineLibraryStore()
        if let client = SupabaseProvider.client {
            session = SessionStore(client: client)
            repository = SupabaseMusicRepository(client: client)
            isDemoBackend = false
        } else {
            session = SessionStore(client: nil)
            repository = DemoMusicRepository()
            isDemoBackend = true
        }
        player = AudioPlayer(offlineLibrary: offlineLibrary)
        links = DeepLinkRouter()
    }

    func handleURL(_ url: URL) {
        if url.scheme == "yeply", url.host == "auth" {
            SupabaseProvider.client?.handle(url)
        } else {
            links.handle(url)
        }
    }
}
