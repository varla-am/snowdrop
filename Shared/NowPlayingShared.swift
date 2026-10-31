import AppIntents
import Foundation

// Code shared by the app and the widget extension.

// MARK: - SnowdropShared

enum SnowdropShared {
    /// macOS app groups prefixed with the team ID need no provisioning profile.
    static let appGroupID = "G66D3PLMB8.group.com.varlaam.Snowdrop"
    static let widgetKind = "SnowdropNowPlaying"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupID)
    }

    static var snapshotURL: URL? {
        self.containerURL?.appendingPathComponent("nowplaying.json")
    }

    static var artworkURL: URL? {
        self.containerURL?.appendingPathComponent("artwork.jpg")
    }
}

// MARK: - NowPlayingSnapshot

/// What the widget shows. The app writes it when the track or play state changes;
/// the widget animates the progress bar by itself from `progress` and `updatedAt`.
struct NowPlayingSnapshot: Codable, Equatable, Sendable {
    struct UpNext: Codable, Equatable, Sendable {
        var title: String
        var artist: String
    }

    var hasTrack: Bool
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// Seconds played when the snapshot was written.
    var progress: Double
    var duration: Double
    var updatedAt: Date
    var upNext: [UpNext]
    /// Theme accent as sRGB components.
    var accent: [Double]
    /// Identifies the artwork file's track, so the widget can tell when it is stale.
    var artworkID: String

    static let idle = NowPlayingSnapshot(
        hasTrack: false, title: "", artist: "", album: "", isPlaying: false,
        progress: 0, duration: 0, updatedAt: Date(), upNext: [],
        accent: [0.42, 0.72, 0.95], artworkID: ""
    )

    static func load() -> NowPlayingSnapshot {
        guard let url = SnowdropShared.snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
        else { return .idle }
        return snapshot
    }

    func save() {
        guard let url = SnowdropShared.snapshotURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Widget intents

enum WidgetCommand: Sendable {
    case togglePlayPause
    case next
    case previous
}

/// The app installs the handler at launch. The intents below run inside the app
/// process (they are `AudioPlaybackIntent`s), so the handler is set when they fire.
@MainActor
enum WidgetIntentRouter {
    static var handler: ((WidgetCommand) -> Void)?
}

struct WidgetTogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetIntentRouter.handler?(.togglePlayPause)
        return .result()
    }
}

struct WidgetNextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetIntentRouter.handler?(.next)
        return .result()
    }
}

struct WidgetPreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetIntentRouter.handler?(.previous)
        return .result()
    }
}
