import SwiftUI

// MARK: - YouTubeShortsView

/// The Shorts experience: a vertical pager that autoplays one short at a
/// time. Scrolling up advances to the next short, scrolling down returns
/// to the previous one (snap paging).
struct YouTubeShortsView: View {
    let viewModel: YouTubeShortsViewModel

    @Environment(AuthService.self) private var authService
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    /// The short currently snapped into view (drives autoplay).
    @State private var currentShortId: String?

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
                        await self.viewModel.refresh()
                    }
                }
            case .loaded, .loadingMore:
                if self.viewModel.shorts.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Shorts right now"), systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                    } description: {
                        Text("Shorts from your feed appear here.", comment: "Empty Shorts surface description")
                    }
                } else {
                    self.pager
                }
            }
        }
        .navigationTitle(Text("Shorts", comment: "YouTube Shorts title"))
        // Keyed on the view-model identity so a cold-launch account swap (which
        // rebuilds the model) re-fires the load instead of leaving the fresh,
        // idle model stuck. See YouTubeHomeView for the full rationale.
        .task(id: ObjectIdentifier(self.viewModel)) {
            // The view model is swapped on an account change; this @State is from
            // the previous account. Reset it so the autoplay guard below selects
            // the new model's first short instead of keeping a stale ID that is
            // not in the new pager.
            self.currentShortId = nil
            await self.viewModel.load()
            // Autoplay the first short on entry.
            if self.currentShortId == nil, let first = self.viewModel.shorts.first {
                self.currentShortId = first.videoId
                self.play(shortId: first.videoId)
            }
        }
        .onDisappear {
            self.stopIfPlayingShort()
        }
    }

    // MARK: - Pager

    private var pager: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(self.viewModel.shorts) { short in
                    ShortPage(
                        short: short,
                        isActive: self.isPresenting(short)
                    )
                    .containerRelativeFrame(.vertical)
                    .id(short.videoId)
                }
            }
            .scrollTargetLayout()
        }
        // Viewport-relative `.paging` accumulates the asymmetric navigation-bar
        // and player-bar safe-area offset on every page. Align the explicit
        // row targets instead so repeated wheel gestures cannot drift mid-page.
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: self.$currentShortId)
        .scrollIndicators(.hidden)
        .overlay(alignment: .trailing) {
            self.pagerArrows
        }
        .background(.black)
        .onChange(of: self.currentShortId) { _, shortId in
            guard let shortId else { return }
            self.play(shortId: shortId)
        }
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.shortsPager)
    }

    /// Up / down buttons at the window edge, like YouTube on the desktop.
    private var pagerArrows: some View {
        let shorts = self.viewModel.shorts
        let index = shorts.firstIndex { $0.videoId == self.currentShortId }

        return VStack(spacing: 12) {
            self.arrowButton("chevron.up", help: String(localized: "Previous Short"), isEnabled: (index ?? 0) > 0) {
                self.step(-1)
            }
            self.arrowButton("chevron.down", help: String(localized: "Next Short"), isEnabled: (index ?? -1) < shorts.count - 1) {
                self.step(1)
            }
        }
        .padding(.trailing, 18)
    }

    private func arrowButton(
        _ systemImage: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .compatGlass(interactive: true, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
    }

    /// Moves the pager by one short; autoplay follows `currentShortId`.
    private func step(_ offset: Int) {
        let shorts = self.viewModel.shorts
        guard let id = self.currentShortId,
              let index = shorts.firstIndex(where: { $0.videoId == id })
        else { return }
        let target = index + offset
        guard shorts.indices.contains(target) else { return }
        withAnimation(.smooth(duration: 0.3)) {
            self.currentShortId = shorts[target].videoId
        }
    }

    /// Whether the live surface belongs to this short.
    private func isPresenting(_ short: YouTubeVideo) -> Bool {
        self.youtubePlayer.currentVideo?.videoId == short.videoId
            && self.youtubePlayer.surfaceLocation == .inline
    }

    private func play(shortId: String) {
        guard let short = self.viewModel.shorts.first(where: { $0.videoId == shortId }) else {
            return
        }
        guard self.youtubePlayer.currentVideo?.videoId != short.videoId else { return }
        self.youtubePlayer.play(video: short, usesCookieFreeDataStore: self.authService.shouldUseCookieFreePlaybackDataStore)
        self.youtubePlayer.activeInlineVideoId = short.videoId
    }

    /// Leaving the Shorts surface ends shorts playback (a vertical short in
    /// the 16:9 floating window would be all pillarbox).
    private func stopIfPlayingShort() {
        guard let current = self.youtubePlayer.currentVideo,
              current.isShort,
              self.viewModel.shorts.contains(where: { $0.videoId == current.videoId }),
              self.youtubePlayer.surfaceLocation == .inline
        else {
            return
        }
        self.youtubePlayer.stop()
    }
}

// MARK: - ShortPage

/// One full-height page of the Shorts pager: the live 9:16 surface when
/// active, otherwise the thumbnail; title/channel overlaid at the bottom.
private struct ShortPage: View {
    let short: YouTubeVideo
    let isActive: Bool

    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @Environment(\.openURL) private var openURL

    var body: some View {
        // The card is centred: an empty column on the left balances the actions on the right.
        HStack(alignment: .bottom, spacing: 14) {
            Color.clear.frame(width: 44)
            self.card
            self.actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var card: some View {
        Group {
            if self.isActive {
                YouTubeWatchSurfaceView(expectedVideoId: self.short.videoId)
            } else {
                CachedAsyncImage(
                    url: self.short.thumbnailURL,
                    targetSize: CGSize(width: 540, height: 960)
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(.black)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .overlay {
            if self.isActive {
                // Tap anywhere on the short to pause / resume, like YouTube.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { self.youtubePlayer.playPause() }
            }
        }
        .overlay {
            if self.isActive, !self.youtubePlayer.isPlaying, !self.youtubePlayer.isPlaybackLoading {
                Image(systemName: "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .compatGlass(in: .circle)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                self.infoOverlay
                self.progressBar
            }
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityLabel(self.short.title)
    }

    /// Thin playback line along the bottom edge of the short.
    @ViewBuilder
    private var progressBar: some View {
        let duration = self.youtubePlayer.duration
        if self.isActive, duration > 0 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.25))
                    Rectangle()
                        .fill(.white)
                        .frame(width: proxy.size.width * min(max(self.youtubePlayer.progress / duration, 0), 1))
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: Actions

    /// Round action buttons to the right of the short. They act on the playing short only.
    private var actions: some View {
        VStack(spacing: 16) {
            self.actionButton(
                self.isActive && self.youtubePlayer.currentRating == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                help: String(localized: "Like")
            ) {
                Task { await self.youtubePlayer.toggleLike() }
            }
            self.actionButton(
                self.isActive && self.youtubePlayer.currentRating == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                help: String(localized: "Dislike")
            ) {
                Task { await self.youtubePlayer.toggleDislike() }
            }
            if let url = self.shortURL {
                ShareLink(item: url) {
                    self.actionIcon("square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help(String(localized: "Share"))
                self.actionButton("arrow.up.right.square", help: String(localized: "Open on YouTube")) {
                    self.openURL(url)
                }
            }
        }
        .frame(width: 44)
        .padding(.bottom, 8)
        .disabled(!self.isActive)
        .opacity(self.isActive ? 1 : 0.35)
    }

    private var shortURL: URL? {
        URL(string: "https://www.youtube.com/shorts/\(self.short.videoId)")
    }

    private func actionButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            self.actionIcon(systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func actionIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .compatGlass(interactive: true, in: .circle)
            .contentShape(.circle)
    }

    /// Title / channel overlay at the bottom of the short, Shorts-style.
    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.short.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            let detail = [self.short.channelName, self.short.viewCountText]
                .compactMap(\.self)
                .joined(separator: " · ")
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let shortsPager = "youtubeContent.shortsPager"
}
