import SwiftUI

/// Home view displaying personalized content sections.
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(AuthService.self) private var authService
    @State private var navigationPath = NavigationPath()
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var selectedChip: String?

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if !self.networkMonitor.isConnected {
                    ErrorView(
                        title: String(localized: "No Connection"),
                        message: String(localized: "Please check your internet connection and try again.")
                    ) {
                        Task { await self.viewModel.refresh() }
                    }
                } else {
                    switch self.viewModel.loadingState {
                    case .idle, .loading:
                        HomeLoadingView()
                    case .loaded, .loadingMore:
                        self.contentView
                    case let .error(error):
                        ErrorView(error: error) {
                            Task { await self.viewModel.refresh() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .localizedNavigationTitle("Home")
            .navigationDestinations(client: self.viewModel.client)
            .playerBarMusicNavigation(path: self.$navigationPath)
        }
        .playerBarMusicNavigation(path: self.$navigationPath)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // A pushed card draws its own bar; two stacked bars looked like a bug.
            if self.navigationPath.isEmpty {
                PlayerBar()
                    .playerBarMusicNavigation(path: self.$navigationPath)
            }
        }
        .onAppear {
            if self.viewModel.loadingState == .idle {
                Task {
                    await self.viewModel.load()
                }
            }
        }
        .popsNavigationStackOnSidebarReselect(path: self.$navigationPath, for: .home)
    }

    // MARK: - Views

    private var contentView: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !self.chipSections.isEmpty {
                    HomeChipsBar(
                        titles: self.chipSections.map(\.title),
                        selected: self.selectedChip
                    ) { title in
                        withAnimation(.smooth(duration: 0.35)) {
                            self.selectedChip = title
                            if let id = self.chipSections.first(where: { $0.title == title })?.id {
                                proxy.scrollTo(id, anchor: .top)
                            } else {
                                proxy.scrollTo("home.top", anchor: .top)
                            }
                        }
                    }
                    .padding(.horizontal, DetailContentLayout.horizontalInset)
                    .id("home.top")
                }

                // Favorites section (hidden when empty)
                if self.authService.hasPersonalAccount, self.favoritesManager.isVisible {
                    FavoritesSection(
                        onNavigate: { destination in
                            if let playlist = destination as? Playlist {
                                self.navigationPath.append(playlist)
                            } else if let artist = destination as? Artist {
                                self.navigationPath.append(artist)
                            } else if let podcastShow = destination as? PodcastShow {
                                self.navigationPath.append(podcastShow)
                            }
                        },
                        contentInset: DetailContentLayout.horizontalInset
                    )
                    .staggeredAppearance(index: 0)
                }

                // API sections
                ForEach(self.viewModel.sections) { section in
                    self.sectionView(section)
                        .id(section.id)
                        .task {
                            await self.prefetchImagesAsync(for: section)
                        }
                }

                if self.viewModel.hasMoreSections || self.viewModel.loadingState == .loadingMore {
                    self.loadMoreControl
                }
            }
            // The ScrollView fills the detail column edge-to-edge so shelves
            // scroll under the floating glass sidebar; each shelf restores a
            // resting inset via `contentInset`. Only the vertical inset stays
            // on the stack.
            .padding(.vertical, 20)
        }
        .accessibilityIdentifier(AccessibilityID.Home.scrollView)
        .pullToRefresh {
            await self.viewModel.refresh()
        }
        }
    }

    /// Sections the chips can jump to (titles only; capped so the row stays short).
    private var chipSections: [HomeSection] {
        Array(self.viewModel.sections.filter { !$0.title.isEmpty }.prefix(10))
    }

    /// A section made only of songs reads as Quick picks.
    private func quickPickSongs(in section: HomeSection) -> [Song]? {
        let songs: [Song] = section.items.compactMap {
            if case let .song(song) = $0 { return song }
            return nil
        }
        guard songs.count == section.items.count, songs.count >= 6, !section.isChart else { return nil }
        return songs
    }

    private var loadMoreControl: some View {
        LoadMoreFooter(
            isLoading: self.viewModel.loadingState == .loadingMore,
            title: "Load More",
            loadingTitle: "Loading more...",
            autoLoad: true,
            autoLoadTrigger: self.viewModel.sections.count
        ) {
            await self.viewModel.loadMore()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        if let songs = self.quickPickSongs(in: section) {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: section.title, eyebrow: String(localized: "Start radio from a song"))
                    .padding(.horizontal, DetailContentLayout.horizontalInset)
                QuickPicksGrid(
                    songs: songs,
                    contentInset: DetailContentLayout.horizontalInset,
                    onPlay: { song in
                        Task { await self.playerService.playWithRadio(song: song) }
                    },
                    menu: { song in
                        self.contextMenuItems(for: .song(song), in: section, at: 0)
                    }
                )
            }
        } else {
            self.shelfView(section)
        }
    }

    private func shelfView(_ section: HomeSection) -> some View {
        HomeItemShelfSection(
            accessibilityLabel: section.title,
            items: section.items,
            isChart: section.isChart,
            contentInset: DetailContentLayout.horizontalInset,
            action: { item, index in
                self.playItem(item, in: section, at: index)
            },
            playlistPlayAction: { item in
                self.playlistPlayAction(for: item)
            },
            header: {
                HomeSectionHeader(title: section.title, eyebrow: nil)
            },
            contextMenu: { item, index in
                self.contextMenuItems(for: item, in: section, at: index)
            }
        )
    }

    // MARK: - Context Menu

    private func playlistPlayAction(for item: HomeSectionItem) -> (() -> Void)? {
        guard case let .playlist(playlist) = item,
              SongActionsHelper.canQuickPlayPlaylist(playlist)
        else {
            return nil
        }

        return {
            SongActionsHelper.playPlaylist(
                playlist,
                client: self.viewModel.client,
                playerService: self.playerService
            )
        }
    }

    private func contextMenuItems(for item: HomeSectionItem, in section: HomeSection, at index: Int) -> some View {
        HomeSectionItemContextMenu(
            item: item,
            client: self.viewModel.client,
            play: { self.playItem(item, in: section, at: index) },
            navigate: { self.navigationPath.append($0) }
        )
    }

    // MARK: - Image Prefetching

    private static let thumbnailDisplaySize = CGSize(width: 160, height: 160)

    private func prefetchImagesAsync(for section: HomeSection) async {
        // Early exit if task is cancelled
        guard !Task.isCancelled else { return }

        let urls = section.items.prefix(6).compactMap { $0.thumbnailURL?.highQualityThumbnailURL }
        guard !urls.isEmpty else { return }

        await ImageCache.shared.prefetch(
            urls: urls,
            targetSize: Self.thumbnailDisplaySize,
            maxConcurrent: 2
        )
    }

    // MARK: - Actions

    private func playItem(_ item: HomeSectionItem, in _: HomeSection, at _: Int) {
        switch item {
        case let .song(song):
            // Play the song and fetch similar songs (radio queue) in the background
            Task {
                await self.playerService.playWithRadio(song: song)
            }
        case let .playlist(playlist):
            // Navigate to playlist detail
            self.navigationPath.append(playlist)
        case let .album(album):
            // For now, we'll create a playlist-like navigation for albums
            // In a full implementation, we'd have an AlbumDetailView
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: Artist.inline(name: album.artistsDisplay, namespace: "album-artist")
            )
            self.navigationPath.append(playlist)
        case let .artist(artist):
            // Navigate to artist detail
            self.navigationPath.append(artist)
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    HomeView(viewModel: HomeViewModel(client: client))
        .environment(PlayerService())
        .environment(authService)
        .environment(FavoritesManager.shared)
}
