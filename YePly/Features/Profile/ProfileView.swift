import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @State private var showingSignOut = false
    @State private var showingEditor = false
    @State private var avatarURL: URL?
    @State private var socialProfile: UserProfile?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("Perfil").font(.system(size: 34, weight: .bold, design: .rounded))
                    Spacer()
                    YePlyLogo(size: 34)
                }
                .padding(.top, 18)

                VStack(spacing: 13) {
                    ProfileAvatarView(url: avatarURL, initials: initials, size: 104)
                        .id(session.profile?.avatarPath)
                    VStack(spacing: 5) {
                        Text(session.profile?.displayName ?? "Usuário").font(.title2.bold())
                        Text("@\(session.profile?.username ?? "yeply")").font(.subheadline).foregroundStyle(YePlyTheme.secondary)
                    }
                    if let bio = session.profile?.bio, !bio.isEmpty {
                        Text(bio).font(.subheadline).foregroundStyle(YePlyTheme.secondary).multilineTextAlignment(.center).padding(.horizontal, 14)
                    }
                    HStack(spacing: 8) {
                        if session.isAdmin {
                            Label("Administrador", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(YePlyTheme.accent)
                        }
                        Button { showingEditor = true } label: {
                            Label("Editar perfil", systemImage: "pencil")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)

                if let tastes = session.profile?.tastes, !tastes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MEUS GOSTOS").font(.caption2.bold()).tracking(1.7).foregroundStyle(YePlyTheme.tertiary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(tastes, id: \.self) { taste in
                                Text(taste).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(height: 32)
                                    .background(YePlyTheme.elevatedStrong, in: Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    ProfileMetric(value: "\(socialProfile?.followerCount ?? 0)", label: "Seguidores", icon: "person.2.fill")
                    ProfileMetric(value: "\(socialProfile?.followingCount ?? 0)", label: "Seguindo", icon: "person.badge.plus")
                }

                HStack(spacing: 10) {
                    ProfileMetric(value: "\(offlineLibrary.downloadedPlaylistCount)", label: "Playlists offline", icon: "arrow.down.circle.fill")
                    ProfileMetric(value: formattedOfflineSize, label: "No aparelho", icon: "internaldrive.fill")
                }

                VStack(spacing: 0) {
                    ProfileRow(icon: "lock.shield", title: "Privacidade", subtitle: "Arquivos offline protegidos neste iPhone")
                    Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                    ProfileRow(icon: "questionmark.circle", title: "Ajuda e suporte", subtitle: "Fale com a equipe YePly")
                    Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                    ProfileRow(icon: "doc.text", title: "Termos e direitos autorais", subtitle: "Regras para envio de músicas")
                }
                .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if container.isDemoBackend {
                    Label("Modo demonstração — conecte o Supabase para habilitar contas e uploads reais.", systemImage: "hammer.fill")
                        .font(.footnote).foregroundStyle(YePlyTheme.secondary).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(YePlyTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                Button(role: .destructive) { showingSignOut = true } label: {
                    Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingEditor) {
            if let profile = session.profile { ProfileEditorView(profile: profile) }
        }
        .task(id: session.profile?.avatarPath) { avatarURL = await session.avatarURL() }
        .task(id: session.profile?.id) {
            guard offlineLibrary.isConnected, let id = session.profile?.id else { return }
            socialProfile = try? await container.repository.fetchProfile(id: id)
        }
        .confirmationDialog("Sair do YePly?", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("Sair", role: .destructive) { Task { await session.signOut() } }
            Button("Cancelar", role: .cancel) {}
        }
        .yeplyBackground()
    }

    private var initials: String {
        (session.profile?.displayName ?? "Y P").split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var formattedOfflineSize: String {
        ByteCountFormatter.string(fromByteCount: offlineLibrary.downloadedSizeBytes, countStyle: .file)
    }
}

private struct ProfileAvatarView: View {
    let url: URL?
    let initials: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [YePlyTheme.accent, YePlyTheme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url, url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Text(initials).font(.title.bold()).foregroundStyle(.white) }
                }
            } else {
                Text(initials).font(.title.bold()).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct ProfileMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(YePlyTheme.accent)
            Text(value).font(.headline.bold()).lineLimit(1).minimumScaleFactor(0.75)
            Text(label).font(.caption2).foregroundStyle(YePlyTheme.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @State private var displayName: String
    @State private var bio: String
    @State private var tastesText: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarPreview: UIImage?
    @State private var currentAvatarURL: URL?
    @State private var isSaving = false

    let profile: UserProfile

    init(profile: UserProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio ?? "")
        _tastesText = State(initialValue: (profile.tastes ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Foto") {
                    HStack(spacing: 18) {
                        if let avatarPreview {
                            Image(uiImage: avatarPreview).resizable().scaledToFill().frame(width: 78, height: 78).clipShape(Circle())
                        } else {
                            ProfileAvatarView(url: currentAvatarURL, initials: initials, size: 78)
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Escolher foto", systemImage: "photo.on.rectangle")
                        }
                    }
                }

                Section {
                    TextField("Nome", text: $displayName)
                    LabeledContent("Usuário") { Text("@\(profile.username)").foregroundStyle(.secondary) }
                } header: {
                    Text("Identidade")
                } footer: {
                    Label("O nome de usuário é permanente e não pode ser alterado.", systemImage: "lock.fill")
                }

                Section("Sobre você") {
                    TextField("Escreva uma descrição", text: $bio, axis: .vertical).lineLimit(3...6)
                    HStack { Spacer(); Text("\(bio.count)/280").font(.caption2).foregroundStyle(bio.count > 280 ? Color.red : YePlyTheme.secondary) }
                }

                Section("Gostos musicais") {
                    TextField("Rap, R&B, Funk, Rock…", text: $tastesText, axis: .vertical)
                    Text("Separe os gostos com vírgulas. Você pode adicionar até 12.").font(.caption).foregroundStyle(.secondary)
                }

                if offlineLibrary.isOfflineMode && !session.isDemo {
                    Section {
                        Label("Conecte-se à internet para salvar mudanças no perfil.", systemImage: "wifi.slash").foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(YePlyTheme.background)
            .navigationTitle("Editar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Salvando…" : "Salvar") { save() }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bio.count > 280 || (offlineLibrary.isOfflineMode && !session.isDemo))
                }
            }
            .onChange(of: selectedPhoto) { _, photo in
                Task {
                    guard let data = try? await photo?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    avatarPreview = image
                }
            }
            .task { currentAvatarURL = await session.avatarURL() }
            .alert("Não foi possível salvar", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(session.errorMessage ?? "") }
        }
    }

    private var initials: String {
        displayName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func save() {
        isSaving = true
        let tastes = tastesText.split(separator: ",").map(String.init)
        let jpeg = avatarPreview.flatMap(makeAvatarJPEG)
        Task {
            if await session.updateProfile(displayName: displayName, bio: bio, tastes: tastes, avatarJPEG: jpeg) { dismiss() }
            isSaving = false
        }
    }

    private func makeAvatarJPEG(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let target = CGSize(width: 720, height: 720)
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return normalized.jpegData(compressionQuality: 0.84)
    }
}

private struct ProfileRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        Button {} label: {
            HStack(spacing: 13) {
                Image(systemName: icon).frame(width: 30, height: 30).foregroundStyle(YePlyTheme.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(YePlyTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(YePlyTheme.tertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
}
