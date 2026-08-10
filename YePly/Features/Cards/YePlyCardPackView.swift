import SwiftUI

/// Estado visual da embalagem. O estado de persistência do pack continua sendo
/// controlado pela tela que integra este componente.
enum YePlyCardPackVisualState: Equatable, Sendable {
    case sealed
    case tearing(progress: Double)
    case opened

    var tearProgress: Double {
        switch self {
        case .sealed: 0
        case let .tearing(progress): min(max(progress, 0), 1)
        case .opened: 1
        }
    }
}

/// Embalagem nativa do YePly, criada apenas com SwiftUI. Pode ser usada nos
/// cards da lista, na abertura individual e na pilha de "abrir todos".
struct YePlyCardPackView: View {
    let pack: CardPackSummary
    var state: YePlyCardPackVisualState = .sealed
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let progress = state.tearProgress

            ZStack {
                packBody(size: size)

                packSeal(size: size)
                    .offset(
                        x: progress * size.width * 0.15,
                        y: -progress * size.height * 0.27
                    )
                    .rotationEffect(.degrees(reduceMotion ? 0 : progress * 13), anchor: .bottomLeading)
                    .opacity(1 - progress * 0.35)

                if progress > 0.02 {
                    tornOpening(size: size)
                        .opacity(progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size.width * 0.085, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size.width * 0.085, style: .continuous)
                    .strokeBorder(.white.opacity(0.24), lineWidth: compact ? 1 : 1.5)
            }
            .shadow(color: YePlyTheme.accentSoft.opacity(0.28), radius: compact ? 12 : 26, y: 12)
        }
        .aspectRatio(0.68, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pack YePly com \(pack.cardCount) cartas")
        .accessibilityValue(state.tearProgress >= 1 ? "Aberto" : "Fechado")
    }

    private func packBody(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.09, blue: 0.29),
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.31, green: 0.09, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            FoilMesh()
                .opacity(0.72)

            LinearGradient(
                colors: [.clear, .white.opacity(0.22), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .rotationEffect(.degrees(-24))
            .offset(x: -size.width * 0.25)

            RoundedRectangle(cornerRadius: size.width * 0.07, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [YePlyTheme.accent, .pink, YePlyTheme.accentSoft, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: compact ? 2 : 3
                )
                .padding(size.width * 0.055)

            VStack(spacing: size.height * 0.025) {
                Spacer(minLength: size.height * 0.18)

                ZStack {
                    Circle()
                        .fill(.black.opacity(0.42))
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        }
                    Image(systemName: "waveform")
                        .font(.system(size: size.width * 0.13, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, YePlyTheme.accent, .purple.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: size.width * 0.34, height: size.width * 0.34)

                VStack(spacing: compact ? 2 : 5) {
                    Text("YEPLY")
                        .font(.system(size: size.width * 0.14, weight: .black, design: .rounded))
                        .tracking(size.width * 0.012)
                    Text("MUSIC CARDS")
                        .font(.system(size: size.width * 0.038, weight: .heavy, design: .rounded))
                        .tracking(size.width * 0.012)
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                    Text("\(pack.cardCount) CARTAS")
                }
                .font(.system(size: size.width * 0.042, weight: .black, design: .rounded))
                .tracking(0.8)
                .padding(.horizontal, size.width * 0.07)
                .padding(.vertical, size.height * 0.018)
                .background(.black.opacity(0.38), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.16)) }

                Text(pack.source.uppercased())
                    .font(.system(size: size.width * 0.032, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .padding(.bottom, size.height * 0.065)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, size.width * 0.08)
        }
    }

    private func packSeal(size: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.12, blue: 0.42),
                        Color(red: 0.95, green: 0.28, blue: 0.42),
                        Color(red: 0.40, green: 0.25, blue: 0.93)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: size.width * 0.025) {
                    Image(systemName: "chevron.right.2")
                    Text("RASGUE AQUI")
                    Image(systemName: "chevron.right.2")
                }
                .font(.system(size: size.width * 0.035, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.88))
            }
            .frame(height: size.height * 0.16)

            JaggedEdge()
                .fill(Color(red: 0.74, green: 0.20, blue: 0.50))
                .frame(height: max(8, size.height * 0.025))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tornOpening(size: CGSize) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.95), Color(red: 0.17, green: 0.07, blue: 0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size.height * 0.16)

            JaggedEdge()
                .fill(.black.opacity(0.92))
                .frame(height: max(8, size.height * 0.025))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct JaggedEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.35))

        let teeth = 18
        for index in stride(from: teeth, through: 0, by: -1) {
            let x = rect.width * CGFloat(index) / CGFloat(teeth)
            let y = index.isMultiple(of: 2) ? rect.maxY : rect.maxY * 0.42
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }
}

private struct FoilMesh: View {
    var body: some View {
        Canvas { context, size in
            let colors: [Color] = [YePlyTheme.accent, .purple, .cyan, .pink, .orange]
            for index in 0..<24 {
                let seed = CGFloat(index)
                let diameter = 18 + (seed.truncatingRemainder(dividingBy: 5) * 8)
                let x = (seed * 73).truncatingRemainder(dividingBy: max(size.width, 1))
                let y = (seed * 113).truncatingRemainder(dividingBy: max(size.height, 1))
                let rect = CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(colors[index % colors.count].opacity(0.08))
                )
            }

            for index in 0..<8 {
                var stripe = Path()
                let x = CGFloat(index) * size.width / 7
                stripe.move(to: CGPoint(x: x - size.height * 0.18, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height * 0.18, y: 0))
                context.stroke(stripe, with: .color(.white.opacity(0.045)), lineWidth: 2)
            }
        }
    }
}

#if DEBUG
#Preview("Pack premium") {
    YePlyCardPackView(
        pack: CardPackSummary(
            packId: UUID(),
            source: "Sequência diária",
            cardCount: 3,
            createdAt: .now
        )
    )
    .frame(width: 260)
    .padding(40)
    .yeplyBackground()
}
#endif
