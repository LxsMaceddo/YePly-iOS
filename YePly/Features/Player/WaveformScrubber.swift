import SwiftUI

struct WaveformScrubber: View {
    let samples: [Double]
    let progress: Double
    let onScrub: (Double, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let values = samples.isEmpty ? Array(repeating: 0.35, count: 72) : samples
                let spacing: CGFloat = 2
                let barWidth = max(1, (size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))
                let playedWidth = size.width * min(max(progress, 0), 1)

                for (index, sample) in values.enumerated() {
                    let height = max(4, size.height * CGFloat(min(max(sample, 0.06), 1)))
                    let x = CGFloat(index) * (barWidth + spacing)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let color = x <= playedWidth ? YePlyTheme.accent : Color.white.opacity(0.24)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                }

                let marker = CGRect(x: max(0, min(size.width - 2, playedWidth - 1)), y: 0, width: 2, height: size.height)
                context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(.white))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrub(fraction(for: value.location.x, width: geometry.size.width), true) }
                    .onEnded { value in onScrub(fraction(for: value.location.x, width: geometry.size.width), false) }
            )
        }
        .frame(height: 58)
        .accessibilityLabel("Linha do tempo em forma de onda")
        .accessibilityValue("\(Int(progress * 100)) por cento")
    }

    private func fraction(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}
