import WebKit

// MARK: - PlaybackWebViewUIDelegate

/// UI delegate for the hidden/extracted playback WebViews (music and YouTube watch).
///
/// Without a `WKUIDelegate`, WebKit silently drops `window.open` and answers
/// every `alert`/`confirm`/`prompt` with its defaults. That is the behaviour we
/// want for a playback surface, but relying on the absence of a delegate makes
/// it implicit and leaves no place to log when the page tries. This delegate
/// makes those decisions explicit: no popups are ever created, dialogs are
/// dismissed immediately, and each attempt is logged once so a regression on
/// YouTube's side shows up in diagnostics instead of as a mysterious hang.
@MainActor
final class PlaybackWebViewUIDelegate: NSObject, WKUIDelegate {
    static let shared = PlaybackWebViewUIDelegate()

    private let logger = DiagnosticsLogger.player

    override private init() {
        super.init()
    }

    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        self.logger.info(
            "Playback WebView popup suppressed: \(navigationAction.request.url?.host ?? "nil", privacy: .public)"
        )
        return nil
    }

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage _: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        self.logger.info("Playback WebView alert suppressed from \(frame.securityOrigin.host, privacy: .public)")
        completionHandler()
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage _: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        self.logger.info("Playback WebView confirm suppressed from \(frame.securityOrigin.host, privacy: .public)")
        completionHandler(false)
    }

    func webView(
        _: WKWebView,
        runJavaScriptTextInputPanelWithPrompt _: String,
        defaultText _: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        self.logger.info("Playback WebView prompt suppressed from \(frame.securityOrigin.host, privacy: .public)")
        completionHandler(nil)
    }
}
