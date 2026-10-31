import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Bundle

@main
struct SnowdropWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

// MARK: - Widget

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnowdropShared.widgetKind, provider: NowPlayingProvider()) { entry in
            NowPlayingView(entry: entry)
                .widgetURL(URL(string: "snowdrop://open"))
        }
        .configurationDisplayName("Now Playing")
        .description("The current track with its cover, progress and controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
    let artwork: NSImage?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in _: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: Self.sample, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(context.isPreview ? NowPlayingEntry(date: .now, snapshot: Self.sample, artwork: nil) : Self.current())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // The app asks for a reload whenever the track or play state changes, and the
        // progress bar animates by itself, so one entry is all the widget needs.
        completion(Timeline(entries: [Self.current()], policy: .never))
    }

    private static func current() -> NowPlayingEntry {
        let snapshot = NowPlayingSnapshot.load()
        let artwork = SnowdropShared.artworkURL.flatMap { NSImage(contentsOf: $0) }
        return NowPlayingEntry(date: .now, snapshot: snapshot, artwork: snapshot.hasTrack ? artwork : nil)
    }

    private static let sample = NowPlayingSnapshot(
        hasTrack: true, title: "Snowdrop", artist: "Your music", album: "", isPlaying: true,
        progress: 40, duration: 200, updatedAt: .now,
        upNext: [.init(title: "Next song", artist: "Artist"), .init(title: "Another one", artist: "Artist")],
        accent: [0.42, 0.72, 0.95], artworkID: ""
    )
}

// MARK: - Views

struct NowPlayingView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: NowPlayingSnapshot {
        self.entry.snapshot
    }

    private var accent: Color {
        let c = self.snapshot.accent
        return c.count == 3 ? Color(red: c[0], green: c[1], blue: c[2]) : .accentColor
    }

    var body: some View {
        Group {
            if self.snapshot.hasTrack {
                switch self.family {
                case .systemSmall: self.small
                case .systemMedium: self.medium
                default: self.large
                }
            } else {
                self.idle
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { self.background }
    }

    // MARK: Layouts

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                self.cover(size: 58, radius: 14)
                Spacer()
                Image(systemName: self.snapshot.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: self.snapshot.isPlaying)
                    .foregroundStyle(self.accent)
            }
            Spacer(minLength: 6)
            self.titleBlock(titleSize: 14)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            self.cover(size: 112, radius: 20)
            VStack(alignment: .leading, spacing: 6) {
                self.titleBlock(titleSize: 16)
                Spacer(minLength: 0)
                self.progressBar
                self.controls(size: 19)
            }
        }
    }

    private var large: some View {
        VStack(spacing: 12) {
            self.cover(size: 170, radius: 26)
            self.titleBlock(titleSize: 18, centered: true)
            self.progressBar
            self.controls(size: 24)

            if !self.snapshot.upNext.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.55))
                    ForEach(Array(self.snapshot.upNext.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Text(item.title).fontWeight(.medium).lineLimit(1)
                            Text(item.artist).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 12))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image(systemName: "snowflake")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(self.accent)
            Text("Nothing playing")
                .font(.system(size: 14, weight: .semibold))
            Text("Open Snowdrop to start")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pieces

    private func titleBlock(titleSize: CGFloat, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 2) {
            Text(self.snapshot.title)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(centered ? .center : .leading)
            Text(self.snapshot.artist)
                .font(.system(size: titleSize - 4, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    @ViewBuilder
    private var progressBar: some View {
        if self.snapshot.isPlaying, self.snapshot.duration > 0 {
            let start = self.snapshot.updatedAt.addingTimeInterval(-self.snapshot.progress)
            let end = start.addingTimeInterval(self.snapshot.duration)
            ProgressView(timerInterval: start ... end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(self.accent)
        } else if self.snapshot.duration > 0 {
            ProgressView(value: min(self.snapshot.progress, self.snapshot.duration), total: self.snapshot.duration)
                .progressViewStyle(.linear)
                .tint(self.accent)
        }
    }

    private func controls(size: CGFloat) -> some View {
        HStack(spacing: size * 1.1) {
            Button(intent: WidgetPreviousTrackIntent()) {
                Image(systemName: "backward.fill")
            }
            Button(intent: WidgetTogglePlaybackIntent()) {
                Image(systemName: self.snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: size * 1.7))
                    .foregroundStyle(self.accent)
            }
            Button(intent: WidgetNextTrackIntent()) {
                Image(systemName: "forward.fill")
            }
        }
        .font(.system(size: size))
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func cover(size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let artwork = self.entry.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [self.accent, self.accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.85)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }

    /// The cover, blown up and blurred, under a dark wash so white text stays readable.
    private var background: some View {
        ZStack {
            if let artwork = self.entry.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .saturation(1.3)
            } else {
                LinearGradient(colors: [self.accent.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
    }
}
