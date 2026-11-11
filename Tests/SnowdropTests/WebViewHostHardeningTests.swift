import AppKit
import Testing
import WebKit
@testable import Snowdrop

@Suite("WebView host hardening", .serialized, .tags(.service))
@MainActor
struct WebViewHostHardeningTests {
    @Test("Login success is detected only on YouTube Music itself, not a look-alike host")
    func loginHostMatchIsExact() {
        #expect(LoginWebView.isYouTubeMusicHost("music.youtube.com"))
        #expect(LoginWebView.isYouTubeMusicHost("MUSIC.YOUTUBE.COM"))
        #expect(!LoginWebView.isYouTubeMusicHost("music.youtube.com.example"))
        #expect(!LoginWebView.isYouTubeMusicHost("notmusic.youtube.com"))
        #expect(!LoginWebView.isYouTubeMusicHost("www.youtube.com"))
        #expect(!LoginWebView.isYouTubeMusicHost(nil))
    }

    @Test("Sign-in sheet keeps Google-owned hosts and hands everything else to the browser")
    func loginSheetNavigationAllowlist() {
        #expect(LoginWebView.keepsNavigationInSheet(host: "accounts.google.com"))
        #expect(LoginWebView.keepsNavigationInSheet(host: "www.youtube.com"))
        #expect(LoginWebView.keepsNavigationInSheet(host: "www.gstatic.com"))
        #expect(!LoginWebView.keepsNavigationInSheet(host: "example.com"))
        #expect(!LoginWebView.keepsNavigationInSheet(host: "google.com.example"))
        #expect(!LoginWebView.keepsNavigationInSheet(host: nil))
    }

    @Test("A disappearing host detaches the watch surface it owns and no other")
    func hostContainerDisappearanceDetachesOwnedSurfaceOnly() {
        let singleton = YouTubeWatchWebView.makeTestInstance()
        let webKitManager = WebKitManager.makeTestInstance()
        let playerService = YouTubePlayerService(webKitManager: webKitManager)
        let webView = singleton.getWebView(webKitManager: webKitManager, playerService: playerService)
        defer { singleton.tearDown() }

        let firstHost = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let secondHost = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))

        singleton.ensureInHierarchy(container: firstHost)
        #expect(webView.superview === firstHost)

        // Another host already claimed the surface: the old host's teardown
        // must not steal it back out of the new one.
        singleton.ensureInHierarchy(container: secondHost)
        singleton.hostContainerWillDisappear(firstHost)
        #expect(webView.superview === secondHost)

        singleton.hostContainerWillDisappear(secondHost)
        #expect(webView.superview == nil)
    }

    @Test("Playback WebViews carry the popup-refusing UI delegate until teardown")
    func playbackWebViewsRefusePopups() {
        let singleton = YouTubeWatchWebView.makeTestInstance()
        let webKitManager = WebKitManager.makeTestInstance()
        let playerService = YouTubePlayerService(webKitManager: webKitManager)
        let webView = singleton.getWebView(webKitManager: webKitManager, playerService: playerService)

        #expect(webView.uiDelegate === PlaybackWebViewUIDelegate.shared)

        let musicSingleton = SingletonPlayerWebView.makeTestInstance()
        let musicWebView = musicSingleton.getWebView(
            webKitManager: webKitManager,
            playerService: PlayerService()
        )
        #expect(musicWebView.uiDelegate === PlaybackWebViewUIDelegate.shared)

        singleton.tearDown()
        musicSingleton.tearDown()
        #expect(webView.uiDelegate == nil)
        #expect(musicWebView.uiDelegate == nil)
    }
}
