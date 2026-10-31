import SwiftUI

// MARK: - HomeChipsBar

/// Row of pill chips under the top bar. Each chip scrolls Home to that section.
struct HomeChipsBar: View {
    let titles: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainerCompat {
                HStack(spacing: 8) {
                    self.chip(title: String(localized: "All"), isSelected: self.selected == nil) {
                        self.onSelect(nil)
                    }
                    ForEach(self.titles, id: \.self) { title in
                        self.chip(title: title, isSelected: self.selected == title) {
                            self.onSelect(title)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background {
                    if isSelected {
                        Capsule().fill(.tint)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .compatGlass(interactive: true, in: Capsule())
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}

/// Groups glass shapes so they merge and morph; plain container before macOS 26.
private struct GlassEffectContainerCompat<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { self.content() }
        } else {
            self.content()
        }
    }
}

// MARK: - HomeSectionHeader

/// Section title in the Home style: small eyebrow over a large rounded title.
struct HomeSectionHeader: View {
    let title: String
    let eyebrow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(self.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
    }
}

// MARK: - QuickPicksGrid

/// Compact song rows in four rows, scrolling sideways, like the YouTube Music home.
struct QuickPicksGrid<Menu: View>: View {
    let songs: [Song]
    let contentInset: CGFloat
    let onPlay: (Song) -> Void
    let menu: (Song) -> Menu

    private let rows = Array(repeating: GridItem(.fixed(60), spacing: 6), count: 4)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: self.rows, spacing: 14) {
                ForEach(self.songs, id: \.id) { song in
                    QuickPickRow(song: song, onPlay: { self.onPlay(song) })
                        .frame(width: 330)
                        .contextMenu { self.menu(song) }
                }
            }
            .padding(.horizontal, self.contentInset)
            .padding(.vertical, 4)
        }
        .frame(height: 4 * 60 + 3 * 6 + 8)
        .scrollClipDisabled()
    }
}

private struct QuickPickRow: View {
    let song: Song
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: self.onPlay) {
            HStack(spacing: 12) {
                self.cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(self.song.artistsDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.primary.opacity(self.isHovering ? 0.10 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { self.isHovering = hovering }
        }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
            if let url = self.song.thumbnailURL?.highQualityThumbnailURL {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 48, height: 48)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            if self.isHovering {
                Color.black.opacity(0.35)
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}
