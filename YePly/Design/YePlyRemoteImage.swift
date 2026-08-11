import SwiftUI
import UIKit

/// Stable artwork fallbacks for curated albums. Spotify artwork is mirrored to
/// Supabase on sync; these URLs keep old card snapshots useful until that sync.
enum YePlyArtworkFallbacks {
    private static let releaseGroups: [String: String] = [
        "the college dropout": "8a01217e-6947-3927-a39b-6691104694f1",
        "late registration": "c563d738-3841-31ce-b29d-ec6b40fd1e7b",
        "graduation": "d44c50ad-61fd-3fce-95fc-27024d7f1d30",
        "808s heartbreak": "1c1b50ec-828b-3d7c-9b1b-54cb1fe97d55",
        "my beautiful dark twisted fantasy": "5d6e21e1-deb5-428e-bb42-c2a567f3619b",
        "watch the throne deluxe": "a96597aa-93b4-4e14-9e6e-03892ab24979",
        "kanye west presents good music cruel summer": "1e06bb4d-3e20-4d1c-8d0a-0c179df397b5",
        "yeezus": "5d4d0f2d-9be7-4922-bc9a-cbd2880b12c2",
        "the life of pablo": "8c18657a-6338-490d-a952-897663596b96",
        "ye": "6448381d-9d98-4f84-b99d-733b6acde906",
        "kids see ghosts": "3346a9d9-031e-49e2-84b0-3734d790d7e5",
        "jesus is king": "ee26718c-2633-4278-8718-f3a45a95f20e",
        "donda deluxe": "7f4792fe-b563-4554-849a-95a89be71f84",
        "donda 2": "26584460-df1f-4a91-b036-8d0bf6f8ce95",
        "vultures 1": "c4d999c3-983d-4149-8580-9ccb4567a12a",
        "vultures 2": "d69250da-c94d-436d-bacf-7e52da48bc68"
    ]

    static func albumURL(for albumName: String) -> URL? {
        guard let releaseGroup = releaseGroups[normalized(albumName)] else { return nil }
        return URL(string: "https://coverartarchive.org/release-group/\(releaseGroup)/front-500")
    }

    static func candidates(primary: URL?, albumName: String?) -> [URL] {
        var result = primary.map { [$0] } ?? []
        if let albumName, let fallback = albumURL(for: albumName), fallback != primary {
            result.append(fallback)
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum YePlyRemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

/// Shared loader used by every remote cover and avatar. Identical requests are
/// coalesced and decoded data stays in memory while URLCache keeps a disk copy.
actor YePlyRemoteImageLoader {
    static let shared = YePlyRemoteImageLoader()

    private let memoryCache = NSCache<NSString, NSData>()
    private let session: URLSession
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private init() {
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
        memoryCache.countLimit = 500

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            directory: nil
        )
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 35
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async -> Data? {
        let key = cacheKey(for: url)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached as Data
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let session = session
        let task = Task<Data?, Never> {
            func fetch(policy: URLRequest.CachePolicy) async -> Data? {
                var request = URLRequest(url: url)
                request.cachePolicy = policy
                // Do not advertise AVIF/WebP here: some CDNs honor that header,
                // but not every iOS/UIKit decoder accepts the returned variant.
                request.setValue("image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
                guard let (data, response) = try? await session.data(for: request),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      !data.isEmpty,
                      data.count <= 20 * 1_024 * 1_024,
                      UIImage(data: data) != nil
                else { return nil }
                return data
            }

            if let cachedOrRemote = await fetch(policy: .returnCacheDataElseLoad) {
                return cachedOrRemote
            }
            // A stale signed URL or an unsupported cached representation should
            // not leave the card permanently on its placeholder.
            return await fetch(policy: .reloadIgnoringLocalCacheData)
        }
        inFlight[key] = task
        let loaded = await task.value
        inFlight[key] = nil
        if let loaded {
            memoryCache.setObject(loaded as NSData, forKey: key as NSString, cost: loaded.count)
        }
        return loaded
    }

    private func cacheKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

struct YePlyRemoteImage<Content: View>: View {
    let urls: [URL]
    let transaction: Transaction
    let content: (YePlyRemoteImagePhase) -> Content

    @State private var phase: YePlyRemoteImagePhase = .empty

    init(
        url: URL?,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (YePlyRemoteImagePhase) -> Content
    ) {
        self.urls = url.map { [$0] } ?? []
        self.transaction = transaction
        self.content = content
    }

    init(
        urls: [URL],
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (YePlyRemoteImagePhase) -> Content
    ) {
        self.urls = urls.reduce(into: []) { result, candidate in
            if !result.contains(candidate) { result.append(candidate) }
        }
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: urls) {
                phase = .empty
                for url in urls {
                    guard !Task.isCancelled else { return }
                    if let data = await YePlyRemoteImageLoader.shared.data(for: url),
                       let image = UIImage(data: data, scale: UIScreen.main.scale) {
                        withTransaction(transaction) {
                            phase = .success(Image(uiImage: image))
                        }
                        return
                    }
                }
                if !Task.isCancelled { phase = .failure }
            }
    }
}
