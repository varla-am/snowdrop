import Foundation
import Observation

/// Data behind the You page: subscribed channels, the user's playlists, and
/// the videos of whichever source the video row is showing.
@MainActor
@Observable
final class YouTubeYouViewModel {
    private(set) var loadingState: LoadingState = .idle
    private(set) var channels: [YouTubeChannel] = []
    private(set) var playlists: [YouTubePlaylist] = []
    /// Videos per source id; missing = not loaded yet.
    private(set) var videosBySource: [String: [YouTubeVideo]] = [:]
    private(set) var loadingSources: Set<String> = []

    private var loadTask: Task<Void, Never>?
    private var generation = 0

    let client: any YouTubeClientProtocol
    private let logger = DiagnosticsLogger.api

    init(client: any YouTubeClientProtocol) {
        self.client = client
    }

    /// Everything the user can pick from: the built-ins first, then playlists.
    var allSources: [YouTubeYouSource] {
        [YouTubeYouSource.history, .watchLater, .liked]
            + self.playlists.filter { !["WL", "LL"].contains($0.playlistId) }.map(YouTubeYouSource.playlist)
    }

    func load() async {
        if case .loaded = self.loadingState { return }
        if let existing = self.loadTask {
            await existing.value
            return
        }
        self.generation += 1
        let run = self.generation
        let task = Task { await self.performLoad(run: run) }
        self.loadTask = task
        await task.value
    }

    func cancelLoad() {
        self.generation += 1
        self.loadTask?.cancel()
        self.loadTask = nil
    }

    private func performLoad(run: Int) async {
        defer { if self.generation == run { self.loadTask = nil } }
        self.loadingState = .loading
        // Both lists are optional garnish: a failure of one must not blank the page.
        async let channelsResult = self.fetch { try await self.client.getSubscribedChannels() }
        async let playlistsResult = self.fetch { try await self.client.getUserPlaylists() }
        let (channels, playlists) = await (channelsResult, playlistsResult)
        guard run == self.generation, !Task.isCancelled else {
            self.loadingState = .idle
            return
        }
        self.channels = channels ?? []
        self.playlists = playlists ?? []
        self.loadingState = .loaded
    }

    private func fetch<T: Sendable>(_ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            self.logger.error("You page fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Channel search for the Personalize sheet.
    func searchChannels(_ query: String) async -> [YouTubeChannel] {
        do {
            return try await self.client.search(query: query, filter: .channels).channels
        } catch {
            self.logger.error("You page channel search failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Loads the videos of one source (cached after the first success).
    func loadVideos(for sourceId: String, force: Bool = false) async {
        guard force || self.videosBySource[sourceId] == nil, !self.loadingSources.contains(sourceId) else { return }
        self.loadingSources.insert(sourceId)
        defer { self.loadingSources.remove(sourceId) }
        let run = self.generation
        do {
            let videos: [YouTubeVideo]
            if sourceId == YouTubeYouPreferences.historyID {
                videos = try await self.client.getHistory(forceRefresh: force).videos
            } else {
                videos = try await self.client.getPlaylist(playlistId: sourceId, forceRefresh: force).videos
            }
            guard run == self.generation else { return }
            self.videosBySource[sourceId] = videos
        } catch {
            self.logger.error("You page videos failed: \(error.localizedDescription)")
            if run == self.generation, self.videosBySource[sourceId] == nil { self.videosBySource[sourceId] = [] }
        }
    }
}
