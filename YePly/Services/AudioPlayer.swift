import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsedTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentArtworkPath: String?
    @Published private(set) var currentCollectionTitle: String?
    @Published private(set) var isRepeatingOne = false
    @Published var errorMessage: String?

    private struct PlaybackContext {
        let artworkPath: String?
        let collectionTitle: String?
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var repository: (any MusicRepository)?
    private var contexts: [UUID: PlaybackContext] = [:]
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?

    init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        artworkTask?.cancel()
    }

    var currentIndex: Int? {
        guard let currentTrack else { return nil }
        return queue.firstIndex(where: { $0.id == currentTrack.id })
    }

    var upcomingTracks: [Track] {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return queue }
        let next = queue.index(after: currentIndex)
        guard next < queue.endIndex else { return [] }
        return Array(queue[next...])
    }

    var hasPrevious: Bool { (currentIndex ?? 0) > 0 || progress > 0.03 }
    var hasNext: Bool { guard let currentIndex else { return false }; return queue.indices.contains(currentIndex + 1) }

    func play(
        _ track: Track,
        queue: [Track],
        repository: any MusicRepository,
        artworkPath: String? = nil,
        collectionTitle: String? = nil
    ) async {
        errorMessage = nil
        self.queue = queue.contains(where: { $0.id == track.id }) ? queue : [track] + queue
        self.repository = repository
        for queuedTrack in self.queue {
            contexts[queuedTrack.id] = PlaybackContext(
                artworkPath: queuedTrack.artworkPath ?? artworkPath,
                collectionTitle: collectionTitle
            )
        }
        await start(track)
    }

    func playFromQueue(_ track: Track) {
        Task { await start(track) }
    }

    func playNext(
        _ track: Track,
        repository: any MusicRepository,
        artworkPath: String? = nil,
        collectionTitle: String? = nil
    ) {
        self.repository = repository
        contexts[track.id] = PlaybackContext(artworkPath: track.artworkPath ?? artworkPath, collectionTitle: collectionTitle)
        guard track.id != currentTrack?.id else { return }
        guard currentIndex != nil else {
            Task { await play(track, queue: [track], repository: repository, artworkPath: artworkPath, collectionTitle: collectionTitle) }
            return
        }
        queue.removeAll { $0.id == track.id && $0.id != currentTrack?.id }
        guard let refreshedCurrentIndex = currentIndex else { return }
        let insertion = min(refreshedCurrentIndex + 1, queue.count)
        queue.insert(track, at: insertion)
    }

    func addToQueue(
        _ track: Track,
        repository: any MusicRepository,
        artworkPath: String? = nil,
        collectionTitle: String? = nil
    ) {
        self.repository = repository
        contexts[track.id] = PlaybackContext(artworkPath: track.artworkPath ?? artworkPath, collectionTitle: collectionTitle)
        if currentTrack == nil {
            Task { await play(track, queue: [track], repository: repository, artworkPath: artworkPath, collectionTitle: collectionTitle) }
        } else if track.id != currentTrack?.id {
            queue.removeAll { $0.id == track.id }
            queue.append(track)
        }
    }

    func removeFromQueue(_ track: Track) {
        guard track.id != currentTrack?.id else { return }
        queue.removeAll { $0.id == track.id }
        contexts[track.id] = nil
    }

    func clearUpcoming() {
        guard let currentTrack else { queue.removeAll(); return }
        queue = [currentTrack]
    }

    func toggle() {
        guard player != nil else { return }
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
        updateNowPlaying(elapsed: elapsedTime)
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let target = duration * min(max(fraction, 0), 1)
        elapsedTime = target
        progress = target / duration
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateNowPlaying(elapsed: target)
    }

    func next() { Task { await move(by: 1) } }

    func previous() {
        if elapsedTime > 4 { seek(to: 0) }
        else { Task { await move(by: -1) } }
    }

    func toggleRepeatOne() {
        isRepeatingOne.toggle()
    }

    private func start(_ track: Track) async {
        guard let repository else { return }
        errorMessage = nil
        do {
            let url = try await repository.signedAudioURL(for: track)
            let context = contexts[track.id]
            currentArtworkPath = context?.artworkPath ?? track.artworkPath
            currentCollectionTitle = context?.collectionTitle ?? track.albumName
            replaceItem(url: url, track: track)
            player?.play()
            isPlaying = true
            updateNowPlaying()
            loadNowPlayingArtwork()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(by offset: Int) async {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + offset
        guard queue.indices.contains(nextIndex) else { return }
        await start(queue[nextIndex])
    }

    private func replaceItem(url: URL, track: Track) {
        if let timeObserver { player?.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        currentTrack = track
        duration = track.durationSeconds
        elapsedTime = 0
        progress = 0
        nowPlayingArtwork = nil

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
                let itemDuration = self.player?.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite, itemDuration > 0 { self.duration = itemDuration }
                self.elapsedTime = seconds
                self.progress = self.duration > 0 ? min(seconds / self.duration, 1) : 0
                self.updateNowPlaying(elapsed: seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isRepeatingOne {
                    self.seek(to: 0)
                    self.player?.play()
                    self.isPlaying = true
                } else if self.hasNext {
                    self.next()
                } else {
                    self.isPlaying = false
                    self.updateNowPlaying(elapsed: self.duration)
                }
            }
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
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                guard let self, self.duration > 0 else { return }
                self.seek(to: event.positionTime / self.duration)
            }
            return .success
        }
    }

    private func loadNowPlayingArtwork() {
        artworkTask?.cancel()
        guard let path = currentArtworkPath, let repository else { return }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await repository.signedCoverURL(path: path)
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                updateNowPlaying(elapsed: elapsedTime)
            } catch { }
        }
    }

    private func updateNowPlaying(elapsed: Double = 0) {
        guard let currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artistName,
            MPMediaItemPropertyAlbumTitle: currentCollectionTitle ?? currentTrack.albumName ?? "YePly",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
