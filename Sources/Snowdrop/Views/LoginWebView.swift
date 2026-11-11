import AppKit
import SwiftUI
import WebKit

/// WebView for Google login.
struct LoginWebView: NSViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager

    /// Callback when navigation completes to YouTube Music.
    var onNavigationToYouTubeMusic: (() -> Void)?

    /// Google's sign-in entry point, continuing to YouTube Music on success.
    static let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F")

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationToYouTubeMusic: self.onNavigationToYouTubeMusic)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = self.webKitManager.createSessionSwitchWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = WebKitManager.userAgent
        #if DEBUG
            webView.isInspectable = true
        #endif

        context.coordinator.loadLoginPage(in: webView)
        return webView
    }

    func updateNSView(_: WKWebView, context: Context) {
        // SwiftUI may rebuild the parent with a fresh closure; keep the
        // coordinator pointing at the current one instead of a stale copy.
        context.coordinator.onNavigationToYouTubeMusic = self.onNavigationToYouTubeMusic
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // The sheet is going away: stop any in-flight sign-in navigation so a
        // late redirect cannot fire callbacks into a view that no longer exists.
        coordinator.onNavigationToYouTubeMusic = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    /// Whether `host` is YouTube Music itself (exact or a subdomain), never a
    /// look-alike such as `music.youtube.com.example`.
    nonisolated static func isYouTubeMusicHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "music.youtube.com" || host.hasSuffix(".music.youtube.com")
    }

    /// Hosts the embedded sign-in sheet keeps inside itself. Anything else the
    /// user clicks (help centre, privacy policy on a third-party domain) opens
    /// in the default browser so the sheet never becomes a trapped mini-browser
    /// with no back button.
    nonisolated static func keepsNavigationInSheet(host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        let trustedSuffixes = [
            "google.com",
            "youtube.com",
            "gstatic.com",
            "googleusercontent.com",
            "googleapis.com",
            "ggpht.com",
            "recaptcha.net",
        ]
        return trustedSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onNavigationToYouTubeMusic: (() -> Void)?
        private var contentProcessRecoveryCount = 0
        private let logger = DiagnosticsLogger.auth

        init(onNavigationToYouTubeMusic: (() -> Void)?) {
            self.onNavigationToYouTubeMusic = onNavigationToYouTubeMusic
        }

        func loadLoginPage(in webView: WKWebView) {
            guard let url = LoginWebView.loginURL else { return }
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Check if we've navigated to YouTube Music
            if LoginWebView.isYouTubeMusicHost(webView.url?.host) {
                self.onNavigationToYouTubeMusic?()
            }
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isHTTP = url?.scheme?.lowercased() == "https" || url?.scheme?.lowercased() == "http"

            // Popups (`target="_blank"`) cannot be hosted by the sheet: hand
            // http(s) ones to the default browser, drop the rest.
            if navigationAction.targetFrame == nil {
                if isHTTP, let url {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            // Redirects and form posts drive the sign-in flow and must stay
            // untouched; only explicit link clicks off Google's domains leave.
            if navigationAction.navigationType == .linkActivated,
               navigationAction.targetFrame?.isMainFrame == true,
               isHTTP,
               let url,
               !LoginWebView.keepsNavigationInSheet(host: url.host)
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            guard !WebPlaybackNavigationFailure.isRetryableCancellation(error) else { return }
            self.logger.error("Login page navigation failed (\(nsError.domain, privacy: .public) \(nsError.code))")
            // A failed first load leaves a blank sheet with no way to retry;
            // bring the entry point back so the user can try again.
            if webView.url == nil {
                self.loadLoginPage(in: webView)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            self.contentProcessRecoveryCount += 1
            self.logger.error("Login WebView content process terminated (recovery #\(self.contentProcessRecoveryCount))")
            // Bounded: a page that keeps crashing the process must not loop.
            guard self.contentProcessRecoveryCount <= 3 else { return }
            self.loadLoginPage(in: webView)
        }

        // MARK: WKUIDelegate

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               url.scheme?.lowercased() == "https"
            {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

#Preview {
    LoginWebView()
        .environment(WebKitManager.shared)
        .frame(width: 500, height: 600)
}
