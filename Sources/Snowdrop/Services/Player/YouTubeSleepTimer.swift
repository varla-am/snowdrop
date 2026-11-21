import Foundation

// MARK: - YouTubeSleepTimer

/// When the YouTube player should pause by itself.
enum YouTubeSleepTimer: Hashable {
    case off
    case minutes(Int)
    case endOfVideo

    /// Options shown in the settings menu, in order.
    nonisolated static let menuOptions: [YouTubeSleepTimer] = [
        .off, .minutes(5), .minutes(10), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfVideo,
    ]

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case let .minutes(minutes): String(localized: "\(minutes) minutes")
        case .endOfVideo: String(localized: "End of video")
        }
    }
}
