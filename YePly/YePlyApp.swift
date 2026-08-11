import SwiftUI

@main
struct YePlyApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.session)
                .environmentObject(container.player)
                .environmentObject(container.links)
                .environmentObject(container.offlineLibrary)
                .environmentObject(container.notifications)
                .onOpenURL { container.handleURL($0) }
                .task { await container.session.start() }
        }
    }
}
