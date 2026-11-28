import AppKit
import SwiftUI
import WebKit

// MARK: - YouTubeLiveChatWindowController

/// A separate window with the chat of the live stream that is playing.
///
/// It loads YouTube's own pop-out chat page in a WebView that shares the app's
/// signed-in session, so you can read and write like in the browser.
@MainActor
final class YouTubeLiveChatWindowController: NSObject, NSWindowDelegate {
    static let shared = YouTubeLiveChatWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var loadedVideoId: String?
    private let frameAutosaveKey = "SnowdropYouTubeLiveChatWindow"

    private static let minContentSize = NSSize(width: 300, height: 360)

    override private init() {
        super.init()
    }

    /// Opens the chat window for a live video, or points an open one at it.
    func show(videoId: String, title: String?) {
        if self.window == nil {
            self.createWindow()
        }
        guard let window = self.window else { return }
        window.title = title.map { String(localized: "Live chat — \($0)") } ?? String(localized: "Live chat")
        self.load(videoId: videoId)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        self.window?.close()
    }

    // MARK: - Private

    private func load(videoId: String) {
        guard self.loadedVideoId != videoId, let webView = self.webView else { return }
        self.loadedVideoId = videoId
        var components = URLComponents(string: "https://www.youtube.com/live_chat")
        components?.queryItems = [
            URLQueryItem(name: "is_popout", value: "1"),
            URLQueryItem(name: "dark_theme", value: "1"),
            URLQueryItem(name: "v", value: videoId),
        ]
        guard let url = components?.url else { return }
        webView.load(URLRequest(url: url))
    }

    private func createWindow() {
        // A bare configuration: only the signed-in cookie store is shared. The
        // player's configuration also carries the web-extension controller and
        // autoplay settings, and sharing those with a second YouTube page made
        // the main player misbehave once the chat opened.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WebKitManager.shared.dataStore
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.glassScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Without a browser-like user agent YouTube answers "you're using an older browser".
        webView.customUserAgent = WebKitManager.userAgent
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isOpaque = false

        // The same themed, see-through backdrop as Snowdrop's main window (theme
        // colour, transparency and blur all follow Settings), with the chat on top.
        let glass = NSView()
        let backdrop = NSHostingView(rootView: Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .snowdropWindowStyle())
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(backdrop)
        glass.addSubview(webView)
        // The views must be in the window before they are pinned to the window's
        // layout guide: activating that constraint earlier throws and wedges the UI.
        window.contentView = glass
        // Only the close button, like a small utility panel.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titleVisibility = .hidden
        let topGuide = (window.contentLayoutGuide as? NSLayoutGuide) ?? glass.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: glass.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            webView.topAnchor.constraint(equalTo: topGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minContentSize
        window.identifier = NSUserInterfaceItemIdentifier(AccessibilityID.YouTubeContent.liveChatWindow)
        window.delegate = self
        if !window.setFrameUsingName(self.frameAutosaveKey) {
            window.center()
        }
        window.setFrameAutosaveName(self.frameAutosaveKey)
        self.window = window
    }

    /// Makes the chat page see-through so the window's glass shows behind the messages.
    private static let glassScript = #"""
    (function() {
        var css = [
            'html, body, yt-live-chat-app, yt-live-chat-renderer, #chat, #contents, #item-scroller, #item-list,',
            '#chat-messages, yt-live-chat-header-renderer, #ticker, #input-panel, yt-live-chat-message-input-renderer,',
            'yt-live-chat-renderer #separator { background: transparent !important; background-color: transparent !important; }',
            'html { --yt-live-chat-background-color: transparent !important; --yt-live-chat-action-panel-background-color: transparent !important;',
            '  --yt-live-chat-header-background-color: transparent !important; }',
            'yt-live-chat-renderer { --yt-live-chat-background-color: transparent !important; }',
            '#input-panel, yt-live-chat-header-renderer { border-color: rgba(255,255,255,0.14) !important; }',
            // One capsule: the field's own inner box stays clear, or it shows as a pill inside the pill.
            '#input-container { background: rgba(255,255,255,0.10) !important; border-radius: 14px !important; }',
            '#input-container #input, #input-container yt-live-chat-text-input-field-renderer, #input-container #underline { background: transparent !important; border: 0 !important; box-shadow: none !important; }',
            '::-webkit-scrollbar { width: 0 !important; }'
        ].join('\n');
        var style = document.createElement('style');
        style.textContent = css;
        (document.head || document.documentElement).appendChild(style);
    })();
    """#

    func windowWillClose(_: Notification) {
        // Stop the page (and its network use) while the window is closed.
        self.webView?.load(URLRequest(url: URL(string: "about:blank")!)) // swiftlint:disable:this force_unwrapping
        self.loadedVideoId = nil
    }
}
