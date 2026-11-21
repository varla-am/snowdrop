import SwiftUI

/// A YouTube channel page: banner and profile header, tabs, then the landing-tab video grid.
struct YouTubeChannelView: View {
    @State private var viewModel: YouTubeChannelViewModel
    /// Selected tab's params; `nil` means the first content tab, `aboutTabID` the local About panel.
    @State private var selectedTabID: String?
    @State private var isDescriptionExpanded = false

    private static let columns = YouTubeGridLayout.columns
    private static let accent = PackageResourceLookup.brandAccent
    private static let avatarSize: CGFloat = 108

    private static let aboutTabID = "snowdrop.about"
    private static let playlistColumns = [
        GridItem(.adaptive(minimum: 340, maximum: 520), spacing: YouTubeGridLayout.columnSpacing, alignment: .top),
    ]
    private static let shortColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 190), spacing: YouTubeGridLayout.columnSpacing, alignment: .top),
    ]

    /// The tabs worth showing in the bar (Home, Posts and the rest are skipped).
    private static func contentTabs(of detail: YouTubeChannelDetail) -> [YouTubeChannelTab] {
        let wanted: Set<YouTubeChannelTab.Kind> = [.videos, .shorts, .live, .playlists, .podcasts]
        return detail.tabs.filter { wanted.contains($0.kind) }
    }

    init(channelId: String, client: any YouTubeClientProtocol) {
        self._viewModel = State(
            initialValue: YouTubeChannelViewModel(channelId: channelId, client: client)
        )
    }

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView()
            case let .error(error):
                ErrorView(
                    title: error.title,
                    message: error.message,
                    isRetryable: error.isRetryable
                ) {
                    Task {
                        await self.viewModel.load()
                    }
                }
            case .loaded, .loadingMore:
                if let detail = self.viewModel.detail {
                    self.content(for: detail)
                }
            }
        }
        .navigationTitle(Text(self.viewModel.detail?.channel.name ?? ""))
        .task {
            await self.viewModel.load()
        }
    }

    private func content(for detail: YouTubeChannelDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                self.hero(for: detail)
                self.tabBar(for: detail)
                self.tabContent(for: detail)
            }
            .padding(.bottom, 20)
            // Edge-to-edge with a resting inset so content extends under the
            // floating glass sidebar.
            .detailScrollContentInset()
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(for detail: YouTubeChannelDetail) -> some View {
        let tabs = Self.contentTabs(of: detail)
        if self.selectedTabID == Self.aboutTabID {
            self.about(for: detail.channel)
        } else if let tab = self.currentTab(in: tabs) {
            // The task sits on a container that is always in the tree: a modifier on a
            // branch that renders nothing never fires, which left the tab empty.
            VStack(alignment: .leading, spacing: 0) {
                self.content(of: tab, detail: detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: tab.id) {
                await self.viewModel.loadTab(tab)
            }
        } else {
            // The page offered no tabs we can browse: show the landing videos.
            self.videosGrid(detail.videos)
        }
    }

    private func currentTab(in tabs: [YouTubeChannelTab]) -> YouTubeChannelTab? {
        if let id = self.selectedTabID, let match = tabs.first(where: { $0.id == id }) {
            return match
        }
        return tabs.first
    }

    @ViewBuilder
    private func content(of tab: YouTubeChannelTab, detail: YouTubeChannelDetail) -> some View {
        let loaded = self.viewModel.tabContents[tab.id]
        let isLoading = self.viewModel.loadingTabs.contains(tab.id)

        if loaded == nil, isLoading {
            // Landing videos keep the Videos tab from flashing empty while its own page loads.
            if tab.kind == .videos, !detail.videos.isEmpty {
                self.videosGrid(detail.videos)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        } else if let loaded {
            VStack(alignment: .leading, spacing: 20) {
                switch tab.kind {
                case .shorts:
                    self.shortsGrid(loaded.shorts.isEmpty ? loaded.videos : loaded.shorts)
                case .playlists, .podcasts:
                    self.playlistsGrid(loaded.playlists)
                default:
                    self.videosGrid(loaded.videos)
                }

                if loaded.continuation != nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .task(id: loaded.continuation) {
                            await self.viewModel.loadMoreTab(tab)
                        }
                }
            }
        } else if self.viewModel.failedTabs.contains(tab.id) {
            ContentUnavailableView {
                Label(String(localized: "Couldn't load this tab"), systemImage: "exclamationmark.triangle")
            } actions: {
                Button(String(localized: "Try again")) {
                    Task { await self.viewModel.loadTab(tab) }
                }
            }
        } else {
            // Not started yet: show progress instead of an empty page.
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    @ViewBuilder
    private func videosGrid(_ videos: [YouTubeVideo]) -> some View {
        if videos.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No videos"), systemImage: "play.rectangle")
            }
        } else {
            LazyVGrid(columns: Self.columns, spacing: YouTubeGridLayout.rowSpacing) {
                ForEach(videos) { video in
                    NavigationLink(value: YouTubeRoute.watch(video)) {
                        VideoCard(video: video)
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
        }
    }

    @ViewBuilder
    private func shortsGrid(_ shorts: [YouTubeVideo]) -> some View {
        if shorts.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Shorts"), systemImage: "bolt")
            }
        } else {
            LazyVGrid(columns: Self.shortColumns, spacing: YouTubeGridLayout.columnSpacing) {
                ForEach(shorts) { short in
                    NavigationLink(value: YouTubeRoute.watch(short)) {
                        YouTubeShortCard(video: short)
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
        }
    }

    @ViewBuilder
    private func playlistsGrid(_ playlists: [YouTubePlaylist]) -> some View {
        if playlists.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No playlists"), systemImage: "list.bullet.rectangle")
            }
        } else {
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

    // MARK: - Hero

    private func hero(for detail: YouTubeChannelDetail) -> some View {
        let channel = detail.channel
        return VStack(alignment: .leading, spacing: 0) {
            self.banner(for: channel)

            HStack(alignment: .top, spacing: 20) {
                self.avatar(for: channel)
                    // Lift the avatar over the lower edge of the banner.
                    .padding(.top, -(Self.avatarSize / 2))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(channel.name)
                            .font(.largeTitle.bold())
                            .lineLimit(2)
                        if channel.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .help(String(localized: "Verified channel"))
                        }
                    }

                    let meta = [channel.handle, channel.subscriberCountText, channel.videoCountText].compactMap(\.self)
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    self.descriptionBlock(for: channel)
                    self.actionRow(for: detail)
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
    }

    private func banner(for channel: YouTubeChannel) -> some View {
        // The image lives in an overlay so its pixel size can never widen the page layout.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .overlay {
                ZStack(alignment: .bottom) {
                    if let url = channel.bannerURL {
                        CachedAsyncImage(
                            url: url,
                            targetSize: CGSize(width: 1600, height: 360)
                        ) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            self.bannerFallback
                        }
                    } else {
                        self.bannerFallback
                    }

                    // Soft fade so the banner melts into the themed window instead of ending in a hard edge.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.28)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var bannerFallback: some View {
        LinearGradient(
            colors: [Self.accent.opacity(0.85), Self.accent.opacity(0.25), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(.quaternary.opacity(0.4))
    }

    private func avatar(for channel: YouTubeChannel) -> some View {
        CachedAsyncImage(
            url: channel.thumbnailURL,
            targetSize: CGSize(width: Self.avatarSize, height: Self.avatarSize)
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Circle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(Self.accent.opacity(0.9), lineWidth: 3)
        }
        .shadow(color: Self.accent.opacity(0.45), radius: 16, y: 4)
    }

    @ViewBuilder
    private func descriptionBlock(for channel: YouTubeChannel) -> some View {
        if let description = channel.descriptionSnippet, !description.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(self.isDescriptionExpanded ? nil : 2)
                    .textSelection(.enabled)

                if description.count > 110 {
                    Button(self.isDescriptionExpanded ? String(localized: "less") : String(localized: "…more")) {
                        withAnimation(.snappy) {
                            self.isDescriptionExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func actionRow(for detail: YouTubeChannelDetail) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await self.viewModel.toggleSubscribed() }
            } label: {
                Label(
                    self.viewModel.isSubscribed ? String(localized: "Subscribed") : String(localized: "Subscribe"),
                    systemImage: self.viewModel.isSubscribed ? "bell.fill" : "bell"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(self.viewModel.isSubscribed ? Color.primary : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if self.viewModel.isSubscribed {
                        Capsule().fill(.quaternary.opacity(0.5))
                    } else {
                        Capsule().fill(Self.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.YouTubeContent.subscribeButton)

            if let latest = detail.videos.first ?? self.viewModel.tabContents.values.lazy.compactMap(\.videos.first).first {
                NavigationLink(value: YouTubeRoute.watch(latest)) {
                    Label(String(localized: "Play latest"), systemImage: "play.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Self.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let url = URL(string: "https://www.youtube.com/channel/\(detail.channel.channelId)") {
                ShareLink(item: url) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Tabs

    private func tabBar(for detail: YouTubeChannelDetail) -> some View {
        let tabs = Self.contentTabs(of: detail)
        let activeID = self.selectedTabID == Self.aboutTabID
            ? Self.aboutTabID
            : (self.currentTab(in: tabs)?.id ?? "")

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    self.tabButton(title: tab.title, isActive: activeID == tab.id) {
                        self.selectedTabID = tab.id
                    }
                }
                self.tabButton(title: String(localized: "About"), isActive: activeID == Self.aboutTabID) {
                    self.selectedTabID = Self.aboutTabID
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func tabButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy, action)
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background {
                    if isActive {
                        Capsule().fill(Self.accent)
                    } else {
                        Capsule().fill(.quaternary.opacity(0.5))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - About

    private func about(for channel: YouTubeChannel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = channel.descriptionSnippet, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Text("No description.", comment: "Channel About tab when the channel has no description")
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let handle = channel.handle {
                    self.aboutRow(icon: "at", text: handle)
                }
                if let subscribers = channel.subscriberCountText {
                    self.aboutRow(icon: "person.2", text: subscribers)
                }
                if let videos = channel.videoCountText {
                    self.aboutRow(icon: "play.rectangle", text: videos)
                }
                if let url = URL(string: "https://www.youtube.com/channel/\(channel.channelId)") {
                    Link(destination: url) {
                        Label(String(localized: "Open on YouTube"), systemImage: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 4)
    }

    private func aboutRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
