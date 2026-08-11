import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var offlineLibrary: OfflineLibraryStore
    @EnvironmentObject private var notifications: YePlyNotificationStore
    @State private var showingSignOut = false
    @State private var showingEditor = false
    @State private var avatarURL: URL?
    @State private var backgroundURL: URL?
    @State private var socialProfile: UserProfile?
    @State private var equippedBadges: [EquippedAlbumBadge] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    profileHero

                    if !equippedBadges.isEmpty {
                        ProfileBadgeShowcase(badges: equippedBadges)
                    }

                    if let tastes = session.profile?.tastes, !tastes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Sua assinatura musical", systemImage: "heart.fill")
                                .font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(tastes, id: \.self) { taste in
                                    Text(taste).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(height: 32)
                                        .background(YePlyTheme.elevatedStrong, in: Capsule())
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(YePlyTheme.elevated.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        ProfileMetric(value: "\(offlineLibrary.downloadedPlaylistCount)", label: "Playlists offline", icon: "arrow.down.circle.fill")
                        ProfileMetric(value: formattedOfflineSize, label: "No aparelho", icon: "internaldrive.fill")
                    }

                    VStack(spacing: 0) {
                        if session.isAdmin {
                            NavigationLink { AdminDashboardView() } label: {
                                ProfileRow(icon: "slider.horizontal.3", title: "Administração", subtitle: "Catálogo, uploads e artistas verificados")
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                        }
                        NavigationLink { PlaybackHistoryView() } label: {
                            ProfileRow(icon: "clock.arrow.circlepath", title: "Histórico de reprodução", subtitle: "Veja tudo que você ouviu")
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                        NavigationLink { PlaybackSettingsView() } label: {
                            ProfileRow(icon: "slider.horizontal.3", title: "Configurações de reprodução", subtitle: "Sem atraso, fade in e fade out")
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                        NavigationLink { FavoriteCardArtistsView() } label: {
                            ProfileRow(icon: "star.fill", title: "Artistas favoritos", subtitle: "Escolha os artistas dos packs de conquista")
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                        ProfileRow(icon: "lock.shield", title: "Privacidade", subtitle: "Arquivos offline protegidos neste iPhone")
                        Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                        ProfileRow(icon: "questionmark.circle", title: "Ajuda e suporte", subtitle: "Fale com a equipe YePly")
                        Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                        NavigationLink { LegalTermsView() } label: {
                            ProfileRow(icon: "doc.text", title: "Termos e direitos autorais", subtitle: "Regras para músicas, cartas e comunidade")
                        }
                        .buttonStyle(.plain)
                    }
                    .background(YePlyTheme.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

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
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
                .background(alignment: .top) {
                    ProfileHeroBackdrop(url: backgroundURL)
                        .frame(height: 540)
                        .offset(y: -24)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingEditor) {
            if let profile = session.profile { ProfileEditorView(profile: profile) }
        }
        .task(id: session.profile?.avatarPath) { avatarURL = await session.avatarURL() }
        .task(id: session.profile?.backgroundPath) { backgroundURL = await session.backgroundURL() }
        .task(id: session.profile?.id) {
            guard offlineLibrary.isConnected, let id = session.profile?.id else { return }
            async let profile = container.repository.fetchProfile(id: id)
            async let badges = container.repository.fetchEquippedCardBadges(profileID: id)
            socialProfile = try? await profile
            equippedBadges = (try? await badges) ?? []
        }
        .confirmationDialog("Sair do YePly?", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("Sair", role: .destructive) { Task { await session.signOut() } }
            Button("Cancelar", role: .cancel) {}
        }
        .yeplyBackground()
    }

    private var profileHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("PERFIL").font(.caption2.bold()).tracking(2).foregroundStyle(.white.opacity(0.75))
                Spacer()
                profileToolbarButton(systemImage: "bell.fill", action: notifications.openCenter, badge: notifications.unreadCount)
                NavigationLink { CardProfileShowcaseView() } label: {
                    Image(systemName: "medal.star.fill")
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.34), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Badges e conquistas")
            }
            .padding(.top, 18)

            Spacer().frame(height: 58)

            HStack(alignment: .center, spacing: 16) {
                ProfileAvatarView(url: avatarURL, initials: initials, size: 96)
                    .id(session.profile?.avatarPath)
                    .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 3))
                    .shadow(color: .black.opacity(0.38), radius: 18, y: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.profile?.displayName ?? "Usuário")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text("@\(session.profile?.username ?? "yeply")")
                        if session.isAdmin {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(YePlyTheme.accent)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
                }
                Spacer()
                Button { showingEditor = true } label: {
                    Image(systemName: "pencil").font(.headline).frame(width: 42, height: 42)
                        .background(.white, in: Circle()).foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Editar perfil")
            }

            if let bio = session.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
            }

            HStack(spacing: 0) {
                profileHeroMetric(value: socialProfile?.followerCount ?? 0, label: "seguidores")
                Divider().frame(height: 34).overlay(.white.opacity(0.16))
                profileHeroMetric(value: socialProfile?.followingCount ?? 0, label: "seguindo")
                Divider().frame(height: 34).overlay(.white.opacity(0.16))
                profileHeroMetric(value: equippedBadges.count, label: "badges")
            }
            .padding(.vertical, 13)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10)))
        }
        .frame(minHeight: 410, alignment: .top)
    }

    private func profileToolbarButton(systemImage: String, action: @escaping () -> Void, badge: Int) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage).frame(width: 42, height: 42)
                    .background(.black.opacity(0.34), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16)))
                if badge > 0 {
                    Text("\(min(badge, 99))").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                        .padding(4).background(.red, in: Circle()).offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func profileHeroMetric(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.headline.monospacedDigit().bold())
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
    }

    private var initials: String {
        (session.profile?.displayName ?? "Y P").split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var formattedOfflineSize: String {
        ByteCountFormatter.string(fromByteCount: offlineLibrary.downloadedSizeBytes, countStyle: .file)
    }
}

private struct ProfileHeroBackdrop: View {
    let url: URL?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [YePlyTheme.accentSoft.opacity(0.54), YePlyTheme.accent.opacity(0.28), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url, url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url {
                YePlyRemoteImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                    if case let .success(image) = phase { image.resizable().scaledToFill() }
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.12), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.46),
                    .init(color: .black.opacity(0.78), location: 0.78),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .accessibilityHidden(true)
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
                YePlyRemoteImage(url: url) { phase in
                    if case let .success(image) = phase { image.resizable().scaledToFill() }
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

struct ProfileBadgeShowcase: View {
    let badges: [EquippedAlbumBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BADGES EM DESTAQUE")
                .font(.caption2.bold())
                .tracking(1.7)
                .foregroundStyle(YePlyTheme.tertiary)

            HStack(spacing: 18) {
                ForEach(badges.sorted { $0.slot < $1.slot }) { badge in
                    VStack(spacing: 7) {
                        CardBrowserArtwork(
                            path: badge.artworkPath,
                            seed: badge.albumId.uuidString,
                            title: badge.title,
                            tint: YePlyTheme.accent,
                            cornerRadius: 40
                        )
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(
                                LinearGradient(
                                    colors: [YePlyTheme.accent, .white.opacity(0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                        }
                        .shadow(color: YePlyTheme.accent.opacity(0.22), radius: 10, y: 5)

                        Text(badge.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(YePlyTheme.secondary)
                            .lineLimit(1)
                            .frame(width: 82)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
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
    @State private var selectedBackgroundPhoto: PhotosPickerItem?
    @State private var avatarPreview: UIImage?
    @State private var backgroundPreview: UIImage?
    @State private var currentAvatarURL: URL?
    @State private var currentBackgroundURL: URL?
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
                    Group {
                        if let backgroundPreview {
                            Image(uiImage: backgroundPreview).resizable().scaledToFill()
                        } else if let currentBackgroundURL, currentBackgroundURL.isFileURL,
                                  let image = UIImage(contentsOfFile: currentBackgroundURL.path) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if let currentBackgroundURL {
                            YePlyRemoteImage(url: currentBackgroundURL) { phase in
                                if case let .success(image) = phase { image.resizable().scaledToFill() }
                                else { profileBackgroundPlaceholder }
                            }
                        } else {
                            profileBackgroundPlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                    PhotosPicker(selection: $selectedBackgroundPhoto, matching: .images) {
                        Label("Escolher imagem de fundo", systemImage: "photo.fill.on.rectangle.fill")
                    }
                } header: {
                    Text("Fundo do perfil")
                } footer: {
                    Text("A imagem aparece no topo e desaparece gradualmente para preto ao navegar pelo perfil.")
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
            .onChange(of: selectedBackgroundPhoto) { _, photo in
                Task {
                    guard let data = try? await photo?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    backgroundPreview = image
                }
            }
            .task {
                async let avatar = session.avatarURL()
                async let background = session.backgroundURL()
                currentAvatarURL = await avatar
                currentBackgroundURL = await background
            }
            .alert("Não foi possível salvar", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(session.errorMessage ?? "") }
        }
    }

    private var initials: String {
        displayName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var profileBackgroundPlaceholder: some View {
        LinearGradient(
            colors: [YePlyTheme.accentSoft.opacity(0.75), YePlyTheme.accent.opacity(0.52), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(Image(systemName: "photo.on.rectangle.angled").font(.title).foregroundStyle(.white.opacity(0.7)))
    }

    private func save() {
        isSaving = true
        let tastes = tastesText.split(separator: ",").map(String.init)
        let jpeg = avatarPreview.flatMap(makeAvatarJPEG)
        let backgroundJPEG = backgroundPreview.flatMap(makeBackgroundJPEG)
        Task {
            if await session.updateProfile(
                displayName: displayName,
                bio: bio,
                tastes: tastes,
                avatarJPEG: jpeg,
                backgroundJPEG: backgroundJPEG
            ) { dismiss() }
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

    private func makeBackgroundJPEG(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let target = CGSize(width: 1_440, height: 1_080)
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
        return normalized.jpegData(compressionQuality: 0.80)
    }
}

private struct ProfileRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
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
}
