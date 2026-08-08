import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = LibraryViewModel()
    @State private var showingCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ADMINISTRAÇÃO").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(YePlyTheme.accent)
                        Text("Catálogo").font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1.2)
                        Text("Gerencie o que aparece no YePly e os links de acesso.").font(.subheadline).foregroundStyle(YePlyTheme.secondary)
                    }
                    Spacer()
                    YePlyLogo(size: 40)
                }

                HStack(spacing: 10) {
                    AdminMetric(value: "\(model.playlists.count)", label: "Playlists", icon: "rectangle.stack.fill")
                    AdminMetric(value: "\(model.playlists.reduce(0) { $0 + ($1.trackCount ?? 0) })", label: "Faixas", icon: "music.note")
                    AdminMetric(value: "\(model.playlists.filter { $0.visibility == .unlisted }.count)", label: "Links", icon: "link")
                }

                Button { showingCreate = true } label: {
                    HStack { Image(systemName: "plus"); Text("Criar playlist do catálogo").fontWeight(.bold); Spacer(); Image(systemName: "arrow.right") }
                        .foregroundStyle(.black).padding(.horizontal, 18).frame(height: 52).background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("SUAS PLAYLISTS").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(YePlyTheme.tertiary)
                    ForEach(model.playlists) { playlist in
                        NavigationLink(value: playlist) {
                            HStack(spacing: 13) {
                                CoverArtwork(playlist: playlist, cornerRadius: 11).frame(width: 58, height: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Label(playlist.visibility.title, systemImage: playlist.visibility.icon).font(.caption).foregroundStyle(YePlyTheme.secondary)
                                }
                                Spacer()
                                Text("\(playlist.trackCount ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(YePlyTheme.tertiary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(YePlyTheme.tertiary)
                            }
                            .padding(10).background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(18).padding(.bottom, 40)
        }
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .navigationBarHidden(true)
        .refreshable { await model.load(scope: .mine, repository: container.repository) }
        .sheet(isPresented: $showingCreate) { CreatePlaylistView { Task { await model.load(scope: .mine, repository: container.repository) } } }
        .task { await model.load(scope: .mine, repository: container.repository) }
        .yeplyBackground()
    }
}

private struct AdminMetric: View {
    let value: String
    let label: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(YePlyTheme.accent)
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(YePlyTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(YePlyTheme.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
