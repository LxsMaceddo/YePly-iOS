import SwiftUI

struct PlaybackSettingsView: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        Form {
            Section {
                Toggle("Reprodução sem atraso", isOn: $player.gaplessPlaybackEnabled)
                Picker("Fade in e fade out", selection: $player.fadeDuration) {
                    Text("Desativado").tag(0.0)
                    Text("1 segundo").tag(1.0)
                    Text("2 segundos").tag(2.0)
                    Text("3 segundos").tag(3.0)
                    Text("5 segundos").tag(5.0)
                }
            } header: {
                Text("Transição entre músicas")
            } footer: {
                Text("Sem atraso prepara a próxima música antes da atual terminar. O fade suaviza a entrada e a saída do áudio.")
            }

            Section("Forma de onda") {
                LabeledContent("Precisão", value: "96 amostras")
                Label("Novos MP3 são analisados durante o upload para representar a intensidade real do áudio.", systemImage: "waveform")
                    .font(.footnote).foregroundStyle(YePlyTheme.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(YePlyTheme.background)
        .navigationTitle("Reprodução")
        .navigationBarTitleDisplayMode(.inline)
    }
}
