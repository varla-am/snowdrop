import Foundation

/// Parses YouTube channel pages (`browse` with a `UC…` browse ID).
///
/// Channel metadata comes from `metadata.channelMetadataRenderer` (stable
/// across header redesigns); landing-tab videos are collected recursively.
enum ChannelPageParser {
    static func parse(_ data: [String: Any], channelId fallbackChannelId: String) -> YouTubeChannelDetail? {
        let metadata = (data["metadata"] as? [String: Any])?["channelMetadataRenderer"]
            as? [String: Any]

        let channelId = metadata?["externalId"] as? String ?? fallbackChannelId
        guard let name = metadata?["title"] as? String else {
            return nil
        }

        let channel = YouTubeChannel(
            channelId: channelId,
            name: name,
            handle: Self.handle(fromVanityURL: metadata?["vanityChannelUrl"] as? String),
            subscriberCountText: Self.subscriberCountText(of: data),
            descriptionSnippet: metadata?["description"] as? String,
            thumbnailURL: YouTubeItemParser.thumbnailURL(fromThumbnail: metadata?["avatar"]),
            bannerURL: Self.bannerURL(of: data),
            isVerified: Self.isVerified(data),
            videoCountText: Self.videoCountText(of: data)
        )

        var videos: [YouTubeVideo] = []
        var continuation: String?
        if let contents = data["contents"] {
            YouTubeFeedParser.collect(
                in: contents,
                videos: &videos,
                continuation: &continuation
            )
        }

        return YouTubeChannelDetail(
            channel: channel,
            videos: YouTubeFeedParser.deduplicate(videos),
            tabs: Self.tabs(of: data),
            isSubscribed: Self.isSubscribed(data)
        )
    }

    /// Best-effort subscription state from the header's subscribe button
    /// (`subscribeButtonRenderer.subscribed`, or `isSubscribed` on newer view models).
    private static func isSubscribed(_ data: [String: Any]) -> Bool {
        guard let header = data["header"] else { return false }
        for key in ["subscribed", "isSubscribed"] {
            if let value = Self.firstValue(in: header, forKey: key) as? Bool { return value }
        }
        return false
    }

    /// Tabs from `contents.twoColumnBrowseResultsRenderer.tabs[].tabRenderer`.
    static func tabs(of data: [String: Any]) -> [YouTubeChannelTab] {
        let tabs = (
            (data["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any]
        )?["tabs"] as? [[String: Any]] ?? []
        return tabs.compactMap { tab in
            guard let renderer = tab["tabRenderer"] as? [String: Any],
                  let title = renderer["title"] as? String,
                  let params = (
                      (renderer["endpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
                  )?["params"] as? String
            else { return nil }
            return YouTubeChannelTab(
                title: title,
                params: params,
                kind: YouTubeChannelTab.kind(fromParams: params)
            )
        }
    }

    /// Parses a browse response of one channel tab (or its continuation) into items.
    static func parseTab(_ data: [String: Any]) -> YouTubeChannelTabContent {
        var videos: [YouTubeVideo] = []
        var shorts: [YouTubeVideo] = []
        var continuation: String?
        let body: Any = data["contents"] ?? data["onResponseReceivedActions"] ?? data["onResponseReceivedCommands"] ?? data
        YouTubeFeedParser.collect(in: body, videos: &videos, shorts: &shorts, continuation: &continuation)
        return YouTubeChannelTabContent(
            videos: YouTubeFeedParser.deduplicate(videos),
            shorts: YouTubeFeedParser.deduplicate(shorts),
            playlists: YouTubeFeedParser.collectPlaylists(data),
            continuation: continuation
        )
    }

    // MARK: - Private

    /// Extracts "@handle" from "http://www.youtube.com/@handle".
    private static func handle(fromVanityURL url: String?) -> String? {
        guard let last = url?.split(separator: "/").last, last.hasPrefix("@") else {
            return nil
        }
        return String(last)
    }

    /// Best-effort subscriber count from the page header
    /// (e.g. "20.8M subscribers" somewhere in `header`).
    private static func subscriberCountText(of data: [String: Any]) -> String? {
        guard let header = data["header"] else { return nil }
        return Self.firstText(in: header) { $0.localizedCaseInsensitiveContains("subscriber") }
    }

    /// Best-effort video count ("2.6K videos"): a short header text with a digit and the word "video".
    private static func videoCountText(of data: [String: Any]) -> String? {
        guard let header = data["header"] else { return nil }
        return Self.firstText(in: header) { text in
            text.count <= 24
                && text.localizedCaseInsensitiveContains("video")
                && text.contains { $0.isNumber }
        }
    }

    /// Best-effort verified badge: the header mentions one of YouTube's verified badge markers.
    private static func isVerified(_ data: [String: Any]) -> Bool {
        guard let header = data["header"] else { return false }
        let markers: Set = ["BADGE_STYLE_TYPE_VERIFIED", "CHECK_CIRCLE_THICK", "OFFICIAL_ARTIST_BADGE"]
        return Self.containsString(in: header) { markers.contains($0) }
    }

    /// Widest image found under the header's `banner` key (new `imageBannerViewModel` or old `thumbnails`).
    private static func bannerURL(of data: [String: Any]) -> URL? {
        guard let header = data["header"],
              let banner = Self.firstValue(in: header, forKey: "banner")
        else { return nil }
        var best: (width: Int, url: String)?
        Self.collectImages(in: banner) { width, url in
            if best == nil || width > best?.width ?? 0 { best = (width, url) }
        }
        guard var string = best?.url else { return nil }
        if string.hasPrefix("//") { string = "https:" + string }
        return URL(string: string)
    }

    private static func firstValue(in value: Any, forKey key: String) -> Any? {
        if let dict = value as? [String: Any] {
            if let direct = dict[key] { return direct }
            for nested in dict.values {
                if let found = Self.firstValue(in: nested, forKey: key) { return found }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = Self.firstValue(in: element, forKey: key) { return found }
            }
        }
        return nil
    }

    private static func collectImages(in value: Any, _ body: (Int, String) -> Void) {
        if let dict = value as? [String: Any] {
            if let url = dict["url"] as? String, url.hasPrefix("http") || url.hasPrefix("//") {
                body(dict["width"] as? Int ?? 0, url)
            }
            for nested in dict.values { Self.collectImages(in: nested, body) }
        } else if let array = value as? [Any] {
            for element in array { Self.collectImages(in: element, body) }
        }
    }

    private static func containsString(in value: Any, where predicate: (String) -> Bool) -> Bool {
        if let text = value as? String { return predicate(text) }
        if let dict = value as? [String: Any] {
            return dict.values.contains { Self.containsString(in: $0, where: predicate) }
        }
        if let array = value as? [Any] {
            return array.contains { Self.containsString(in: $0, where: predicate) }
        }
        return false
    }

    /// Depth-first search for the first metadata text matching a predicate.
    private static func firstText(
        in value: Any,
        where predicate: (String) -> Bool
    ) -> String? {
        if let dict = value as? [String: Any] {
            for key in ["content", "simpleText", "text"] {
                if let text = dict[key] as? String, predicate(text) {
                    return text
                }
            }
            for nested in dict.values {
                if let found = firstText(in: nested, where: predicate) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = Self.firstText(in: element, where: predicate) {
                    return found
                }
            }
        }
        return nil
    }
}
