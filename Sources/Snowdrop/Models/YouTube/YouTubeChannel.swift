import Foundation

// MARK: - YouTubeChannel

/// A YouTube channel as it appears in search results and on watch pages.
struct YouTubeChannel: Identifiable, Hashable {
    let channelId: String
    let name: String
    /// Channel handle, e.g. "@veritasium".
    let handle: String?
    /// Display subscriber count, e.g. "20.8M subscribers".
    let subscriberCountText: String?
    let descriptionSnippet: String?
    let thumbnailURL: URL?
    /// Wide header image of the channel page. Only the channel page fills it in.
    let bannerURL: URL?
    /// Whether the channel carries the verified badge. Best-effort: false when the page doesn't show one.
    let isVerified: Bool
    /// Display video count, e.g. "2.6K videos". Best-effort, `nil` when not found.
    let videoCountText: String?

    var id: String {
        self.channelId
    }

    init(
        channelId: String,
        name: String,
        handle: String? = nil,
        subscriberCountText: String? = nil,
        descriptionSnippet: String? = nil,
        thumbnailURL: URL? = nil,
        bannerURL: URL? = nil,
        isVerified: Bool = false,
        videoCountText: String? = nil
    ) {
        self.channelId = channelId
        self.name = name
        self.handle = handle
        self.subscriberCountText = subscriberCountText
        self.descriptionSnippet = descriptionSnippet
        self.thumbnailURL = thumbnailURL
        self.bannerURL = bannerURL
        self.isVerified = isVerified
        self.videoCountText = videoCountText
    }
}

// MARK: - YouTubeChannelDetail

/// A channel page: metadata plus the videos visible on the landing tab.
struct YouTubeChannelDetail: Hashable {
    let channel: YouTubeChannel
    let videos: [YouTubeVideo]
    /// Tabs the channel page offers (Videos, Shorts, Live, Playlists, …), in page order.
    var tabs: [YouTubeChannelTab] = []
    /// Whether the signed-in user subscribes. Best-effort: false when the page doesn't say.
    var isSubscribed: Bool = false
}

// MARK: - YouTubeChannelTab

/// One tab of a channel page, browsed with the `params` the page itself provides.
struct YouTubeChannelTab: Identifiable, Hashable {
    enum Kind: Hashable {
        case home, videos, shorts, live, playlists, podcasts, posts, other
    }

    let title: String
    let params: String
    let kind: Kind

    var id: String {
        self.params
    }

    /// Decodes the tab kind from the params payload (it embeds the tab's ASCII name),
    /// which keeps it independent of the display language.
    static func kind(fromParams params: String) -> Kind {
        var base64 = params.removingPercentEncoding ?? params
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let text = String(data: data.prefix(24), encoding: .isoLatin1)
        else { return .other }
        for (name, kind) in [
            ("featured", Kind.home), ("videos", .videos), ("shorts", .shorts), ("streams", .live),
            ("playlists", .playlists), ("podcasts", .podcasts), ("posts", .posts),
        ] where text.contains(name) {
            return kind
        }
        return .other
    }
}

// MARK: - YouTubeChannelTabContent

/// Items of one channel tab (a page of it, plus the token for the next).
struct YouTubeChannelTabContent: Hashable {
    var videos: [YouTubeVideo] = []
    var shorts: [YouTubeVideo] = []
    var playlists: [YouTubePlaylist] = []
    var continuation: String?

    var isEmpty: Bool {
        self.videos.isEmpty && self.shorts.isEmpty && self.playlists.isEmpty
    }
}
