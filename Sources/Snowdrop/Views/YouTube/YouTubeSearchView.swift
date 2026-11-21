import SwiftUI

// MARK: - YouTubeSearchView

/// YouTube search: query field, result-kind filter, history / suggestions while typing,
/// and a grid of results (big videos, vertical Shorts cards, channel cards).
struct YouTubeSearchView: View {
    @Bindable var viewModel: YouTubeSearchViewModel
    @FocusState private var isSearchFieldFocused: Bool
    /// Width of the results area, to keep the video block a whole number of grid rows.
    @State private var resultsWidth: CGFloat = 900

    private static let accent = PackageResourceLookup.brandAccent
    private static let videoColumns = [
        GridItem(.adaptive(minimum: 300, maximum: 520), spacing: YouTubeGridLayout.columnSpacing, alignment: .top),
    ]
    private static let channelColumns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: YouTubeGridLayout.columnSpacing, alignment: .top),
    ]
    private static let playlistColumns = [
        GridItem(.adaptive(minimum: 340, maximum: 520), spacing: YouTubeGridLayout.columnSpacing, alignment: .top),
    ]

    var body: some View {
        VStack(spacing: 0) {
            self.searchHeader

            Group {
                switch self.viewModel.loadingState {
                case .idle:
                    self.idleContent
                case .loading:
                    LoadingView()
                case let .error(error):
                    ErrorView(
                        title: error.title,
                        message: error.message,
                        isRetryable: error.isRetryable
                    ) {
                        Task {
                            await self.viewModel.search()
                        }
                    }
                case .loaded, .loadingMore:
                    if self.viewModel.results.isEmpty {
                        ContentUnavailableView.search(text: self.viewModel.query)
                    } else {
                        self.resultsList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text("Search", comment: "YouTube search title"))
    }

    // MARK: - Header

    private var searchHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    String(localized: "Search YouTube"),
                    text: self.$viewModel.query
                )
                .textFieldStyle(.plain)
                .focused(self.$isSearchFieldFocused)
                .onSubmit {
                    Task {
                        await self.viewModel.submit()
                    }
                }
                .accessibilityIdentifier(AccessibilityID.YouTubeContent.searchField)

                if !self.viewModel.query.isEmpty {
                    Button {
                        self.viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Clear search"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: Capsule())

            Picker(String(localized: "Filter"), selection: self.$viewModel.selectedFilter) {
                ForEach(YouTubeSearchFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(AccessibilityID.YouTubeContent.searchFilter)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - History & suggestions

    @ViewBuilder
    private var idleContent: some View {
        let trimmed = self.viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.historyList
        } else {
            self.suggestionList
        }
    }

    @ViewBuilder
    private var historyList: some View {
        let entries = self.viewModel.recentSearches
        if entries.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "Search YouTube"), systemImage: "magnifyingglass")
            } description: {
                Text("Find videos, channels, and playlists.", comment: "YouTube search empty state")
            }
            .task { await self.viewModel.loadRecentSearches() }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text("Recent searches", comment: "YouTube search history header")
                        .font(.title3.bold())
                        .padding(.bottom, 6)

                    ForEach(entries, id: \.self) { entry in
                        self.queryRow(entry, icon: "clock.arrow.circlepath")
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task { await self.viewModel.loadRecentSearches() }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        let suggestions = self.viewModel.suggestions
        if suggestions.isEmpty {
            // Nothing to suggest (yet): a hint that Return runs the search.
            ContentUnavailableView {
                Label(String(localized: "Press Return to search"), systemImage: "return")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        self.queryRow(suggestion, icon: "magnifyingglass")
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func queryRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await self.viewModel.submit(text)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Put the entry into the field without searching, like YouTube's arrow.
            Button {
                self.viewModel.query = text
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Use this suggestion"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Results

    /// How many videos come before the Shorts shelf, like on youtube.com.
    private static let videoColumnMinWidth: CGFloat = 300

    /// Two full rows of videos, whatever the column count at the current width.
    private var videosBeforeShorts: Int {
        let spacing = YouTubeGridLayout.columnSpacing
        let columns = max(1, Int((self.resultsWidth + spacing) / (Self.videoColumnMinWidth + spacing)))
        return columns * 2
    }

    private var resultsList: some View {
        let results = self.viewModel.results
        let headVideos = Array(results.videos.prefix(self.videosBeforeShorts))
        let tailVideos = Array(results.videos.dropFirst(self.videosBeforeShorts))
        let showsHeaders = self.viewModel.selectedFilter == .all

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !results.channels.isEmpty {
                    self.channelsSection(results.channels, showsHeader: showsHeaders)
                }

                if !headVideos.isEmpty {
                    self.videosSection(headVideos, title: showsHeaders ? String(localized: "Videos") : nil)
                }

                if !results.shorts.isEmpty {
                    self.shortsShelf(results.shorts)
                }

                if !tailVideos.isEmpty {
                    self.videosSection(tailVideos, title: nil)
                }

                if !results.playlists.isEmpty {
                    self.playlistsSection(results.playlists, showsHeader: showsHeaders)
                }

                if results.continuation != nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .task(id: results.continuation) {
                            await self.viewModel.loadMore()
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 40 } action: { self.resultsWidth = $0 }
        }
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.searchResults)
    }

    private func channelsSection(_ channels: [YouTubeChannel], showsHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                self.sectionHeader(String(localized: "Channels"))
            }
            LazyVGrid(columns: Self.channelColumns, spacing: YouTubeGridLayout.columnSpacing) {
                ForEach(channels) { channel in
                    NavigationLink(value: YouTubeRoute.channel(channelId: channel.channelId)) {
                        SearchChannelCard(channel: channel)
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
        }
    }

    private func videosSection(_ videos: [YouTubeVideo], title: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                self.sectionHeader(title)
            }
            LazyVGrid(columns: Self.videoColumns, spacing: YouTubeGridLayout.rowSpacing) {
                ForEach(videos) { video in
                    NavigationLink(value: YouTubeRoute.watch(video)) {
                        VideoCard(video: video)
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
        }
    }

    private func shortsShelf(_ shorts: [YouTubeVideo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Self.accent)
                self.sectionHeader(String(localized: "Shorts"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(shorts) { short in
                        NavigationLink(value: YouTubeRoute.watch(short)) {
                            YouTubeShortCard(video: short)
                        }
                        .buttonStyle(.interactiveCard)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func playlistsSection(_ playlists: [YouTubePlaylist], showsHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                self.sectionHeader(String(localized: "Playlists"))
            }
            LazyVGrid(columns: Self.playlistColumns, spacing: 12) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: YouTubeRoute.playlist(playlistId: playlist.playlistId)) {
                        YouTubePlaylistRowView(playlist: playlist)
                    }
                    .buttonStyle(.interactiveRow)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
    }
}

// MARK: - SearchShortCard

/// A tall 9:16 Shorts card: full-bleed thumbnail, soft bottom fade, title and views on top of it.
struct YouTubeShortCard: View {
    let video: YouTubeVideo

    private static let width: CGFloat = 190
    private static let height: CGFloat = 338
    private static let accent = PackageResourceLookup.brandAccent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(
                url: self.video.thumbnailURL,
                targetSize: CGSize(width: Self.width * 2, height: Self.height * 2)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: Self.width, height: Self.height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(self.video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let views = self.video.viewCountText {
                    Text(views)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(Self.accent, in: Circle())
                .padding(10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.video.title)
    }
}

// MARK: - SearchChannelCard

/// A channel result as a card: big avatar with an accent ring, name, handle and subscribers.
private struct SearchChannelCard: View {
    let channel: YouTubeChannel

    private static let avatarSize: CGFloat = 96
    private static let accent = PackageResourceLookup.brandAccent

    var body: some View {
        VStack(spacing: 10) {
            CachedAsyncImage(
                url: self.channel.thumbnailURL,
                targetSize: CGSize(width: Self.avatarSize * 2, height: Self.avatarSize * 2)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .clipShape(.circle)
            .overlay {
                Circle().strokeBorder(Self.accent.opacity(0.85), lineWidth: 2.5)
            }
            .shadow(color: Self.accent.opacity(0.35), radius: 12, y: 3)

            VStack(spacing: 3) {
                Text(self.channel.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let meta = [self.channel.handle, self.channel.subscriberCountText].compactMap(\.self)
                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let snippet = self.channel.descriptionSnippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }

            Text("View channel", comment: "Channel card button label in search results")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Self.accent, in: Capsule())
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.32), in: .rect(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let searchField = "youtubeContent.searchField"
    static let searchFilter = "youtubeContent.searchFilter"
    static let searchResults = "youtubeContent.searchResults"
}
