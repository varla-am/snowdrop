import Foundation

// MARK: - YouTubeSearchSuggestions

/// Fetches autocomplete suggestions for the YouTube search field.
///
/// Uses the public suggest endpoint that powers the search box on youtube.com.
/// Failures are silent: suggestions are a convenience, never an error state.
enum YouTubeSearchSuggestions {
    static func fetch(for query: String) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1,
              let list = json[1] as? [String]
        else { return [] }

        return Array(list.prefix(10))
    }
}
