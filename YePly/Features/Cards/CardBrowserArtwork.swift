import SwiftUI

/// Compact, failure-tolerant artwork used by the Cards browsers.
/// It accepts both Supabase object paths and already-public HTTPS artwork URLs.
struct CardBrowserArtwork: View {
    @EnvironmentObject private var container: AppContainer

    let path: String?
    let seed: String
    let title: String
    var tint: Color = YePlyTheme.accentSoft
    var cornerRadius: CGFloat = 16

    @State private var resolvedURL: URL?
    @State private var didFail = false

    var body: some View {
        ZStack {
            placeholder

            if let resolvedURL, !didFail {
                AsyncImage(url: resolvedURL, transaction: Transaction(animation: .easeOut(duration: 0.22))) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        placeholder
                            .onAppear { didFail = true }
                    case .empty:
                        ProgressView()
                            .tint(.white.opacity(0.65))
                    @unknown default:
                        placeholder
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .clipped()
        .task(id: path) {
            resolvedURL = nil
            didFail = false
            guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return }
            resolvedURL = try? await container.repository.signedCoverURL(path: path)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.92), Color(red: 0.08, green: 0.07, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 110, height: 110)
                .offset(x: 40, y: -36)

            VStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .black))
                Text(monogram)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(.white.opacity(0.80))
        }
    }

    private var monogram: String {
        let value = title
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return value.isEmpty ? "Y" : value
    }
}
