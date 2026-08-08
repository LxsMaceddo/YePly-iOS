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

    var downloadedPlaylistCount: Int { visibleManifests.count }

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
        let values = visibleManifests.values.map(\.playlist)
        switch scope {
        case .all: return values
        case .mine: return values.filter { $0.ownerId == activeUserID }
        case .shared: return values.filter { $0.ownerId != activeUserID }
        }
    }

    func tracks(for playlistID: UUID) -> [Track]? {
        visibleManifests[playlistID]?.tracks.sorted { $0.position < $1.position }
    }

    func state(for playlistID: UUID) -> OfflinePlaylistState {
        if let progress = progressByPlaylist[playlistID] { return .downloading(progress) }
        if visibleManifests[playlistID] != nil { return .downloaded }
        if let failure = failuresByPlaylist[playlistID] { return .failed(failure) }
        return .notDownloaded
    }

    func isPlaylistDownloaded(_ playlistID: UUID) -> Bool { visibleManifests[playlistID] != nil }

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
                let remoteURL = try await repository.signedAudioURL(for: track)
                let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
                try validate(response)
                let filename = "\(track.id.uuidString.lowercased()).mp3"
                try fileManager.moveItem(at: temporaryURL, to: stagingDirectory.appendingPathComponent(filename))
                audioFiles[track.id.uuidString.lowercased()] = filename
                completedSteps += 1
                progressByPlaylist[playlist.id] = Double(completedSteps) / Double(totalSteps)
                revision += 1
            }

            var coverFileName: String?
            if let coverPath = playlist.coverPath {
                let remoteURL = try await repository.signedCoverURL(path: coverPath)
                let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
                try validate(response)
                let filename = "cover.jpg"
                try fileManager.moveItem(at: temporaryURL, to: stagingDirectory.appendingPathComponent(filename))
                coverFileName = filename
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
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
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
