import AVFoundation
import MediaPlayer
import Foundation

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var queue: [Track] = []
    private var repository: (any MusicRepository)?

    init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
    }

    func play(_ track: Track, queue: [Track], repository: any MusicRepository) async {
        errorMessage = nil
        self.queue = queue
        self.repository = repository
        do {
            let url = try await repository.signedAudioURL(for: track)
            replaceItem(url: url, track: track)
            player?.play()
            isPlaying = true
            updateNowPlaying()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle() {
        guard player != nil else { return }
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        player?.seek(to: CMTime(seconds: duration * min(max(fraction, 0), 1), preferredTimescale: 600))
    }

    func next() { Task { await move(by: 1) } }
    func previous() {
        if progress > 0.05 { seek(to: 0) }
        else { Task { await move(by: -1) } }
    }

    private func move(by offset: Int) async {
        guard let currentTrack, let repository, let index = queue.firstIndex(of: currentTrack) else { return }
        let nextIndex = index + offset
        guard queue.indices.contains(nextIndex) else { return }
        await play(queue[nextIndex], queue: queue, repository: repository)
    }

    private func replaceItem(url: URL, track: Track) {
        if let timeObserver { player?.removeTimeObserver(timeObserver); self.timeObserver = nil }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        currentTrack = track
        duration = track.durationSeconds
        progress = 0
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 10), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = max(0, time.seconds)
                self.progress = self.duration > 0 ? min(seconds / self.duration, 1) : 0
                self.updateNowPlaying(elapsed: seconds)
            }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Não foi possível configurar o áudio: \(error.localizedDescription)"
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
    }

    private func updateNowPlaying(elapsed: Double = 0) {
        guard let currentTrack else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artistName,
            MPMediaItemPropertyAlbumTitle: currentTrack.albumName ?? "YePly",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
