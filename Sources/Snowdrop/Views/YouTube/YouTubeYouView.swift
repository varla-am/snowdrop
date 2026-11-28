import SwiftUI

// MARK: - YouTubeYouView

/// The "You" page. The header, the collection tiles and the channel column stay put;
/// only the video area scrolls: your videos sideways, Recommended downwards.
struct YouTubeYouView: View {
    let viewModel: YouTubeYouViewModel
    let home: YouTubeHomeViewModel

    @Environment(AccountService.self) private var accountService
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @State private var preferences = YouTubeYouPreferences.shared
    @State private var selectedVideoSource: String?
    @State private var showingPersonalize = false

    private static let tileSize: CGFloat = 108
    private static let channelSize: CGFloat = 56
    private static let channelSpacing: CGFloat = 14

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView()
            case .loaded, .loadingMore, .error:
                self.content
            }
        }
        .navigationTitle(Text("You", comment: "YouTube You page title"))
        .task(id: ObjectIdentifier(self.viewModel)) {
            await self.viewModel.load()
        }
        .task(id: ObjectIdentifier(self.home)) {
            await self.home.load()
        }
        .sheet(isPresented: self.$showingPersonalize) {
            YouTubePersonalizeYouSheet(viewModel: self.viewModel, preferences: self.preferences)
        }
    }

    // MARK: Resolved selections

    private var tiles: [YouTubeYouSource] {
        let all = self.viewModel.allSources
        guard let ids = self.preferences.tileIds else { return all }
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private var videoSources: [YouTubeYouSource] {
        let all = self.viewModel.allSources
        let ids = self.preferences.videoSourceIds ?? [YouTubeYouPreferences.historyID, YouTubeYouPreferences.watchLaterID]
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private var activeVideoSource: YouTubeYouSource? {
        let sources = self.videoSources
        return sources.first { $0.id == self.selectedVideoSource } ?? sources.first
    }

    private var pinnedChannels: [YouTubeYouChannel] {
        self.preferences.channels ?? self.viewModel.channels.map(YouTubeYouChannel.init)
    }

    // MARK: Layout

    private var content: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 22) {
                    self.header
                    self.tilesRow
                    self.scrollingArea
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                self.channelsColumn(availableHeight: proxy.size.height - 96)
            }
            .padding(.top, 24)
            .detailScrollContentInset()
        }
    }

    /// The only part of the page that moves.
    private var scrollingArea: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                self.videosRow
                self.recommended
            }
            .padding(.bottom, 28)
            // Breathing room inside the clip, so hovered (scaled) cards and shadows aren't cut at the edges.
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.025), .init(color: .black, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 18) {
            self.avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(self.accountService.currentAccount?.name ?? String(localized: "You"))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if let handle = self.accountService.currentAccount?.displayHandle {
                    Text(handle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var avatar: some View {
        ChannelMonogram(
            name: self.accountService.currentAccount?.name,
            avatarURL: self.accountService.currentAccount?.thumbnailURL,
            size: 80
        )
        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .frame(width: 80, height: 80)
        // Sits on the avatar's own rim (upper right), not beside it.
        .overlay(alignment: .topTrailing) {
            Button {
                self.showingPersonalize = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(colors: [.pink, Color(red: 1, green: 0.4, blue: 0.6)], startPoint: .top, endPoint: .bottom),
                        in: .circle
                    )
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .shadow(color: .pink.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(.interactiveCard)
            .help(String(localized: "Personalize You"))
            .accessibilityLabel(String(localized: "Personalize You"))
        }
    }

    // MARK: Tiles

    private var tilesRow: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(self.tiles) { source in
                        NavigationLink(value: self.route(for: source)) {
                            YouTubeYouTile(source: source, size: Self.tileSize)
                        }
                        .buttonStyle(.interactiveCard)
                    }
                }
                // Few tiles sit in the middle instead of hugging the left edge.
                .frame(minWidth: proxy.size.width, alignment: .center)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: Self.tileSize + 48)
    }

    private func route(for source: YouTubeYouSource) -> YouTubeRoute {
        source.isHistory ? .history : .playlist(playlistId: source.id)
    }

    // MARK: Your videos

    @ViewBuilder
    private var videosRow: some View {
        if let source = self.activeVideoSource {
            let videos = self.viewModel.videosBySource[source.id]
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: self.route(for: source)) {
                    HStack(spacing: 7) {
                        Image(systemName: source.systemImage).foregroundStyle(.tint)
                        Text(source.title).font(.system(size: 18, weight: .bold))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                HStack(alignment: .top, spacing: 14) {
                    self.videoStrip(videos)
                    if self.videoSources.count > 1 {
                        self.sourcePill(active: source)
                    }
                }
            }
            // Fresh data every time the page or the source comes up (history and lists change often).
            .task(id: source.id) {
                await self.viewModel.loadVideos(for: source.id, force: true)
            }
            // After a watch ends, YouTube needs a moment to record it; then refresh.
            .onChange(of: self.youtubePlayer.watchConclusionGeneration) { _, _ in
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await self.viewModel.loadVideos(for: source.id, force: true)
                }
            }
        }
    }

    @ViewBuilder
    private func videoStrip(_ videos: [YouTubeVideo]?) -> some View {
        if let videos {
            if videos.isEmpty {
                Text("Nothing here yet", comment: "Empty You page video row")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                GeometryReader { proxy in
                    // Three cards exactly fill the row; more scroll sideways at the same width.
                    let cardWidth = max(220, (proxy.size.width - 32) / 3)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(videos.prefix(40)) { video in
                                NavigationLink(value: YouTubeRoute.watch(video)) {
                                    VideoCard(video: video)
                                        .frame(width: cardWidth)
                                }
                                .buttonStyle(.interactiveCard)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(height: 260)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 150)
        }
    }

    /// The vertical switcher beside the video row, centred against the strip.
    private func sourcePill(active: YouTubeYouSource) -> some View {
        VStack(spacing: 6) {
            ForEach(self.videoSources) { source in
                let isActive = source.id == active.id
                Button {
                    withAnimation(.snappy(duration: 0.22)) { self.selectedVideoSource = source.id }
                    HapticService.navigation()
                } label: {
                    Image(systemName: source.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background {
                            if isActive { Circle().fill(Color.accentColor.gradient) }
                        }
                }
                .buttonStyle(.plain)
                .help(source.title)
                .accessibilityLabel(source.title)
            }
        }
        .padding(5)
        .compatGlass(in: Capsule())
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: Recommended

    @ViewBuilder
    private var recommended: some View {
        if !self.home.videos.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").foregroundStyle(.tint)
                    Text("Recommended", comment: "You page recommended section").font(.system(size: 18, weight: .bold))
                }

                LazyVGrid(columns: YouTubeGridLayout.columns, spacing: YouTubeGridLayout.rowSpacing) {
                    ForEach(self.home.videos) { video in
                        NavigationLink(value: YouTubeRoute.watch(video)) {
                            VideoCard(video: video)
                        }
                        .buttonStyle(.interactiveCard)
                    }

                    if self.home.hasMoreVideos {
                        ProgressView()
                            .controlSize(.small)
                            .task(id: self.home.videos.count) {
                                await self.home.loadMore()
                            }
                    }
                }
            }
        }
    }

    // MARK: Channels

    /// As many channels as the window's height holds; the rest wait for a taller window.
    @ViewBuilder
    private func channelsColumn(availableHeight: CGFloat) -> some View {
        let perItem = Self.channelSize + Self.channelSpacing
        let fit = max(1, Int((availableHeight - 24 + Self.channelSpacing) / perItem))
        let shown = Array(self.pinnedChannels.prefix(fit))
        if !shown.isEmpty {
            VStack(spacing: Self.channelSpacing) {
                ForEach(shown) { channel in
                    NavigationLink(value: YouTubeRoute.channel(channelId: channel.id)) {
                        ChannelMonogram(name: channel.name, avatarURL: channel.thumbnailURL, size: Self.channelSize)
                    }
                    .buttonStyle(.interactiveCard)
                    .help(channel.name)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 48)
        }
    }
}

// MARK: - YouTubeYouTile

/// A square collection tile: playlist art, or a coloured icon for the built-ins.
private struct YouTubeYouTile: View {
    let source: YouTubeYouSource
    let size: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            self.art
                .frame(width: self.size, height: self.size)
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            Text(self.source.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: self.size)
        }
    }

    @ViewBuilder
    private var art: some View {
        if self.source.isBuiltIn {
            LinearGradient(colors: self.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    Image(systemName: self.source.systemImage)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
        } else {
            CachedAsyncImage(url: self.source.thumbnailURL, targetSize: CGSize(width: 240, height: 240)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "list.and.film")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
    }

    private var colors: [Color] {
        switch self.source.id {
        case YouTubeYouPreferences.historyID: [.indigo, .purple]
        case YouTubeYouPreferences.watchLaterID: [.orange, .pink]
        default: [.pink, .red]
        }
    }
}

// MARK: - YouTubePersonalizeYouSheet

/// "Personalize You": pick channels (searchable), collections and the video-row sources.
struct YouTubePersonalizeYouSheet: View {
    let viewModel: YouTubeYouViewModel
    @Bindable var preferences: YouTubeYouPreferences
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable, Identifiable {
        case channels, collections, videos
        var id: String { self.rawValue }
        var title: String {
            switch self {
            case .channels: String(localized: "Channels")
            case .collections: String(localized: "Collections")
            case .videos: String(localized: "Video row")
            }
        }
    }

    @State private var tab: Tab = .channels
    @State private var query = ""
    @State private var results: [YouTubeChannel] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(String(localized: "Personalize You"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(String(localized: "Reset")) { self.preferences.reset() }
                    .disabled(!self.preferences.isCustomised)
                Button(String(localized: "Done")) { self.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Picker("", selection: self.$tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            switch self.tab {
            case .channels: self.channelsTab
            case .collections: self.collectionsTab
            case .videos: self.videosTab
            }
        }
        .frame(width: 460, height: 600)
    }

    // MARK: Channels

    private var pinned: [YouTubeYouChannel] {
        self.preferences.channels ?? self.viewModel.channels.map(YouTubeYouChannel.init)
    }

    private var channelsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Search YouTube channels"), text: self.$query)
                    .textFieldStyle(.plain)
                if self.isSearching { ProgressView().controlSize(.small) }
                if !self.query.isEmpty {
                    Button { self.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            .padding(12)
            .task(id: self.query) { await self.runSearch() }

            Text("Shown on the page: as many as fit the window height.", comment: "Personalize hint")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            List {
                if self.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    // One stable list (no row hops between sections, which made rows overlap):
                    // pinned channels that aren't subscriptions first, then the subscriptions.
                    let subscribedIds = Set(self.viewModel.channels.map(\.channelId))
                    let extra = self.pinned.filter { !subscribedIds.contains($0.id) }
                    ForEach(extra) { self.channelRow($0) }
                    ForEach(self.viewModel.channels) { self.channelRow(YouTubeYouChannel($0)) }
                } else {
                    Section(String(localized: "Search results")) {
                        ForEach(self.results) { self.channelRow(YouTubeYouChannel($0), subtitle: $0.subscriberCountText ?? $0.handle) }
                    }
                }
            }
        }
    }

    private func runSearch() async {
        let text = self.query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            self.results = []
            self.isSearching = false
            return
        }
        self.isSearching = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let found = await self.viewModel.searchChannels(text)
        guard !Task.isCancelled else { return }
        self.results = found
        self.isSearching = false
    }

    private func channelRow(_ channel: YouTubeYouChannel, subtitle: String? = nil) -> some View {
        let isOn = self.pinned.contains { $0.id == channel.id }
        return Button {
            var list = self.pinned
            if let index = list.firstIndex(where: { $0.id == channel.id }) {
                list.remove(at: index)
            } else {
                list.append(channel)
            }
            self.preferences.channels = list
        } label: {
            HStack(spacing: 12) {
                ChannelMonogram(name: channel.name, avatarURL: channel.thumbnailURL, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Collections / video row

    private var collectionsTab: some View {
        List {
            Section {
                ForEach(self.viewModel.allSources) { source in
                    self.sourceRow(source, isOn: self.tileSelection.contains(source.id)) {
                        self.toggle(source.id, in: self.tileSelection, limit: nil) { self.preferences.tileIds = $0 }
                    }
                }
            } footer: {
                Text("Tiles in the top row. With few, they sit in the middle.", comment: "Personalize hint")
            }
        }
    }

    private var videosTab: some View {
        List {
            Section {
                ForEach(self.viewModel.allSources) { source in
                    self.sourceRow(source, isOn: self.sourceSelection.contains(source.id)) {
                        self.toggle(source.id, in: self.sourceSelection, limit: YouTubeYouPreferences.maxVideoSources) {
                            self.preferences.videoSourceIds = $0
                        }
                    }
                }
            } footer: {
                Text("What the round switcher flips between (up to \(YouTubeYouPreferences.maxVideoSources)).", comment: "Personalize hint")
            }
        }
    }

    private var tileSelection: [String] {
        self.preferences.tileIds ?? self.viewModel.allSources.map(\.id)
    }

    private var sourceSelection: [String] {
        self.preferences.videoSourceIds ?? [YouTubeYouPreferences.historyID, YouTubeYouPreferences.watchLaterID]
    }

    private func toggle(_ id: String, in current: [String], limit: Int?, commit: ([String]) -> Void) {
        var next = current
        if let index = next.firstIndex(of: id) {
            next.remove(at: index)
        } else {
            if let limit, next.count >= limit { next.removeFirst() }
            next.append(id)
        }
        commit(next)
    }

    private func sourceRow(_ source: YouTubeYouSource, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: source.systemImage)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.tint)
                Text(source.title).lineLimit(1)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
