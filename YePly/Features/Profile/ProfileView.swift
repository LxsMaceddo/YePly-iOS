import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var container: AppContainer
    @State private var showingSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack { Text("Perfil").font(.system(size: 34, weight: .bold, design: .rounded)); Spacer(); YePlyLogo(size: 34) }.padding(.top, 18)

                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [YePlyTheme.accent, YePlyTheme.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(initials).font(.title.bold()).foregroundStyle(.white)
                    }.frame(width: 84, height: 84)
                    Text(session.profile?.displayName ?? "Usuário").font(.title3.bold())
                    Text("@\(session.profile?.username ?? "yeply")").font(.subheadline).foregroundStyle(YePlyTheme.secondary)
                    if session.isAdmin { Label("Administrador", systemImage: "checkmark.shield.fill").font(.caption.weight(.semibold)).foregroundStyle(YePlyTheme.accent) }
                }

                VStack(spacing: 0) {
                    ProfileRow(icon: "lock.shield", title: "Privacidade", subtitle: "Arquivos privados e links protegidos")
                    Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                    ProfileRow(icon: "questionmark.circle", title: "Ajuda e suporte", subtitle: "Fale com a equipe YePly")
                    Divider().overlay(YePlyTheme.line).padding(.leading, 56)
                    ProfileRow(icon: "doc.text", title: "Termos e direitos autorais", subtitle: "Regras para envio de músicas")
                }.background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if container.isDemoBackend {
                    Label("Modo demonstração — conecte o Supabase para habilitar contas e uploads reais.", systemImage: "hammer.fill")
                        .font(.footnote).foregroundStyle(YePlyTheme.secondary).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(YePlyTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                Button(role: .destructive) { showingSignOut = true } label: { Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).frame(height: 50).background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 15)) }
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .confirmationDialog("Sair do YePly?", isPresented: $showingSignOut, titleVisibility: .visible) { Button("Sair", role: .destructive) { Task { await session.signOut() } }; Button("Cancelar", role: .cancel) {} }
        .yeplyBackground()
    }

    private var initials: String {
        (session.profile?.displayName ?? "Y P").split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
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
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white); Text(subtitle).font(.caption).foregroundStyle(YePlyTheme.secondary) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(YePlyTheme.tertiary)
            }.padding(14)
        }.buttonStyle(.plain)
    }
}
