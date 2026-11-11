import AppKit
import SwiftUI
import WebKit

/// A view that displays the options page of a WebKit extension.
struct ExtensionOptionsView: NSViewRepresentable {
    let page: WebKitManager.ExtensionPage

    private static let consoleHandlerName = "optionsDebug"

    func makeNSView(context: Context) -> WKWebView {
        let config = (self.page.configuration.copy() as? WKWebViewConfiguration) ?? self.page.configuration

        // Inject script to pipe console to native
        let consoleProxyScript = WKUserScript(
            source: """
            (function() {
                var oldLog = console.log;
                var oldError = console.error;
                var oldWarn = console.warn;
                console.log = function() {
                    window.webkit.messageHandlers.optionsDebug.postMessage("LOG: " + Array.from(arguments).join(" "));
                    oldLog.apply(console, arguments);
                };
                console.error = function() {
                    window.webkit.messageHandlers.optionsDebug.postMessage("ERROR: " + Array.from(arguments).join(" "));
                    oldError.apply(console, arguments);
                };
                console.warn = function() {
                    window.webkit.messageHandlers.optionsDebug.postMessage("WARN: " + Array.from(arguments).join(" "));
                    oldWarn.apply(console, arguments);
                };
                window.onerror = function(msg, url, line, col, error) {
                    window.webkit.messageHandlers.optionsDebug.postMessage("UNCAUGHT ERROR: " + msg + " at " + url + ":" + line + ":" + col);
                    return false;
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(consoleProxyScript)
        // `add` raises an exception on a duplicate name. The copy above should
        // give us a fresh controller, but if the copy failed we are sharing the
        // extension context's own configuration, so clear any earlier handler.
        config.userContentController.removeScriptMessageHandler(forName: Self.consoleHandlerName)
        config.userContentController.add(context.coordinator, name: Self.consoleHandlerName)

        let webView = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
            webView.isInspectable = true
        #endif

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(self.page.url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload only when the *requested* page changes. Comparing against
        // `webView.url` reloaded the options page on every in-page navigation
        // (hash tabs, pushState), which snapped the user back to the start.
        context.coordinator.load(self.page.url, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator _: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        // The content controller retains its handlers strongly; drop ours so the
        // coordinator and the configuration copy can be released.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.consoleHandlerName)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        private var requestedURL: URL?
        private var contentProcessRecoveryCount = 0

        /// Loads `url` unless it is already the requested page.
        func load(_ url: URL, in webView: WKWebView) {
            guard self.requestedURL != url else { return }
            self.requestedURL = url
            // Tiny delay to ensure WebKit's internal extension registry has caught up with the ID
            Task { @MainActor [weak webView] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let webView, self.requestedURL == url else { return }
                DiagnosticsLogger.extensions.info("ExtensionOptionsView loading URL: \(url.absoluteString)")
                webView.load(URLRequest(url: url))
            }
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == ExtensionOptionsView.consoleHandlerName {
                DiagnosticsLogger.extensions.info("Options Console: \(String(describing: message.body))")
            }
        }

        func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            DiagnosticsLogger.extensions.info("Options page: Provisional navigation started.")
        }

        func webView(_: WKWebView, didCommit _: WKNavigation!) {
            DiagnosticsLogger.extensions.info("Options page: Navigation committed.")
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            DiagnosticsLogger.extensions.error("Options page navigation failed (Code \(nsError.code)): \(error.localizedDescription)")
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            DiagnosticsLogger.extensions.error("Options page load failed (Code \(nsError.code)): \(error.localizedDescription)")
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            DiagnosticsLogger.extensions.info("Options page loaded successfully.")
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // Options pages link out (homepage, docs, donations). The sheet has
            // no browser chrome, so send those to the default browser and keep
            // only the extension's own pages inside.
            if let url = navigationAction.request.url,
               navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme?.lowercased(),
               scheme == "https" || scheme == "http"
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            self.contentProcessRecoveryCount += 1
            DiagnosticsLogger.extensions.error("Options page content process terminated (recovery #\(self.contentProcessRecoveryCount))")
            guard self.contentProcessRecoveryCount <= 3, let url = self.requestedURL else { return }
            webView.load(URLRequest(url: url))
        }

        // MARK: WKUIDelegate

        // Options pages commonly use `confirm()` ("Reset all settings?") and
        // `alert()`; without a UI delegate WebKit answers them silently, so the
        // page never gets a "yes". Show real dialogs, attached to the sheet
        // when it has a window.

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "https" || scheme == "http"
            {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame _: WKFrameInfo,
            completionHandler: @escaping @MainActor () -> Void
        ) {
            let alert = Self.makeAlert(message: message)
            alert.addButton(withTitle: String(localized: "OK"))
            Self.present(alert, for: webView) { _ in completionHandler() }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame _: WKFrameInfo,
            completionHandler: @escaping @MainActor (Bool) -> Void
        ) {
            let alert = Self.makeAlert(message: message)
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            Self.present(alert, for: webView) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame _: WKFrameInfo,
            completionHandler: @escaping @MainActor (String?) -> Void
        ) {
            let alert = Self.makeAlert(message: prompt)
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            Self.present(alert, for: webView) { response in
                completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        }

        private static func makeAlert(message: String) -> NSAlert {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .informational
            return alert
        }

        private static func present(
            _ alert: NSAlert,
            for webView: WKWebView,
            completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void
        ) {
            if let window = webView.window {
                alert.beginSheetModal(for: window) { response in
                    completion(response)
                }
            } else {
                completion(alert.runModal())
            }
        }
    }
}
