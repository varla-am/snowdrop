import AppKit
import SwiftUI

// MARK: - DockEdge

/// Which screen edge the pill is tucked into.
enum DockEdge: String {
    case left
    case right
}

// MARK: - OverlayController

/// Hosts the now-playing pill in a floating, non-activating panel that stays above
/// other apps, follows you across Desktops and full-screen apps, and remembers where
/// it was dragged to. Nothing happens by itself: the arrow button tucks it into the
/// nearest side wall, and hovering or clicking the sliver that is left brings it back.
@MainActor
@Observable
final class OverlayController {
    static let shared = OverlayController()

    private(set) var isVisible = false
    /// The wall the pill is tucked into, nil while it floats free.
    private(set) var dockEdge: DockEdge?

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var programmaticMoveUntil = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    static let size = NSSize(width: 340, height: 76)

    /// How much of the pill stays visible in the wall.
    private let tab: CGFloat = 26
    private let margin: CGFloat = 12

    private enum Keys {
        static let visible = "overlayVisible"
        static let x = "overlayX"
        static let y = "overlayY"
        static let dock = "overlayDock"
    }

    private init() {}

    /// Reopens the overlay at launch if it was on when Snowdrop last quit.
    func restore(playerService: PlayerService, youtubePlayer: YouTubePlayerService) {
        if self.defaults.bool(forKey: Keys.visible) {
            self.show(playerService: playerService, youtubePlayer: youtubePlayer)
        }
    }

    func toggle(playerService: PlayerService, youtubePlayer: YouTubePlayerService) {
        self.isVisible ? self.hide() : self.show(playerService: playerService, youtubePlayer: youtubePlayer)
    }

    func show(playerService: PlayerService, youtubePlayer: YouTubePlayerService) {
        let panel = self.panel ?? self.makePanel(playerService: playerService, youtubePlayer: youtubePlayer)
        self.panel = panel
        panel.orderFrontRegardless()
        self.isVisible = true
        self.defaults.set(true, forKey: Keys.visible)
        self.updatePolling()
    }

    func hide() {
        self.stopPolling()
        self.panel?.orderOut(nil)
        self.isVisible = false
        self.defaults.set(false, forKey: Keys.visible)
    }

    // MARK: Panel

    private func makePanel(playerService: PlayerService, youtubePlayer: YouTubePlayerService) -> NSPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        // The status-bar layer, like the menu bar itself: windows down at `.floating` are drawn per
        // Desktop and ride in with the incoming one when you swipe, instead of staying put.
        panel.level = .statusBar
        // On every Desktop and over full-screen apps. `stationary` is what makes it stay put on
        // screen while the Desktops slide underneath, so it looks like it flies along with you;
        // without it the pill belongs to each Desktop and slides away with the old one.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        let hosting = FirstMouseHostingView(
            rootView: OverlayView(onClose: { [weak self] in self?.hide() })
                .environment(playerService)
                .environment(youtubePlayer)
        )
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting

        if self.defaults.object(forKey: Keys.x) != nil {
            panel.setFrameOrigin(NSPoint(x: self.defaults.double(forKey: Keys.x), y: self.defaults.double(forKey: Keys.y)))
        } else if let screen = NSScreen.main {
            // First run: bottom-right corner, clear of the Dock.
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - Self.size.width - 28, y: frame.minY + 28))
        }

        if let raw = self.defaults.string(forKey: Keys.dock), let edge = DockEdge(rawValue: raw) {
            self.dockEdge = edge
            panel.setFrame(self.hiddenFrame(for: edge, in: panel), display: false)
        }

        self.observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelDidMove() }
        })
        // Switching Desktops must never lose the pill: put it back in front each time.
        self.observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.panel?.orderFrontRegardless()
            }
        })
        return panel
    }

    // MARK: Moving

    private func visibleFrame(for panel: NSPanel) -> NSRect {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func move(to frame: NSRect, animated: Bool) {
        guard let panel else { return }
        self.programmaticMoveUntil = Date().addingTimeInterval(0.5)
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// A drag by hand: remember where the pill was dropped. No snapping, no hiding.
    private func panelDidMove() {
        guard let panel, Date() > self.programmaticMoveUntil else { return }
        if self.dockEdge != nil {
            // Pulled out of the wall by hand.
            self.dockEdge = nil
            self.defaults.removeObject(forKey: Keys.dock)
            self.stopPolling()
        }
        self.defaults.set(Double(panel.frame.origin.x), forKey: Keys.x)
        self.defaults.set(Double(panel.frame.origin.y), forKey: Keys.y)
    }

    // MARK: Tucking into the wall

    /// Flush against the wall, fully visible.
    private func revealedFrame(for edge: DockEdge, in panel: NSPanel) -> NSRect {
        let vis = self.visibleFrame(for: panel)
        var frame = panel.frame
        frame.origin.y = min(max(frame.origin.y, vis.minY + self.margin), vis.maxY - frame.height - self.margin)
        frame.origin.x = edge == .left ? vis.minX + self.margin : vis.maxX - frame.width - self.margin
        return frame
    }

    /// Only `tab` points stay on screen.
    private func hiddenFrame(for edge: DockEdge, in panel: NSPanel) -> NSRect {
        let vis = self.visibleFrame(for: panel)
        var frame = self.revealedFrame(for: edge, in: panel)
        frame.origin.x = edge == .left ? vis.minX - frame.width + self.tab : vis.maxX - self.tab
        return frame
    }

    /// Tucks the pill into whichever side wall is nearer.
    func tuck() {
        guard let panel, self.dockEdge == nil else { return }
        let vis = self.visibleFrame(for: panel)
        let edge: DockEdge = panel.frame.midX < vis.midX ? .left : .right
        let revealed = self.revealedFrame(for: edge, in: panel)
        // Where it comes back to.
        self.defaults.set(Double(revealed.origin.x), forKey: Keys.x)
        self.defaults.set(Double(revealed.origin.y), forKey: Keys.y)
        self.defaults.set(edge.rawValue, forKey: Keys.dock)
        self.dockEdge = edge
        self.move(to: self.hiddenFrame(for: edge, in: panel), animated: true)
        self.updatePolling()
    }

    /// Slides the pill back out of the wall and leaves it there.
    func reveal() {
        guard let panel, let edge = self.dockEdge else { return }
        self.dockEdge = nil
        self.defaults.removeObject(forKey: Keys.dock)
        self.stopPolling()
        let frame = NSRect(
            x: self.defaults.double(forKey: Keys.x), y: self.defaults.double(forKey: Keys.y),
            width: Self.size.width, height: Self.size.height
        )
        _ = edge
        self.move(to: frame, animated: true)
        _ = panel
    }

    /// The mouse only matters while the pill is tucked away: touching the sliver brings it out.
    private func updatePolling() {
        guard self.dockEdge != nil, self.isVisible else { return self.stopPolling() }
        guard self.pollTimer == nil else { return }
        self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, self.dockEdge != nil else { return }
                guard NSEvent.pressedMouseButtons == 0 else { return }
                if panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
                    self.reveal()
                }
            }
        }
    }

    private func stopPolling() {
        self.pollTimer?.invalidate()
        self.pollTimer = nil
    }
}

/// A borderless panel still has to accept clicks, hence the override.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// The pill is parked half off-screen on purpose; AppKit must not pull it back.
    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect { frameRect }
}

// MARK: - OverlayView

struct OverlayView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @State private var isHovering = false
    let onClose: () -> Void

    private var track: Song? {
        self.playerService.currentTrack
    }

    /// True while a YouTube video is what's playing (or what the app is showing), so the
    /// pill follows it instead of the music queue.
    private var isVideo: Bool {
        guard self.youtubePlayer.currentVideo != nil else { return false }
        return self.youtubePlayer.isPlaying
            || (SettingsManager.shared.appSource == .video && !self.playerService.isPlaying)
    }

    private var titleText: String {
        if self.isVideo { return self.youtubePlayer.currentVideo?.title ?? "Nothing playing" }
        return self.track?.title ?? "Nothing playing"
    }

    private var subtitleText: String {
        if self.isVideo { return self.youtubePlayer.currentVideo?.channelName ?? "YouTube" }
        return self.track?.artistsDisplay ?? "Snowdrop"
    }

    private var isPlayingNow: Bool {
        self.isVideo ? self.youtubePlayer.isPlaying : self.playerService.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            self.cover
            VStack(alignment: .leading, spacing: 2) {
                Text(self.titleText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(self.subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            self.controls
        }
        .padding(.horizontal, 12)
        .frame(width: 340, height: 76)
        .background(alignment: .bottom) { self.progressBar }
        .background { WindowDragHandle() }
        .compatGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                self.cornerButton("chevron.compact.right", action: { OverlayController.shared.tuck() })
                self.cornerButton("xmark", action: self.onClose)
            }
            .opacity(self.isHovering ? 1 : 0)
            .offset(x: 4, y: -4)
        }
        .overlay { self.dockedTab }
        .onHover { self.isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: self.isHovering)
    }

    /// What peeks out of the wall: a frosted sliver with an arrow pointing back into the screen.
    @ViewBuilder
    private var dockedTab: some View {
        let controller = OverlayController.shared
        if let edge = controller.dockEdge {
            // On the left wall the visible sliver is the pill's right end, and the other way round.
            HStack(spacing: 0) {
                if edge == .left { Spacer(minLength: 0) }
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
                    Image(systemName: edge == .left ? "chevron.compact.right" : "chevron.compact.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .trailing : .leading)
                        .padding(.horizontal, 5)
                }
                .frame(width: 340)
                if edge == .right { Spacer(minLength: 0) }
            }
            .contentShape(.rect)
            .onTapGesture { controller.reveal() }
        }
    }

    private func cornerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .background(.ultraThinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var coverURL: URL? {
        if self.isVideo { return self.youtubePlayer.currentVideo?.thumbnailURL }
        return self.track?.thumbnailURL?.highQualityThumbnailURL ?? self.track?.thumbnailURL
    }

    private var cover: some View {
        AsyncImage(url: self.coverURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.gray.opacity(0.25)
                Image(systemName: self.isVideo ? "play.rectangle.fill" : "music.note").foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.75))
    }

    private var controls: some View {
        HStack(spacing: 2) {
            self.button("backward.fill", size: 13) {
                if self.isVideo { self.youtubePlayer.skipBackward() } else { await self.playerService.previous() }
            }
            self.button(self.isPlayingNow ? "pause.fill" : "play.fill", size: 17) {
                if self.isVideo { self.youtubePlayer.playPause() } else { await self.playerService.playPause() }
            }
            self.button("forward.fill", size: 13) {
                if self.isVideo { await self.youtubePlayer.skipForward() } else { await self.playerService.next() }
            }
        }
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let duration = max(self.isVideo ? self.youtubePlayer.duration : self.playerService.duration, 1)
            let progress = self.isVideo ? self.youtubePlayer.progress : self.playerService.progress
            Capsule()
                .fill(.tint.opacity(0.7))
                .frame(width: max(0, proxy.size.width - 40) * min(1, progress / duration), height: 2.5)
                .padding(.leading, 20)
                .padding(.bottom, 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
