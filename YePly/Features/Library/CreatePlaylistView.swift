import SwiftUI

struct CreatePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @State private var title = ""
    @State private var artist = ""
    @State private var summary = ""
    @State private var visibility: PlaylistVisibility = .unlisted
    @State private var isSaving = false
    @State private var error: String?
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Identidade") {
                    TextField("Nome da playlist", text: $title)
                    TextField("Artista ou curador", text: $artist)
                    TextField("Descrição", text: $summary, axis: .vertical).lineLimit(3...6)
                }
                Section("Acesso") {
                    Picker("Visibilidade", selection: $visibility) {
                        ForEach(PlaylistVisibility.allCases) { item in Label(item.title, systemImage: item.icon).tag(item) }
                    }
                    Text(visibility == .unlisted ? "Somente pessoas com o link poderão entrar." : visibility == .publicAccess ? "Aparece para todos os usuários autenticados." : "Somente você pode acessar.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section { Label("Envie somente músicas próprias ou que você tenha autorização para distribuir.", systemImage: "checkmark.shield") .font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden)
            .background(YePlyTheme.background)
            .navigationTitle("Nova playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Criando…" : "Criar") { create() }.disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .alert("Erro", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }

    private func create() {
        guard let userID = session.userID else { error = YePlyError.noActiveUser.localizedDescription; return }
        isSaving = true
        Task {
            do {
                _ = try await container.repository.createPlaylist(NewPlaylist(ownerId: userID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), artistName: artist.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary.isEmpty ? nil : summary, visibility: visibility))
                onCreated(); dismiss()
            } catch { self.error = error.localizedDescription }
            isSaving = false
        }
    }
}
