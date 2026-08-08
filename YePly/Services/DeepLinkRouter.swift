import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingShareToken: UUID?
    @Published var pendingAuthCallback: URL?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        if url.scheme == "yeply", url.host == "auth" {
            pendingAuthCallback = url
            return true
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        let rawToken: String?
        if url.scheme == "yeply", url.host == "playlist" {
            rawToken = parts.first
        } else if url.host?.hasSuffix("yeply.app") == true, parts.first == "p" {
            rawToken = parts.dropFirst().first
        } else {
            rawToken = nil
        }

        guard let rawToken, let token = UUID(uuidString: rawToken) else { return false }
        pendingShareToken = token
        return true
    }

    func clearShare() { pendingShareToken = nil }
}
