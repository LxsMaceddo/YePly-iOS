import Foundation
import Network

struct OfflinePlaylistManifest: Codable, Sendable {
    let userID: UUID
    let playlist: Playlist
    let tracks: [Track]
    let audioFiles: [String: String]
    let coverFileName: String?
    let downloadedAt: Date
}

enum OfflinePlaylistState: Equatable {
    case notDownloaded
    case downloading(Double)
    case downloaded
    case failed(String)
}

@MainActor
final class OfflineLibraryStore: ObservableObject {
    @Published private(set) var isConnected = true
    @Published private(set) var revision = 0
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.yeply.connectivity")
    private let rootDirectory: URL
    private var manifests: [String: OfflinePlaylistManifest] = [:]
    private var progressByPlaylist: [UUID: Double] = [:]
    private var failuresByPlaylist: [UUID: String] = [:]
    private var activeUserID: UUID?

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = applicationSupport.appendingPathComponent("YePlyOffline", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        excludeFromBackup(rootDirectory)
        cleanupInterruptedDownloads()
        loadManifests()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isConnected != connected else { return }
                self.isConnected = connected
                self.revision += 1
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit { monitor.cancel() }

    var isOfflineMode: Bool { !isConnected }

    var downloadedPlaylistCount: Int {
        visibleManifests.values.filter { !playableTracks(in: $0).isEmpty }.count
    }

    var downloadedTrackCount: Int {
        visibleManifests.values.reduce(0) { $0 + playableTracks(in: $1).count }
    }

    var downloadedSizeBytes: Int64 {
        visibleManifests.values.reduce(0) { result, manifest in
            result + manifest.audioFiles.values.reduce(0) { size, filename in
                let url = playlistDirectory(userID: manifest.userID, playlistID: manifest.playlist.id).appendingPathComponent(filename)
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                let value = Int64(values?.fileSize ?? 0)
                return size + value
            }
        }
    }

    func activate(userID: UUID?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        revision += 1
    }

    func playlists(for scope: LibraryScope) -> [Playlist] {
        guard let activeUserID else { return [] }
        let values = visibleManifests.values.compactMap { manifest -> Playlist? in
            let tracks = playableTracks(in: manifest)
            guard !tracks.isEmpty else { return nil }
            var playlist = manifest.playlist
            playlist.trackCount = tracks.count
            return playlist
        }
        switch scope {
        case .all: return values
        case .mine: return values.filter { $0.ownerId == activeUserID }
        case .shared: return values.filter { $0.ownerId != activeUserID }
        }
    }

    func tracks(for playlistID: UUID) -> [Track]? {
        guard let manifest = visibleManifests[playlistID] else { return nil }
        let tracks = playableTracks(in: manifest)
        return tracks.isEmpty ? nil : tracks
    }

    func state(for playlistID: UUID) -> OfflinePlaylistState {
        if let progress = progressByPlaylist[playlistID] { return .downloading(progress) }
        if let manifest = visibleManifests[playlistID], !playableTracks(in: manifest).isEmpty { return .downloaded }
        if let failure = failuresByPlaylist[playlistID] { return .failed(failure) }
        return .notDownloaded
    }

    func isPlaylistDownloaded(_ playlistID: UUID) -> Bool {
        guard let manifest = visibleManifests[playlistID] else { return false }
        return !playableTracks(in: manifest).isEmpty
    }

    func isTrackDownloaded(_ track: Track) -> Bool { localAudioURL(for: track) != nil }

    func localAudioURL(for track: Track) -> URL? {
        guard let manifest = visibleManifests[track.playlistId],
              let filename = manifest.audioFiles[track.id.uuidString.lowercased()]
        else { return nil }
        let url = playlistDirectory(userID: manifest.userID, playlistID: track.playlistId).appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func localCoverURL(for playlistID: UUID) -> URL? {
        guard let manifest = visibleManifests[playlistID], let filename = manifest.coverFileName else { return nil }
        let url = playlistDirectory(userID: manifest.userID, playlistID: playlistID).appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func downloadPlaylist(_ playlist: Playlist, tracks: [Track], repository: any MusicRepository) async {
        guard let userID = activeUserID else { errorMessage = YePlyError.noActiveUser.localizedDescription; return }
        guard isConnected else { errorMessage = "Conecte-se à internet para iniciar o download."; return }
        guard !tracks.isEmpty else { errorMessage = "Esta playlist ainda não possui músicas para baixar."; return }
        guard progressByPlaylist[playlist.id] == nil else { return }

        errorMessage = nil
        failuresByPlaylist[playlist.id] = nil
        progressByPlaylist[playlist.id] = 0
        revision += 1

        let userDirectory = rootDirectory.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
        let stagingDirectory = userDirectory.appendingPathComponent(".\(playlist.id.uuidString.lowercased())-\(UUID().uuidString.lowercased())", isDirectory: true)
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            var audioFiles: [String: String] = [:]
            let includesCover = playlist.coverPath != nil
            let totalSteps = max(1, tracks.count + (includesCover ? 1 : 0))
            var completedSteps = 0

            for track in tracks.sorted(by: { $0.position < $1.position }) {
                let filename = try await downloadAudioFile(for: track, to: stagingDirectory, repository: repository)
                audioFiles[track.id.uuidString.lowercased()] = filename
                completedSteps += 1
                progressByPlaylist[playlist.id] = Double(completedSteps) / Double(totalSteps)
                revision += 1
            }

            var coverFileName: String?
            if let coverPath = playlist.coverPath {
                // Artwork is optional: a temporary cover failure must never
                // discard audio files that were downloaded successfully.
                coverFileName = try? await downloadCoverFile(path: coverPath, to: stagingDirectory, repository: repository)
                completedSteps += 1
                progressByPlaylist[playlist.id] = Double(completedSteps) / Double(totalSteps)
            }

            let manifest = OfflinePlaylistManifest(
                userID: userID,
                playlist: playlist,
                tracks: tracks.sorted { $0.position < $1.position },
                audioFiles: audioFiles,
                coverFileName: coverFileName,
                downloadedAt: .now
            )
            let manifestData = try JSONEncoder.yeply.encode(manifest)
            try manifestData.write(to: stagingDirectory.appendingPathComponent("manifest.json"), options: .atomic)

            let destination = playlistDirectory(userID: userID, playlistID: playlist.id)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: stagingDirectory, to: destination)
            protectOfflineFiles(in: destination)
            excludeFromBackup(destination)
            manifests[manifestKey(userID: userID, playlistID: playlist.id)] = manifest
            progressByPlaylist[playlist.id] = nil
            revision += 1
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            progressByPlaylist[playlist.id] = nil
            let message = error.localizedDescription
            failuresByPlaylist[playlist.id] = message
            errorMessage = message
            revision += 1
        }
    }

    func downloadTrack(_ track: Track, in playlist: Playlist, repository: any MusicRepository) async {
        guard let userID = activeUserID else { errorMessage = YePlyError.noActiveUser.localizedDescription; return }
        guard isConnected else { errorMessage = "Conecte-se à internet para iniciar o download."; return }
        guard progressByPlaylist[playlist.id] == nil else { return }
        if isTrackDownloaded(track) { return }

        errorMessage = nil
        failuresByPlaylist[playlist.id] = nil
        progressByPlaylist[playlist.id] = 0
        revision += 1

        let directory = playlistDirectory(userID: userID, playlistID: playlist.id)
        let key = manifestKey(userID: userID, playlistID: playlist.id)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var audioFiles = manifests[key]?.audioFiles ?? [:]
            let filename = try await downloadAudioFile(for: track, to: directory, repository: repository)
            audioFiles[track.id.uuidString.lowercased()] = filename
            progressByPlaylist[playlist.id] = 0.82
            revision += 1

            var coverFileName = manifests[key]?.coverFileName
            if coverFileName == nil, let coverPath = playlist.coverPath {
                coverFileName = try? await downloadCoverFile(path: coverPath, to: directory, repository: repository)
            }

            var savedTracks = manifests[key]?.tracks ?? []
            savedTracks.removeAll { $0.id == track.id }
            savedTracks.append(track)
            savedTracks.sort { $0.position < $1.position }

            let manifest = OfflinePlaylistManifest(
                userID: userID,
                playlist: playlist,
                tracks: savedTracks,
                audioFiles: audioFiles,
                coverFileName: coverFileName,
                downloadedAt: .now
            )
            try writeManifest(manifest, in: directory)
            protectOfflineFiles(in: directory)
            excludeFromBackup(directory)
            manifests[key] = manifest
            progressByPlaylist[playlist.id] = nil
            revision += 1
        } catch {
            progressByPlaylist[playlist.id] = nil
            let message = error.localizedDescription
            failuresByPlaylist[playlist.id] = message
            errorMessage = message
            revision += 1
        }
    }

    func removeDownload(for playlistID: UUID) {
        guard let manifest = visibleManifests[playlistID] else { return }
        let directory = playlistDirectory(userID: manifest.userID, playlistID: playlistID)
        do {
            if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
            manifests[manifestKey(userID: manifest.userID, playlistID: playlistID)] = nil
            failuresByPlaylist[playlistID] = nil
            revision += 1
        } catch { errorMessage = error.localizedDescription }
    }

    private var visibleManifests: [UUID: OfflinePlaylistManifest] {
        guard let activeUserID else { return [:] }
        return Dictionary(uniqueKeysWithValues: manifests.values.filter { $0.userID == activeUserID }.map { ($0.playlist.id, $0) })
    }

    private func manifestKey(userID: UUID, playlistID: UUID) -> String {
        "\(userID.uuidString.lowercased()):\(playlistID.uuidString.lowercased())"
    }

    private func playlistDirectory(userID: UUID, playlistID: UUID) -> URL {
        rootDirectory
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(playlistID.uuidString.lowercased(), isDirectory: true)
    }

    private func playableTracks(in manifest: OfflinePlaylistManifest) -> [Track] {
        manifest.tracks
            .filter { track in
                guard let filename = manifest.audioFiles[track.id.uuidString.lowercased()] else { return false }
                let url = playlistDirectory(userID: manifest.userID, playlistID: manifest.playlist.id).appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: url.path),
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      (values.fileSize ?? 0) > 1_024
                else { return false }
                return true
            }
            .sorted { $0.position < $1.position }
    }

    private func downloadAudioFile(for track: Track, to directory: URL, repository: any MusicRepository) async throws -> String {
        let remoteURL = try await repository.signedAudioURL(for: track)
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        do {
            try validate(response)
            let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 1_024 else {
                throw YePlyError.message("O arquivo de áudio recebido está vazio ou incompleto.")
            }
            let filename = offlineAudioFileName(for: track)
            let destination = directory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            protectOfflineFile(destination)
            return filename
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func downloadCoverFile(path: String, to directory: URL, repository: any MusicRepository) async throws -> String {
        let remoteURL = try await repository.signedCoverURL(path: path)
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        do {
            try validate(response)
            let filename = "cover.jpg"
            let destination = directory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            protectOfflineFile(destination)
            return filename
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func offlineAudioFileName(for track: Track) -> String {
        let candidate = URL(fileURLWithPath: track.audioPath).pathExtension.lowercased()
        let supported = Set(["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"])
        let fileExtension = supported.contains(candidate) ? candidate : "mp3"
        return "\(track.id.uuidString.lowercased()).\(fileExtension)"
    }

    private func writeManifest(_ manifest: OfflinePlaylistManifest, in directory: URL) throws {
        let data = try JSONEncoder.yeply.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func protectOfflineFile(_ url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func protectOfflineFiles(in directory: URL) {
        protectOfflineFile(directory)
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator { protectOfflineFile(url) }
    }

    private func loadManifests() {
        guard let enumerator = fileManager.enumerator(at: rootDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let url as URL in enumerator where url.lastPathComponent == "manifest.json" {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder.yeply.decode(OfflinePlaylistManifest.self, from: data)
            else { continue }
            manifests[manifestKey(userID: manifest.userID, playlistID: manifest.playlist.id)] = manifest
        }
    }

    private func cleanupInterruptedDownloads() {
        guard let userDirectories = try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for userDirectory in userDirectories {
            guard let children = try? fileManager.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for child in children where child.lastPathComponent.hasPrefix(".") {
                try? fileManager.removeItem(at: child)
            }
        }
    }

    private func validate(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw YePlyError.message("O servidor recusou o download (código \(http.statusCode)).")
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}

private extension JSONEncoder {
    static var yeply: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var yeply: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
