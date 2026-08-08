import Foundation
import Supabase

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let publishableKey: String
    let universalLinkBase: URL

    var isConfigured: Bool {
        guard let supabaseURL else { return false }
        return supabaseURL.host?.contains("YOUR_PROJECT") == false &&
            !publishableKey.isEmpty && publishableKey != "YOUR_PUBLISHABLE_KEY"
    }

    static let current: AppConfiguration = {
        guard let url = Bundle.main.url(forResource: "AppConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let raw = object as? [String: Any]
        else {
            return .init(supabaseURL: nil, publishableKey: "", universalLinkBase: URL(string: "https://yeply.app/p/")!)
        }

        let backend = (raw["SUPABASE_URL"] as? String).flatMap(URL.init(string:))
        let key = (raw["SUPABASE_PUBLISHABLE_KEY"] as? String) ?? ""
        let links = (raw["UNIVERSAL_LINK_BASE"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://yeply.app/p/")!
        return .init(supabaseURL: backend, publishableKey: key, universalLinkBase: links)
    }()
}

enum SupabaseProvider {
    static let client: SupabaseClient? = {
        let configuration = AppConfiguration.current
        guard configuration.isConfigured, let url = configuration.supabaseURL else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: configuration.publishableKey,
            options: .init(auth: .init(flowType: .pkce))
        )
    }()
}
