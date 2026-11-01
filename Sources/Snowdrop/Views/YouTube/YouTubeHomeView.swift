import SwiftUI

// MARK: - YouTubeHomeView

/// The YouTube home (recommended) feed: an adaptive grid of video cards.
struct YouTubeHomeView: View {
    let viewModel: YouTubeHomeViewModel

    /// The shelf chip showing in the grid; `nil` is the main feed.
    @State private var selectedChipID: String?

    private static let columns = [
        GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 18, alignment: .top),
    ]

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                self.loadingGrid
            case let .error(error):
                ErrorView(
                    title: error.title,
                    message: error.message,
                    isRetryable: error.isRetryable
                ) {
                    Task {
                        await self.viewModel.refresh()
                    }
                }
            case .loaded, .loadingMore:
                if self.viewModel.sections.isEmpty,
                   self.viewModel.videos.isEmpty,
                   !self.viewModel.hasMoreVideos,
                   !self.viewModel.hasMoreTopicRails,
                   !self.viewModel.isLoadingTopicRails
                {
                    ContentUnavailableView {
                        Label(String(localized: "No recommendations yet"), systemImage: "play.rectangle")
                    } description: {
                        Text("Watch some videos to build your feed.", comment: "Empty YouTube home feed description")
                    }
                } else {
                    // Route to feedContent when there is anything to show OR more
                    // pages remain — feedContent hosts the pagination sentinel,
                    // which must mount so loadMore() can fetch the next page even
                    // when the first render has no renderable rails/videos yet.
                    self.feedContent
                }
            }
        }
        .navigationTitle(Text("Home", comment: "YouTube home feed title"))
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.homeGrid)
        // Key on the view-model identity, not a bare `.task`. On cold launch the
        // account resolves after first paint and `resetForAccountChange()` swaps
        // in a fresh view model; a bare `.task` would not re-fire for that
        // property swap, leaving the new (idle) model stuck on the skeleton until
        // a navigation changed the view identity. Re-keying reloads the new model
        // immediately. (Same shape as YouTubeExploreView.)
        .task(id: ObjectIdentifier(self.viewModel)) {
            await self.viewModel.load()
        }
    }

    /// YouTube's own layout: a row of topic chips, then one grid of recommendations.
    /// The shelves and topic feeds the view model builds become chips; "All" shows the
    /// main feed and a chip swaps the grid to that shelf.
    private var feedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                self.chipBar
                self.videoGrid
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .pullToRefresh {
            await self.viewModel.refresh()
        }
    }

    // MARK: Chips

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                self.chip(title: String(localized: "All"), id: nil)

                ForEach(self.viewModel.sections) { section in
                    self.chip(title: section.title, id: section.id)
                }

                if self.viewModel.hasMoreTopicRails || self.viewModel.isLoadingTopicRails {
                    Button {
                        Task { await self.viewModel.loadMoreTopicRails() }
                    } label: {
                        Group {
                            if self.viewModel.isLoadingTopicRails {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "ellipsis")
                            }
                        }
                        .frame(width: 34, height: 30)
                        .background(.primary.opacity(0.1), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Load more topics"))
                }
            }
            .padding(.horizontal, DetailContentLayout.horizontalInset)
        }
    }

    private func chip(title: String, id: String?) -> some View {
        let isSelected = self.selectedChipID == id
        return Button {
            withAnimation(AppAnimation.quick) {
                self.selectedChipID = id
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .background(
                    isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.1)),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Grid

    /// The grid's videos: the selected shelf, else the main feed (falling back to the
    /// shelves' videos when the feed itself is empty).
    private var displayedVideos: [YouTubeVideo] {
        if let id = self.selectedChipID,
           let section = self.viewModel.sections.first(where: { $0.id == id })
        {
            return section.videos
        }
        if !self.viewModel.videos.isEmpty {
            return self.viewModel.videos
        }
        var seen = Set<String>()
        return self.viewModel.sections.flatMap(\.videos).filter { seen.insert($0.videoId).inserted }
    }

    private var isShowingMainFeed: Bool {
        guard let id = self.selectedChipID else { return true }
        return !self.viewModel.sections.contains { $0.id == id }
    }

    private var videoGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 28) {
            ForEach(self.displayedVideos) { video in
                NavigationLink(value: YouTubeRoute.watch(video)) {
                    VideoCard(video: video)
                }
                .buttonStyle(.interactiveCard)
            }

            if self.isShowingMainFeed, self.viewModel.hasMoreVideos {
                ProgressView()
                    .controlSize(.small)
                    .gridCellColumns(1)
                    .task(id: self.viewModel.videos.count) {
                        await self.viewModel.loadMore()
                    }
            }
        }
        .padding(.horizontal, DetailContentLayout.horizontalInset)
        // Warm the first screenful of thumbnails as soon as the grid publishes so they
        // decode ahead of scroll. Keyed on the first batch's IDs so a fresh load re-warms.
        .task(id: self.firstThumbnailBatchKey) {
            let urls = self.displayedVideos.prefix(12).compactMap(\.thumbnailURL)
            guard !urls.isEmpty else { return }
            await ImageCache.shared.prefetch(
                urls: Array(urls),
                targetSize: CGSize(width: 320, height: 180)
            )
        }
    }

    /// Identity for the prefetch task: the first batch of grid video IDs. Drives
    /// a re-warm when the grid's first page changes (a fresh load), not on every
    /// pagination append.
    private var firstThumbnailBatchKey: String {
        self.displayedVideos.prefix(12).map(\.videoId).joined(separator: ",")
    }

    private var loadingGrid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 20) {
                ForEach(0 ..< 12, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonView.rectangle(cornerRadius: 8)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        SkeletonView.rectangle(cornerRadius: 4)
                            .frame(width: 220, height: 12)
                        SkeletonView.rectangle(cornerRadius: 4)
                            .frame(width: 140, height: 10)
                    }
                }
            }
            .padding(.vertical, 20)
            .detailScrollContentInset()
        }
        .disabled(true)
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let homeGrid = "youtubeContent.homeGrid"
}
