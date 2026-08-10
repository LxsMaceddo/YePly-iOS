import SwiftUI
import UIKit

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
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty,
                  data.count <= 20 * 1_024 * 1_024
            else { return nil }
            return data
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
    let url: URL?
    let transaction: Transaction
    let content: (YePlyRemoteImagePhase) -> Content

    @State private var phase: YePlyRemoteImagePhase = .empty

    init(
        url: URL?,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (YePlyRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                phase = .empty
                guard let url else { return }
                guard let data = await YePlyRemoteImageLoader.shared.data(for: url),
                      !Task.isCancelled,
                      let image = UIImage(data: data, scale: UIScreen.main.scale)
                else {
                    if !Task.isCancelled { phase = .failure }
                    return
                }
                withTransaction(transaction) {
                    phase = .success(Image(uiImage: image))
                }
            }
    }
}
