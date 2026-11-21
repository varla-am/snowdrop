import Foundation
import Observation

/// View model for a YouTube channel page.
@MainActor
@Observable
final class YouTubeChannelViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Loaded channel detail.
    private(set) var detail: YouTubeChannelDetail?

    /// Subscription state shown on the Subscribe button (optimistic while toggling).
    private(set) var isSubscribed = false

    /// Loaded content per tab (keyed by the tab's params).
    private(set) var tabContents: [String: YouTubeChannelTabContent] = [:]
    /// Tabs currently being fetched (first page or continuation).
    private(set) var loadingTabs: Set<String> = []
    /// Tabs whose fetch failed, so the view can offer a retry.
    private(set) var failedTabs: Set<String> = []

    let channelId: String
    /// Invalidates stale in-flight loads when a newer one starts
    /// (SwiftUI restarts .task during launch/layout churn; latest wins).
    private var loadGeneration = 0

    let client: any YouTubeClientProtocol
    private let logger = DiagnosticsLogger.api

    init(channelId: String, client: any YouTubeClientProtocol) {
        self.channelId = channelId
        self.client = client
    }

    func load() async {
        self.loadGeneration += 1
        let generation = self.loadGeneration
        self.loadingState = .loading
        do {
            let detail = try await self.client.getChannel(channelId: self.channelId)
            guard generation == self.loadGeneration else { return }
            self.detail = detail
            self.isSubscribed = detail.isSubscribed
            self.loadingState = .loaded
            await self.resolveSubscription()
        } catch {
            guard generation == self.loadGeneration else { return }
            // A cancelled load (view went away mid-flight) is not an
            // error; reset so the next task run reloads.
            if error is CancellationError {
                self.loadingState = .idle
                return
            }
            self.logger.error("Failed to load YouTube channel: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// The page header doesn't reliably carry the subscription state, so check the account's
    /// own subscription list (a guest has none: the call fails and the button stays "Subscribe").
    private func resolveSubscription() async {
        guard !self.isSubscribed,
              let channels = try? await self.client.getSubscribedChannels()
        else { return }
        if channels.contains(where: { $0.channelId == self.channelId }) {
            self.isSubscribed = true
        }
    }

    /// Subscribes/unsubscribes the channel (optimistic with rollback).
    func toggleSubscribed() async {
        let wasSubscribed = self.isSubscribed
        self.isSubscribed = !wasSubscribed
        do {
            try await self.client.setSubscribed(self.isSubscribed, channelId: self.channelId)
            HapticService.toggle()
        } catch {
            self.logger.error("Failed to change subscription: \(error.localizedDescription)")
            self.isSubscribed = wasSubscribed
        }
    }

    // MARK: - Tabs

    /// Loads the first page of a tab, once (re-callable after a failure).
    func loadTab(_ tab: YouTubeChannelTab) async {
        guard self.tabContents[tab.id] == nil, !self.loadingTabs.contains(tab.id) else { return }
        self.loadingTabs.insert(tab.id)
        self.failedTabs.remove(tab.id)
        defer { self.loadingTabs.remove(tab.id) }
        do {
            let content = try await self.client.getChannelTab(channelId: self.channelId, params: tab.params)
            self.tabContents[tab.id] = content
        } catch {
            if error is CancellationError { return }
            self.logger.error("Failed to load YouTube channel tab: \(error.localizedDescription)")
            self.failedTabs.insert(tab.id)
        }
    }

    /// Appends the next page of a tab.
    func loadMoreTab(_ tab: YouTubeChannelTab) async {
        guard let current = self.tabContents[tab.id],
              let token = current.continuation,
              !self.loadingTabs.contains(tab.id)
        else { return }
        self.loadingTabs.insert(tab.id)
        defer { self.loadingTabs.remove(tab.id) }
        do {
            let more = try await self.client.getChannelTabContinuation(continuation: token)
            var merged = current
            let knownVideos = Set(merged.videos.map(\.videoId))
            merged.videos += more.videos.filter { !knownVideos.contains($0.videoId) }
            let knownShorts = Set(merged.shorts.map(\.videoId))
            merged.shorts += more.shorts.filter { !knownShorts.contains($0.videoId) }
            let knownPlaylists = Set(merged.playlists.map(\.playlistId))
            merged.playlists += more.playlists.filter { !knownPlaylists.contains($0.playlistId) }
            merged.continuation = more.continuation
            self.tabContents[tab.id] = merged
        } catch {
            if error is CancellationError { return }
            self.logger.error("Failed to load more of YouTube channel tab: \(error.localizedDescription)")
            // Stop paging instead of retrying in a loop.
            var stopped = current
            stopped.continuation = nil
            self.tabContents[tab.id] = stopped
        }
    }
}
