@preconcurrency import AVFoundation
import Foundation

enum WaveformAnalyzer {
    static func samples(from url: URL, count: Int = 96) async -> [Double]? {
        await Task.detached(priority: .utility) {
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let totalFrames = max(1, file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else { return nil }
                var peaks = Array(repeating: Float.zero, count: max(24, count))
                var processed: AVAudioFramePosition = 0

                while processed < totalFrames {
                    try file.read(into: buffer)
                    let frameLength = Int(buffer.frameLength)
                    guard frameLength > 0, let channels = buffer.floatChannelData else { break }
                    let channelCount = Int(format.channelCount)

                    for frame in 0..<frameLength {
                        let absoluteFrame = processed + AVAudioFramePosition(frame)
                        let bucket = min(peaks.count - 1, Int((Double(absoluteFrame) / Double(totalFrames)) * Double(peaks.count)))
                        var peak: Float = 0
                        for channel in 0..<channelCount { peak = max(peak, abs(channels[channel][frame])) }
                        peaks[bucket] = max(peaks[bucket], peak)
                    }
                    processed += AVAudioFramePosition(frameLength)
                }

                let maximum = max(peaks.max() ?? 0, 0.000_1)
                return peaks.map { value in
                    max(0.08, min(1, pow(Double(value / maximum), 0.58)))
                }
            } catch { return nil }
        }.value
    }
}
