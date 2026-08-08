import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(colors: [YePlyTheme.accent, YePlyTheme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform").font(.headline)
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(track.artistName).font(.caption).foregroundStyle(YePlyTheme.secondary).lineLimit(1)
                }
                Spacer()
                Button(action: player.toggle) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 34, height: 34) }
                Button(action: player.next) { Image(systemName: "forward.fill").frame(width: 30, height: 34) }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Capsule().fill(YePlyTheme.accent).frame(width: geometry.size.width * player.progress, height: 2)
                }.frame(height: 2)
            }
        }
    }
}
