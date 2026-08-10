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
    @Published private(set) var currentWaveform: [Double] = []
    @Published var gaplessPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(gaplessPlaybackEnabled, forKey: "yeply.playback.gapless")
            player?.automaticallyWaitsToMinimizeStalling = !gaplessPlaybackEnabled
            if gaplessPlaybackEnabled { Task { await preloadNextTrack() } }
            else { preloadedNext = nil }
        }
    }
    @Published var fadeDuration: Double {
        didSet { UserDefaults.standard.set(fadeDuration, forKey: "yeply.playback.fadeDuration") }
    }
    @Published var errorMessage: String?
    @Published var cardRewardMessage: String?

    private struct PlaybackContext {
        let artworkPath: String?
        let collectionTitle: String?
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var repository: (any MusicRepository)?
    private let offlineLibrary: OfflineLibraryStore
    private var contexts: [UUID: PlaybackContext] = [:]
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var preloadedNext: (trackID: UUID, url: URL)?
    private var fadeTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var cardListeningTask: Task<Void, Never>?
    private var cardListeningSeconds: Double = 0
    private var lastReportedCardListeningSeconds = 0

    init(offlineLibrary: OfflineLibraryStore) {
        self.offlineLibrary = offlineLibrary
        let defaults = UserDefaults.standard
        self.gaplessPlaybackEnabled = defaults.object(forKey: "yeply.playback.gapless") == nil ? true : defaults.bool(forKey: "yeply.playback.gapless")
        self.fadeDuration = defaults.object(forKey: "yeply.playback.fadeDuration") == nil ? 0 : defaults.double(forKey: "yeply.playback.fadeDuration")
        configureAudioSession()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        artworkTask?.cancel()
        fadeTask?.cancel()
        waveformTask?.cancel()
        historyTask?.cancel()
        cardListeningTask?.cancel()
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

    func seek(toSeconds seconds: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(seconds / duration, 0), 1))
    }

    func next() { Task { await move(by: 1) } }

    func previous() {
        if elapsedTime > 4 { seek(to: 0) }
        else { Task { await move(by: -1) } }
    }

    func toggleRepeatOne() {
        isRepeatingOne.toggle()
    }

    func recordNowPlayingShare() async {
        guard offlineLibrary.isConnected, let currentTrack, let repository else { return }
        do {
            let reward = try await repository.recordNowPlayingShare(trackID: currentTrack.id)
            if reward.achievementKey != nil || reward.rewardClaimed == true {
                cardRewardMessage = reward.message ?? "Conquista Show Off liberada."
            }
        } catch { }
    }

    private func start(_ track: Track) async {
        guard let repository else { return }
        errorMessage = nil
        do {
            let url: URL
            if let localURL = offlineLibrary.localAudioURL(for: track) {
                url = localURL
                self.preloadedNext = nil
            } else if let preloadedNext, preloadedNext.trackID == track.id {
                url = preloadedNext.url
                self.preloadedNext = nil
            } else {
                guard offlineLibrary.isConnected else {
                    throw YePlyError.message("Esta música não foi baixada para ouvir offline.")
                }
                url = try await repository.signedAudioURL(for: track)
            }
            if currentTrack?.id != track.id, isPlaying, fadeDuration > 0, (self.player?.volume ?? 0) > 0.05 {
                await fadeVolume(to: 0, duration: min(fadeDuration, 1.5))
            }
            let context = contexts[track.id]
            currentArtworkPath = context?.artworkPath ?? track.artworkPath
            currentCollectionTitle = context?.collectionTitle ?? track.albumName
            replaceItem(url: url, track: track)
            player?.volume = fadeDuration > 0 ? 0 : 1
            player?.play()
            isPlaying = true
            if fadeDuration > 0 {
                fadeTask?.cancel()
                fadeTask = Task { [weak self] in
                    guard let self else { return }
                    await self.fadeVolume(to: 1, duration: self.fadeDuration)
                }
            }
            updateNowPlaying()
            loadNowPlayingArtwork()
            loadWaveform(for: track, url: url)
            if offlineLibrary.isConnected {
                historyTask?.cancel()
                historyTask = Task { try? await repository.recordPlayback(trackID: track.id, positionSeconds: 0) }
            }
            if gaplessPlaybackEnabled { Task { await preloadNextTrack() } }
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
        item.preferredForwardBufferDuration = gaplessPlaybackEnabled ? 8 : 0
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = !gaplessPlaybackEnabled
        currentTrack = track
        cardListeningSeconds = 0
        lastReportedCardListeningSeconds = 0
        cardListeningTask?.cancel()
        currentWaveform = track.waveformSamples?.isEmpty == false ? track.waveformSamples! : fallbackWaveform(for: track.id)
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
                if self.isPlaying, self.offlineLibrary.isConnected {
                    self.cardListeningSeconds += 0.5
                    self.reportCardListeningIfNeeded()
                }
                if self.fadeDuration > 0, self.hasNext, self.isPlaying {
                    let remaining = max(0, self.duration - seconds)
                    if remaining <= self.fadeDuration {
                        self.player?.volume = Float(min(max(remaining / self.fadeDuration, 0), 1))
                    }
                }
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

    private func reportCardListeningIfNeeded() {
        let listenedSeconds = Int(cardListeningSeconds)
        guard listenedSeconds >= lastReportedCardListeningSeconds + 60,
              cardListeningTask == nil,
              let trackID = currentTrack?.id,
              let repository else { return }
        let intervalSeconds = min(max(listenedSeconds - lastReportedCardListeningSeconds, 15), 90)
        lastReportedCardListeningSeconds = listenedSeconds
        cardListeningTask = Task { [weak self] in
            defer { self?.cardListeningTask = nil }
            do {
                let reward = try await repository.recordCardListening(trackID: trackID, listenedSeconds: intervalSeconds)
                if reward.packDropped == true {
                    self?.cardRewardMessage = reward.message ?? "Você ganhou um novo pack ouvindo música."
                } else if let achievementKey = reward.achievementKey {
                    self?.cardRewardMessage = reward.message ?? "Nova conquista: \(achievementKey)."
                }
            } catch { }
        }
    }

    private func preloadNextTrack() async {
        guard gaplessPlaybackEnabled, let currentIndex, queue.indices.contains(currentIndex + 1), let repository else {
            preloadedNext = nil
            return
        }
        let nextTrack = queue[currentIndex + 1]
        do {
            let url: URL
            if let localURL = offlineLibrary.localAudioURL(for: nextTrack) { url = localURL }
            else { url = try await repository.signedAudioURL(for: nextTrack) }
            guard currentTrack != nil, queue.indices.contains(currentIndex + 1), queue[currentIndex + 1].id == nextTrack.id else { return }
            preloadedNext = (nextTrack.id, url)
        } catch { preloadedNext = nil }
    }

    private func fadeVolume(to target: Float, duration: Double) async {
        guard duration > 0, let player else { player?.volume = target; return }
        let start = player.volume
        let steps = max(4, Int(duration * 20))
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            player.volume = start + (target - start) * Float(step) / Float(steps)
            try? await Task.sleep(for: .milliseconds(Int((duration * 1_000) / Double(steps))))
        }
        player.volume = target
    }

    private func loadWaveform(for track: Track, url: URL) {
        waveformTask?.cancel()
        guard track.waveformSamples?.isEmpty != false, url.isFileURL else { return }
        waveformTask = Task { [weak self] in
            guard let samples = await WaveformAnalyzer.samples(from: url), !Task.isCancelled else { return }
            self?.currentWaveform = samples
        }
    }

    private func fallbackWaveform(for id: UUID) -> [Double] {
        var state = UInt64(bitPattern: Int64(id.uuidString.hashValue))
        return (0..<96).map { index in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let random = Double((state >> 33) % 1_000) / 1_000
            let shape = 0.45 + 0.35 * sin(Double(index) * 0.22)
            return min(1, max(0.1, shape + random * 0.35))
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
        guard let currentTrack else { return }
        if let localURL = offlineLibrary.localCoverURL(for: currentTrack.playlistId),
           let data = try? Data(contentsOf: localURL), let image = UIImage(data: data) {
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            updateNowPlaying(elapsed: elapsedTime)
            return
        }
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
