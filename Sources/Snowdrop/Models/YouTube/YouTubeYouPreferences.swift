import Foundation
import Observation

// MARK: - YouTubeYouSource

/// One thing the You page can show as a tile or as a video row:
/// watch history, Watch Later, Liked videos, or one of the user's playlists.
struct YouTubeYouSource: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    /// Thumbnail of a regular playlist; the built-ins draw an icon instead.
    var thumbnailURL: URL?

    var isHistory: Bool {
        self.id == YouTubeYouPreferences.historyID
    }

    var isBuiltIn: Bool {
        YouTubeYouPreferences.builtInIDs.contains(self.id)
    }

    static let history = YouTubeYouSource(
        id: YouTubeYouPreferences.historyID,
        title: String(localized: "History"),
        systemImage: "clock.arrow.circlepath"
    )
    static let watchLater = YouTubeYouSource(
        id: YouTubeYouPreferences.watchLaterID,
        title: String(localized: "Watch Later"),
        systemImage: "clock"
    )
    static let liked = YouTubeYouSource(
        id: YouTubeYouPreferences.likedID,
        title: String(localized: "Liked"),
        systemImage: "hand.thumbsup.fill"
    )

    static func playlist(_ playlist: YouTubePlaylist) -> YouTubeYouSource {
        YouTubeYouSource(
            id: playlist.playlistId,
            title: playlist.title,
            systemImage: "list.and.film",
            thumbnailURL: playlist.thumbnailURL
        )
    }
}

// MARK: - YouTubeYouChannel

/// A channel pinned to the You page.
struct YouTubeYouChannel: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let thumbnailURL: URL?

    init(_ channel: YouTubeChannel) {
        self.id = channel.channelId
        self.name = channel.name
        self.thumbnailURL = channel.thumbnailURL
    }
}

// MARK: - YouTubeYouPreferences

/// What the user picked in "Personalize You". `nil` means "not customised yet":
/// the page then falls back to its defaults.
@MainActor
@Observable
final class YouTubeYouPreferences {
    static let shared = YouTubeYouPreferences()

    nonisolated static let historyID = "history"
    nonisolated static let watchLaterID = "WL"
    nonisolated static let likedID = "LL"
    nonisolated static let builtInIDs = [historyID, watchLaterID, likedID]

    static let maxVideoSources = 5

    /// Channels in the right-hand column, in the user's order. They are stored whole
    /// (not just ids) because a channel found through search isn't in the subscription list.
    var channels: [YouTubeYouChannel]? {
        didSet {
            if let channels, let data = try? JSONEncoder().encode(channels) {
                UserDefaults.standard.set(data, forKey: "youtube.you.channelList")
            } else {
                UserDefaults.standard.removeObject(forKey: "youtube.you.channelList")
            }
        }
    }

    /// Tiles in the top row.
    var tileIds: [String]? {
        didSet { Self.store(self.tileIds, key: "youtube.you.tiles") }
    }

    /// Sources the green pill switches between in the video row.
    var videoSourceIds: [String]? {
        didSet { Self.store(self.videoSourceIds, key: "youtube.you.videoSources") }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.channels = defaults.data(forKey: "youtube.you.channelList")
            .flatMap { try? JSONDecoder().decode([YouTubeYouChannel].self, from: $0) }
        self.tileIds = defaults.stringArray(forKey: "youtube.you.tiles")
        self.videoSourceIds = defaults.stringArray(forKey: "youtube.you.videoSources")
    }

    var isCustomised: Bool {
        self.channels != nil || self.tileIds != nil || self.videoSourceIds != nil
    }

    func reset() {
        self.channels = nil
        self.tileIds = nil
        self.videoSourceIds = nil
    }

    private static func store(_ value: [String]?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
