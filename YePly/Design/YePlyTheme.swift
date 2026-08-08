import SwiftUI

enum YePlyTheme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.038)
    static let elevated = Color(red: 0.075, green: 0.075, blue: 0.082)
    static let elevatedStrong = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let line = Color.white.opacity(0.09)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.34)
    static let accentSoft = Color(red: 0.58, green: 0.42, blue: 1.0)

    static let coverGradients: [LinearGradient] = [
        LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.indigo, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.black, .gray.opacity(0.65)], startPoint: .top, endPoint: .bottomTrailing),
        LinearGradient(colors: [.red.opacity(0.85), .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.mint.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    ]
}

struct YePlyLogo: View {
    var size: CGFloat = 34
    var body: some View {
        Image("YePlyBrand")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct CoverArtwork: View {
    let playlist: Playlist
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            YePlyTheme.coverGradients[Int(UInt(bitPattern: playlist.id.hashValue) % UInt(YePlyTheme.coverGradients.count))]
            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: 130, height: 130)
                .blur(radius: 2)
                .offset(x: 46, y: -52)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(playlist.artistName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .opacity(0.7)
                Text(playlist.title)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

extension View {
    func yeplyBackground() -> some View {
        background(YePlyTheme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
