import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var container: AppContainer
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var didRequestConfirmation = false
    @State private var acceptedTerms = false
    @State private var showingTerms = false

    enum Mode { case signIn, signUp }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    YePlyLogo(size: 42)
                    Text("YePly").font(.system(size: 24, weight: .black, design: .rounded))
                }

                Spacer(minLength: 30)

                VStack(alignment: .leading, spacing: 9) {
                    Text(mode == .signIn ? "Sua música mora aqui." : "Crie seu espaço.")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-1.4)
                    Text(mode == .signIn ? "Entre para acessar suas playlists e tudo que compartilharam com você." : "Guarde seus MP3, monte playlists e compartilhe com quem quiser.")
                        .foregroundStyle(YePlyTheme.secondary)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                }

                VStack(spacing: 12) {
                    if mode == .signUp {
                        AuthField(title: "Nome", icon: "person", text: $name)
                        AuthField(title: "Nome de usuário", icon: "at", text: $username, capitalization: .never)
                    }
                    AuthField(title: "E-mail", icon: "envelope", text: $email, keyboard: .emailAddress, capitalization: .never)
                    AuthField(title: "Senha", icon: "lock", text: $password, secure: true)
                }

                if mode == .signUp {
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("Aceitar termos", isOn: $acceptedTerms).labelsHidden().tint(YePlyTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Li e concordo com os Termos de Serviço e a Política de Direitos Autorais.")
                                .font(.footnote).foregroundStyle(YePlyTheme.secondary)
                            Button("Ler os termos completos") { showingTerms = true }
                                .font(.footnote.weight(.semibold)).foregroundStyle(YePlyTheme.accent)
                        }
                    }
                    .padding(13)
                    .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let message = session.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                }
                if didRequestConfirmation {
                    Label("Conta criada. Confira seu e-mail para confirmar o acesso.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                Button(action: submit) {
                    HStack {
                        if isWorking { ProgressView().tint(.black) }
                        Text(mode == .signIn ? "Entrar" : "Criar conta").fontWeight(.bold)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isWorking || !isValid)
                .opacity(isValid ? 1 : 0.45)

                Button(mode == .signIn ? "Ainda não tenho conta" : "Já tenho uma conta") {
                    withAnimation(.snappy) { mode = mode == .signIn ? .signUp : .signIn; session.errorMessage = nil }
                }
                .foregroundStyle(YePlyTheme.secondary)
                .frame(maxWidth: .infinity)

                if container.isDemoBackend {
                    VStack(spacing: 12) {
                        HStack { Rectangle().fill(YePlyTheme.line).frame(height: 1); Text("PRÉVIA").font(.caption2).tracking(1.5).foregroundStyle(YePlyTheme.tertiary); Rectangle().fill(YePlyTheme.line).frame(height: 1) }
                        Button("Explorar a demonstração") { session.enterDemo() }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingTerms) {
            NavigationStack {
                LegalTermsView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { showingTerms = false } } }
            }
        }
        .yeplyBackground()
    }

    private var isValid: Bool {
        email.contains("@") && password.count >= 8 && (mode == .signIn || (acceptedTerms && !name.trimmingCharacters(in: .whitespaces).isEmpty && username.count >= 3))
    }

    private func submit() {
        isWorking = true
        Task {
            if mode == .signIn {
                await session.signIn(email: email, password: password)
            } else {
                didRequestConfirmation = await session.signUp(name: name, username: username, email: email, password: password)
            }
            isWorking = false
        }
    }
}

private struct AuthField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(YePlyTheme.tertiary).frame(width: 20)
            Group {
                if secure { SecureField(title, text: $text) }
                else { TextField(title, text: $text).keyboardType(keyboard).textInputAutocapitalization(capitalization) }
            }
            .textContentType(secure ? .password : keyboard == .emailAddress ? .emailAddress : nil)
            .autocorrectionDisabled(keyboard == .emailAddress)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(YePlyTheme.line))
    }
}
