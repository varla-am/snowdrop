import SwiftUI
import WebKit

// MARK: - VideoPlayerWindow

/// Floating window for video playback: the clip with glass controls that fade in on hover.
struct VideoPlayerWindow: View {
    @Environment(PlayerService.self) private var playerService
    @State private var isHovering = false

    var body: some View {
        // The Window controls the aspect ratio and min size;
        // using .fit here can cause the webview to shrink/be letterboxed incorrectly during fast resize.
        ZStack {
            VideoWebViewContainer(videoId: self.playerService.pendingPlayVideoId)

            VStack(spacing: 0) {
                self.topControls
                Spacer(minLength: 0)
                self.transportControls
            }
            .padding(12)
            .opacity(self.isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: self.isHovering)
        }
        .background(.black)
        .onHover { self.isHovering = $0 }
        .accessibilityIdentifier(AccessibilityID.VideoWindow.container)
    }

    private var topControls: some View {
        HStack(alignment: .top) {
            if let track = self.playerService.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(track.artistsDisplay).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .compatGlass(in: .capsule)
            }
            Spacer()
            HStack(spacing: 2) {
                self.iconButton("arrow.up.left.and.arrow.down.right", help: "Full Screen") {
                    VideoWindowController.shared.toggleFullScreen()
                }
                self.iconButton("xmark", help: "Close Video") {
                    self.playerService.showVideo = false
                }
            }
            .padding(3)
            .compatGlass(in: .capsule)
        }
        // Clear of the traffic lights in the corner.
        .padding(.leading, 64)
    }

    private var transportControls: some View {
        HStack(spacing: 6) {
            self.iconButton("backward.fill", help: "Previous") {
                Task { await self.playerService.previous() }
            }
            self.iconButton(self.playerService.isPlaying ? "pause.fill" : "play.fill", help: "Play or Pause", size: 17) {
                Task { await self.playerService.playPause() }
            }
            self.iconButton("forward.fill", help: "Next") {
                Task { await self.playerService.next() }
            }
        }
        .padding(5)
        .compatGlass(in: .capsule)
    }

    private func iconButton(
        _ symbol: String, help: LocalizedStringKey, size: CGFloat = 13, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - VideoWebViewContainer

/// NSViewRepresentable container for the video WebView.
struct VideoWebViewContainer: NSViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService
    @Environment(AuthService.self) private var authService

    let videoId: String?

    func makeNSView(context _: Context) -> VideoContainerView {
        DiagnosticsLogger.player.info("VideoWebViewContainer.makeNSView called")
        let container = VideoContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        self.attachPlayerWebView(to: container)
        return container
    }

    func updateNSView(_ nsView: VideoContainerView, context _: Context) {
        DiagnosticsLogger.player.debug("VideoWebViewContainer.updateNSView called")
        self.attachPlayerWebView(to: nsView)
    }

    private func attachPlayerWebView(to container: VideoContainerView) {
        _ = SingletonPlayerWebView.shared.getWebView(
            webKitManager: self.webKitManager,
            playerService: self.playerService,
            usesCookieFreeDataStore: self.authService.shouldUseCookieFreePlaybackDataStore
        )
        SingletonPlayerWebView.shared.ensureInHierarchy(container: container)
        SingletonPlayerWebView.shared.updateDisplayMode(.video)

        if let videoId = self.videoId,
           self.playerService.shouldAutoloadPendingVideo,
           SingletonPlayerWebView.shared.currentVideoId != videoId
        {
            SingletonPlayerWebView.shared.loadVideo(videoId: videoId)
        }
    }
}

// MARK: - VideoContainerView

/// Custom NSView that observes frame changes and re-injects CSS.
final class VideoContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.frameDidChange),
            name: NSView.frameDidChangeNotification,
            object: self
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var refreshTask: Task<Void, Never>?

    @objc private func frameDidChange(_: Notification) {
        // Debounce slightly to prevent JS overload during continuous resize
        self.refreshTask?.cancel()
        self.refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .nanoseconds(16_666_666)) // ~60fps
            if !Task.isCancelled, SingletonPlayerWebView.shared.displayMode == .video {
                SingletonPlayerWebView.shared.refreshVideoModeCSS()
            }
        }
    }

    deinit {
        self.refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Preview

#Preview {
    VideoPlayerWindow()
        .environment(PlayerService())
        .environment(WebKitManager.shared)
        .environment(AuthService())
        .frame(width: 480, height: 270)
}
