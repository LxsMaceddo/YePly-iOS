import SwiftUI

struct AdminPackGrantView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var username = ""
    @State private var packCount = 1
    @State private var cardsPerPack = 3
    @State private var selectedArtistKey = ""
    @State private var rarity: CollectibleCardRarity = .common
    @State private var reason = ""
    @State private var artists: [CardArtistOption] = []
    @State private var isLoadingArtists = false
    @State private var isSending = false
    @State private var notice: Notice?

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("RECOMPENSA ADMIN", systemImage: "shippingbox.fill")
                        .font(.caption2.bold()).tracking(1.8).foregroundStyle(YePlyTheme.accent)
                    Text("Entregar packs")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
                    Text("Os packs chegam lacrados na conta escolhida e a entrega fica registrada no histórico administrativo.")
                        .font(.subheadline).foregroundStyle(YePlyTheme.secondary)
                }

                VStack(spacing: 0) {
                    fieldLabel("USUÁRIO")
                    HStack(spacing: 8) {
                        Text("@").foregroundStyle(YePlyTheme.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14).frame(height: 50)
                    .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
                }

                HStack(spacing: 12) {
                    counterCard(title: "PACKS", value: $packCount, range: 1...25, icon: "shippingbox.fill")
                    counterCard(title: "CARTAS/PACK", value: $cardsPerPack, range: 1...5, icon: "rectangle.stack.fill")
                }

                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("CONTEÚDO")
                    Picker("Artista", selection: $selectedArtistKey) {
                        Text("Todos os artistas").tag("")
                        ForEach(artists) { artist in
                            Text("\(artist.artistName) · \(artist.cardCount)").tag(artist.artistKey)
                        }
                    }
                    .pickerStyle(.menu).tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))

                    Picker("Raridade mínima", selection: $rarity) {
                        ForEach(CollectibleCardRarity.allCases) { option in
                            Label(option.title, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .pickerStyle(.menu).tint(rarity.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 9) {
                    fieldLabel("MOTIVO · OPCIONAL")
                    TextField("Ex.: recompensa do evento", text: $reason, axis: .vertical)
                        .lineLimit(2...4).padding(14)
                        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
                    Text("Máximo de 200 caracteres.")
                        .font(.caption2).foregroundStyle(reason.count > 200 ? .red : YePlyTheme.tertiary)
                }

                Button { Task { await sendPacks() } } label: {
                    HStack {
                        if isSending { ProgressView().tint(.black) }
                        Image(systemName: "paperplane.fill")
                        Text(isSending ? "Enviando…" : "Entregar agora").fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                .disabled(!canSubmit)

                Label("A função do Supabase valida o administrador, o usuário, o catálogo e os limites antes de criar qualquer pack.", systemImage: "lock.shield.fill")
                    .font(.caption).foregroundStyle(YePlyTheme.secondary)
                    .padding(14).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(18).padding(.bottom, 36)
        }
        .navigationTitle("Packs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadArtists() }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .yeplyBackground()
    }

    private var canSubmit: Bool {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        return !isSending && cleaned.count >= 3 && reason.count <= 200
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value).font(.caption2.bold()).tracking(1.5).foregroundStyle(YePlyTheme.tertiary)
    }

    private func counterCard(title: String, value: Binding<Int>, range: ClosedRange<Int>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption2.bold()).foregroundStyle(YePlyTheme.secondary)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)").font(.title2.bold().monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func loadArtists() async {
        guard !isLoadingArtists else { return }
        isLoadingArtists = true
        defer { isLoadingArtists = false }
        do { artists = try await container.repository.fetchCardArtists() }
        catch { notice = Notice(title: "Catálogo indisponível", message: error.localizedDescription) }
    }

    @MainActor
    private func sendPacks() async {
        guard canSubmit else { return }
        isSending = true
        defer { isSending = false }
        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        do {
            let result = try await container.repository.adminGrantCardPacks(
                username: cleanedUsername, packCount: packCount, cardCount: cardsPerPack,
                artistKey: selectedArtistKey.isEmpty ? nil : selectedArtistKey,
                rarityFloor: rarity,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason
            )
            notice = Notice(title: "Packs entregues", message: result.message ?? "A recompensa foi enviada para @\(cleanedUsername).")
            username = ""
            reason = ""
        } catch {
            notice = Notice(title: "Não foi possível entregar", message: error.localizedDescription)
        }
    }
}
