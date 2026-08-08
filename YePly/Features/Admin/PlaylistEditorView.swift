import PhotosUI
import SwiftUI
import UIKit

struct PlaylistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @State private var draft: Playlist
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverPreview: Image?

    init(playlist: Playlist) { _draft = State(initialValue: playlist) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Capa") {
                    HStack(spacing: 16) {
                        Group {
                            if let coverPreview { coverPreview.resizable().scaledToFill() }
                            else { CoverArtwork(playlist: draft, cornerRadius: 12) }
                        }
                        .frame(width: 82, height: 82).clipShape(RoundedRectangle(cornerRadius: 12))
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Escolher imagem", systemImage: "photo.on.rectangle")
                        }
                    }
                }
                Section("Playlist") {
                    TextField("Nome", text: $draft.title)
                    TextField("Artista", text: $draft.artistName)
                    TextField("Descrição", text: Binding(get: { draft.summary ?? "" }, set: { draft.summary = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }
                Section("Compartilhamento") {
                    Picker("Visibilidade", selection: $draft.visibility) { ForEach(PlaylistVisibility.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                    LabeledContent("Token do link", value: String(draft.shareToken.uuidString.prefix(8)) + "…")
                }
            }
            .scrollContentBackground(.hidden).background(YePlyTheme.background)
            .navigationTitle("Editar").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Salvando…" : "Salvar") { save() }.disabled(isSaving || draft.title.isEmpty || draft.artistName.isEmpty) }
            }
            .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) else { return }
                    coverPreview = Image(uiImage: uiImage)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                if let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.88) {
                    draft.coverPath = try await container.repository.uploadCover(jpeg, for: draft)
                }
                try await container.repository.updatePlaylist(draft)
                dismiss()
            }
            catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}
