import SwiftUI

@MainActor
private final class ArtistVerificationAdminModel: ObservableObject {
    @Published var artists: [ArtistSummary] = []
    @Published var query = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(repository: any MusicRepository) async {
        isLoading = true
        defer { isLoading = false }
        do { artists = try await repository.searchArtists(query: query); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func toggle(_ artist: ArtistSummary, repository: any MusicRepository) async {
        do {
            let verified = try await repository.toggleArtistVerification(artistName: artist.artistName)
            guard let index = artists.firstIndex(where: { $0.id == artist.id }) else { return }
            artists[index].isVerified = verified
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ArtistVerificationAdminView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = ArtistVerificationAdminModel()

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(YePlyTheme.tertiary)
                    TextField("Buscar artista", text: $model.query).textInputAutocapitalization(.never)
                }
            }

            Section("Artistas") {
                if model.isLoading && model.artists.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                ForEach(model.artists) { artist in
                    HStack(spacing: 12) {
                        ZStack { Circle().fill(YePlyTheme.elevatedStrong); Image(systemName: "music.mic").foregroundStyle(YePlyTheme.accent) }
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(artist.artistName).font(.subheadline.weight(.semibold))
                                if artist.isVerified { VerifiedArtistBadge() }
                            }
                            Text("\(artist.trackCount) músicas · \(artist.followerCount) seguidores")
                                .font(.caption).foregroundStyle(YePlyTheme.secondary)
                        }
                        Spacer()
                        Button(artist.isVerified ? "Verificado" : "Verificar") {
                            Task { await model.toggle(artist, repository: container.repository) }
                        }
                        .font(.caption.bold()).buttonStyle(.bordered).tint(artist.isVerified ? .blue : .white)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden).background(YePlyTheme.background)
        .navigationTitle("Artistas verificados")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.query) {
            if !model.query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await model.load(repository: container.repository)
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }
}
