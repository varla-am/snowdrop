import SwiftUI

// MARK: - HomeSectionItemCard

/// Reusable card view for home section items (songs, playlists, albums, artists).
struct HomeSectionItemCard: View, Equatable {
    let item: HomeSectionItem
    let rank: Int?
    let playAction: (() -> Void)?
    let action: () -> Void
    private let hasPlayAction: Bool
    @Environment(AuthService.self) private var authService

    /// Card dimensions.
    private static let squareThumbnailSize = CGSize(width: 160, height: 160)
    private static let videoThumbnailSize = CGSize(width: 284, height: 160)
    private static let playButtonSize = CGSize(width: 48, height: 48)

    /// Hover state for play overlay.
    @State private var isHovering = false
    @State private var failedThumbnailURLs: Set<URL> = []

    init(
        item: HomeSectionItem,
        rank: Int? = nil,
        playAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.rank = rank
        self.playAction = playAction
        self.action = action
        self.hasPlayAction = playAction != nil
    }

    /// Lets SwiftUI skip re-evaluating unchanged cards when a shelf or its
    /// parent re-renders (measured: this is what made Home scrolling hitch).
    ///
    /// Contract for callers: `action`/`playAction` must depend only on `item`
    /// (and `rank`). If two cards compare equal, the old closures are kept, so
    /// an action that captured section membership or index would go stale.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.hasSameCardContent(as: rhs.item)
            && lhs.rank == rhs.rank
            && lhs.hasPlayAction == rhs.hasPlayAction
    }

    var body: some View {
        if self.supportsPlaylistPlayAction {
            self.cardContent
                .accessibilityAction(named: Text("Play \(self.item.title)")) {
                    self.playAction?()
                }
        } else {
            self.cardContent
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .topLeading) {
            Button(action: self.action) {
                if let rank {
                    self.chartContent(rank: rank)
                } else {
                    self.regularContent
                }
            }
            // Hover feedback lives on the thumbnail (see `thumbnail`), so the
            // button style only contributes press feedback and registers no
            // hover responder.
            .buttonStyle(.interactiveCard(showShadow: false, hoverScale: 1))
        }
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHovering = hovering
            }
        }
        .onChange(of: self.item.id) { _, _ in
            self.failedThumbnailURLs = []
        }
    }

    // MARK: - Regular Card Content

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.thumbnail
            self.titleAndSubtitle
        }
    }

    // MARK: - Chart Card Content

    private func chartContent(rank: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                self.thumbnail
                self.titleAndSubtitle
            }

            // Rank badge overlay with adaptive styling
            Text("\(rank)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.8), radius: 4, x: 0, y: 1)
                .padding(.leading, 8)
                .padding(.bottom, 60)
        }
    }

    // MARK: - Shared Components

    private var thumbnail: some View {
        let thumbnailURLs = self.thumbnailURLs
        let thumbnailURL = thumbnailURLs.first { !self.failedThumbnailURLs.contains($0) }

        return ZStack {
            self.thumbnailBackground

            if let thumbnailURL {
                CachedAsyncImage(
                    url: thumbnailURL,
                    targetSize: self.thumbnailSize,
                    onFailure: self.thumbnailFailureHandler(for: thumbnailURL, in: thumbnailURLs)
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: self.thumbnailContentMode)
                } placeholder: {
                    self.placeholderView
                }
            } else {
                self.placeholderView
            }
        }
        .frame(width: self.thumbnailSize.width, height: self.thumbnailSize.height)
        .clipShape(.rect(cornerRadius: VolumetricCover.cornerRadius, style: .continuous))
        // Depth, glass rim and hover tilt, applied outside the image so the
        // loaded image keeps its identity.
        .modifier(VolumetricCover(isHovering: self.isHovering, size: self.thumbnailSize, showsStack: self.showsSleeveStack))
        .overlay {
            // Play overlay on hover (for songs)
            if case .song = self.item, self.isHovering {
                SongCoverPlayOverlay(size: Self.playButtonSize)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Favorite heart in the corner for songs
            if case let .song(song) = self.item {
                LikeButton(song: song, isRowHovered: self.isHovering, allowsActions: self.authService.hasPersonalAccount)
                    .padding(6)
            }
        }
    }

    private var supportsPlaylistPlayAction: Bool {
        guard case .playlist = self.item else { return false }
        return self.hasPlayAction
    }

    @ViewBuilder
    private var thumbnailBackground: some View {
        if self.isVideoSong {
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
    }

    private var thumbnailURLs: [URL] {
        if self.isVideoSong {
            return Self.uniqueURLs([
                self.videoThumbnailURL,
                self.item.thumbnailURL?.highQualityThumbnailURL,
                self.videoFallbackThumbnailURL,
            ])
        }

        return Self.uniqueURLs([self.item.thumbnailURL?.highQualityThumbnailURL])
    }

    private func thumbnailFailureHandler(for thumbnailURL: URL, in thumbnailURLs: [URL]) -> (@MainActor () -> Void)? {
        guard self.hasFallback(after: thumbnailURL, in: thumbnailURLs) else {
            return nil
        }

        return {
            self.failedThumbnailURLs.insert(thumbnailURL)
        }
    }

    private var videoThumbnailURL: URL? {
        guard case let .song(song) = self.item else { return nil }
        return song.wideHighQualityThumbnailURL
    }

    private var videoFallbackThumbnailURL: URL? {
        guard case let .song(song) = self.item else { return nil }
        return song.fallbackThumbnailURL
    }

    private var thumbnailContentMode: ContentMode {
        self.isVideoSong ? .fit : .fill
    }

    private func hasFallback(after url: URL, in thumbnailURLs: [URL]) -> Bool {
        guard let index = thumbnailURLs.firstIndex(of: url) else { return false }
        let fallbackURLs = thumbnailURLs.dropFirst(index + 1)
        return fallbackURLs.contains { !self.failedThumbnailURLs.contains($0) }
    }

    private static func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { url in
            guard let url, seen.insert(url).inserted else { return nil }
            return url
        }
    }

    /// Placeholder view for items without thumbnails.
    /// Uses the API-provided color for mood/genre cards, or a gradient based on the title.
    private var placeholderView: some View {
        let gradient = self.gradientForItem
        return Rectangle()
            .fill(gradient)
            .overlay {
                // Show a contextual icon based on item type
                Image(systemName: self.placeholderIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

    /// Returns appropriate icon for the placeholder based on item type.
    private var placeholderIcon: String {
        switch self.item {
        case .song: self.isVideoSong ? "play.rectangle" : "music.note"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "person.fill"
        }
    }

    /// Generates a gradient for the card.
    /// Uses API-provided color (from description) for mood cards, or title-based hash.
    private var gradientForItem: LinearGradient {
        // Check if this is a mood card with color in description
        if case let .playlist(playlist) = item,
           let colorHex = playlist.description,
           colorHex.hasPrefix("#"),
           let color = Color(hex: colorHex)
        {
            // Create a gradient from the API color
            return LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // Fallback to title-based gradient
        return Self.gradientForTitle(self.item.title)
    }

    /// Generates a consistent gradient color based on the title string.
    private static func gradientForTitle(_ title: String) -> LinearGradient {
        let hash = abs(title.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.1).truncatingRemainder(dividingBy: 1.0)

        let color1 = Color(hue: hue1, saturation: 0.6, brightness: 0.5)
        let color2 = Color(hue: hue2, saturation: 0.7, brightness: 0.35)

        return LinearGradient(
            colors: [color1, color2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var titleAndSubtitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(self.item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if case let .song(song) = self.item, song.isExplicit == true {
                    ExplicitBadge()
                }
            }
            .frame(width: self.cardWidth, alignment: .leading)

            if let subtitle = self.item.homeCardSubtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: self.cardWidth, alignment: .leading)
            }
        }
    }

    private var cardWidth: CGFloat {
        self.thumbnailSize.width
    }

    private var thumbnailSize: CGSize {
        self.isVideoSong ? Self.videoThumbnailSize : Self.squareThumbnailSize
    }

    private var isVideoSong: Bool {
        self.item.isVideoSong
    }

    /// Albums, playlists and charts read as a stack of records; single songs
    /// and artists stay flat.
    private var showsSleeveStack: Bool {
        switch self.item {
        case .album, .playlist: true
        case .song, .artist: false
        }
    }
}

// MARK: - VolumetricCover

/// Gives a cover depth: a stack of sleeves behind it, a soft shadow, a lit
/// glass rim and a 3D tilt that follows the pointer.
private struct VolumetricCover: ViewModifier {
    static let cornerRadius: CGFloat = 14

    let isHovering: Bool
    let size: CGSize
    let showsStack: Bool

    /// Pointer position within the cover, -0.5 ... 0.5 on each axis.
    @State private var tilt: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .overlay { self.glassRim }
            .overlay { self.sheen }
            .background(alignment: .top) {
                if self.showsStack { self.sleeves }
            }
            .shadow(color: .black.opacity(self.isHovering ? 0.38 : 0.22), radius: self.isHovering ? 18 : 9, x: 0, y: self.isHovering ? 12 : 5)
            .rotation3DEffect(
                .degrees(self.isHovering ? Double(self.tilt.height) * 14 : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.6
            )
            .rotation3DEffect(
                .degrees(self.isHovering ? Double(-self.tilt.width) * 14 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .scaleEffect(self.isHovering ? 1.04 : 1)
            .offset(y: self.isHovering ? -3 : 0)
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    self.tilt = CGSize(
                        width: point.x / max(self.size.width, 1) - 0.5,
                        height: point.y / max(self.size.height, 1) - 0.5
                    )
                case .ended:
                    self.tilt = .zero
                }
            }
            .animation(AppAnimation.spring, value: self.isHovering)
            .animation(.smooth(duration: 0.12), value: self.tilt)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    /// Thin bright edge that is strongest top-left, like light on glass.
    private var glassRim: some View {
        self.shape
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    /// Soft specular highlight across the top; follows the tilt when hovering.
    private var sheen: some View {
        self.shape
            .fill(
                LinearGradient(
                    colors: [.white.opacity(self.isHovering ? 0.28 : 0.16), .clear],
                    startPoint: UnitPoint(x: 0.5 + Double(-self.tilt.width), y: 0),
                    endPoint: UnitPoint(x: 0.5 + Double(self.tilt.width), y: 0.6)
                )
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    /// Two records peeking out behind the cover.
    private var sleeves: some View {
        ZStack(alignment: .top) {
            self.shape
                .fill(.regularMaterial)
                .overlay(self.shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .frame(width: self.size.width * 0.80, height: self.size.height)
                .offset(y: self.isHovering ? -14 : -9)
                .opacity(0.55)
            self.shape
                .fill(.thinMaterial)
                .overlay(self.shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .frame(width: self.size.width * 0.90, height: self.size.height)
                .offset(y: self.isHovering ? -7 : -4.5)
                .opacity(0.8)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - LiquidGlassPlayIcon

private struct LiquidGlassPlayIcon: View {
    let size: CGSize
    let interactive: Bool

    var body: some View {
        Image(systemName: "play.fill")
            .font(.title2)
            .foregroundStyle(.primary)
            .offset(x: 2)
            .frame(width: self.size.width, height: self.size.height)
            .compatGlass(interactive: self.interactive, in: .circle)
    }
}

// MARK: - SongCoverPlayOverlay

struct SongCoverPlayOverlay: View {
    let size: CGSize

    var body: some View {
        LiquidGlassPlayIcon(size: self.size, interactive: false)
            .allowsHitTesting(false)
    }
}

#Preview {
    let song = Song(
        id: "test",
        title: "Test Song with a Very Long Title That Should Wrap",
        artists: [Artist(id: "artist1", name: "Test Artist")],
        videoId: "testVideo"
    )
    HStack {
        HomeSectionItemCard(item: .song(song)) {
            // No-op for preview
        }
        HomeSectionItemCard(item: .song(song), rank: 1) {
            // No-op for preview
        }
    }
    .padding()
    .environment(AuthService())
    .environment(SongLikeStatusManager.shared)
}
