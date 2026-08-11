import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct UploadTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    let playlist: Playlist
    let nextPosition: Int
    let onUploaded: () -> Void

    @State private var fileURL: URL?
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var duration: Double = 0
    @State private var fileSize: Int64 = 0
    @State private var waveformSamples: [Double]?
    @State private var showingImporter = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Arquivo") {
                    Button { showingImporter = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: fileURL == nil ? "waveform.badge.plus" : "music.note").font(.title3).frame(width: 34, height: 34).background(YePlyTheme.elevatedStrong, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) { Text(fileURL?.lastPathComponent ?? "Escolher MP3"); Text(fileURL == nil ? "Até 200 MB" : ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if waveformSamples != nil {
                        Label("Forma de onda analisada", systemImage: "waveform.badge.checkmark")
                            .font(.caption).foregroundStyle(YePlyTheme.accent)
                    }
                }
                Section("Informações") {
                    TextField("Título", text: $title)
                    TextField("Artista", text: $artist)
                    TextField("Álbum (opcional)", text: $album)
                }
                Section { Label("Ao enviar, você confirma que possui os direitos ou autorização para disponibilizar este áudio.", systemImage: "checkmark.shield") .font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden).background(YePlyTheme.background)
            .navigationTitle("Adicionar faixa").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isUploading ? "Enviando…" : "Enviar") { upload() }.disabled(!canUpload || isUploading) }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.mp3, .audio], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                inspect(url)
            }
            .alert("Não foi possível enviar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var canUpload: Bool { fileURL != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty && !artist.trimmingCharacters(in: .whitespaces).isEmpty }

    private func inspect(_ url: URL) {
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "mp3" else { errorMessage = YePlyError.unsupportedFile.localizedDescription; return }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(values.fileSize ?? 0)
                guard size <= 200 * 1_024 * 1_024 else { throw YePlyError.fileTooLarge }
                let asset = AVURLAsset(url: url)
                let loadedDuration = try await asset.load(.duration).seconds
                let copyURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
                try FileManager.default.copyItem(at: url, to: copyURL)
                fileURL = copyURL; fileSize = size; duration = loadedDuration.isFinite ? loadedDuration : 0
                waveformSamples = await WaveformAnalyzer.samples(from: copyURL)
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
                if artist.isEmpty { artist = playlist.artistName }
                if album.isEmpty { album = playlist.title }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func upload() {
        guard let fileURL, let userID = session.userID else { return }
        isUploading = true
        Task {
            do {
                _ = try await container.repository.uploadTrack(TrackUpload(fileURL: fileURL, title: title.trimmingCharacters(in: .whitespacesAndNewlines), artistName: artist.trimmingCharacters(in: .whitespacesAndNewlines), albumName: album.isEmpty ? nil : album, duration: duration, fileSize: fileSize, waveformSamples: waveformSamples), to: playlist, uploaderID: userID, position: nextPosition)
                try? FileManager.default.removeItem(at: fileURL)
                onUploaded(); dismiss()
            } catch { errorMessage = error.localizedDescription }
            isUploading = false
        }
    }
}
