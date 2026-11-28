import WebKit

// MARK: - Snowdrop subtitles

extension YouTubeWatchWebView {
    /// Name of the page-to-app channel that turns Japanese text into Latin letters.
    static let subtitleBridgeName = "snowdropSubtitles"

    /// Pushes the current size / lines / Latin choices into the page.
    func applySubtitleStyle() {
        let json = YouTubeSubtitleStyle.shared.pageConfigJSON
        self.webView?.evaluateJavaScript(
            "window.__snowdropCC && window.__snowdropCC.configure(\(json));",
            completionHandler: nil
        )
    }

    /// Draws YouTube's own caption text again in Snowdrop's style.
    ///
    /// The player still loads and times the captions (so every track, auto-generated
    /// ones and translations work, with no extra request); this script reads the text it
    /// puts on screen, hides that, and shows its own light-blue translucent bubble.
    static func subtitleScript(configJSON: String) -> String {
        Self.subtitleScriptSource.replacingOccurrences(of: "__CONFIG__", with: configJSON)
    }

    private static let subtitleScriptSource = #"""
    (function() {
        'use strict';
        if (window.__snowdropCC) { return; }

        var config = __CONFIG__;
        var handlers = window.webkit && window.webkit.messageHandlers;
        var bridge = handlers && handlers.snowdropSubtitles;
        var box = null;
        var shown = [];
        var currentCount = 0;
        var lastRaw = null;
        var sequence = 0;
        var clearTimer = null;
        var scheduled = false;
        var observer = null;
        var observedPlayer = null;

        var CSS = [
            '#snowdrop-cc {',
            '  position: fixed; left: 50%; bottom: 7%; transform: translateX(-50%);',
            '  max-width: min(88vw, 1400px); width: max-content; display: none;',
            '  z-index: 2147483647; pointer-events: none; text-align: center;',
            '  box-sizing: border-box; padding: 0.42em 1.05em;',
            '  font: 500 calc(min(2.7vw, 4.8vh) * var(--cc-scale, 1)) / 1.38 -apple-system, "SF Pro Text", "Hiragino Sans", sans-serif;',
            '  color: #fff; letter-spacing: 0.005em;',
            '  background: rgba(64, 162, 255, 0.62);',
            '  -webkit-backdrop-filter: blur(16px) saturate(1.5); backdrop-filter: blur(16px) saturate(1.5);',
            '  border: 1px solid rgba(255, 255, 255, 0.30);',
            '  border-radius: 1.05em;',
            '  box-shadow: 0 8px 28px rgba(8, 58, 140, 0.38), inset 0 1px 0 rgba(255, 255, 255, 0.28);',
            '  text-shadow: 0 1px 2px rgba(0, 40, 110, 0.5);',
            '}',
            '#snowdrop-cc .cc-line { transition: opacity 0.25s ease; }',
            '#snowdrop-cc .cc-line.old { opacity: 0.58; }'
        ].join('\n');

        function ensureBox() {
            if (box && box.isConnected) { return box; }
            if (!document.getElementById('snowdrop-cc-style')) {
                var style = document.createElement('style');
                style.id = 'snowdrop-cc-style';
                style.textContent = CSS;
                (document.head || document.documentElement).appendChild(style);
            }
            box = document.createElement('div');
            box.id = 'snowdrop-cc';
            box.setAttribute('aria-hidden', 'true');
            document.documentElement.appendChild(box);
            box.style.setProperty('--cc-scale', String(config.scale || 1));
            return box;
        }

        function render() {
            var element = ensureBox();
            element.textContent = '';
            if (!shown.length) { element.style.display = 'none'; return; }
            var firstCurrent = shown.length - currentCount;
            shown.forEach(function(line, index) {
                var row = document.createElement('div');
                row.className = 'cc-line' + (index < firstCurrent ? ' old' : '');
                row.textContent = line;
                element.appendChild(row);
            });
            element.style.display = 'block';
        }

        function splitLines(text) {
            if (!text) { return []; }
            return text.split(/\n+/).map(function(line) { return line.trim(); }).filter(Boolean);
        }

        function update(lines) {
            if (!lines.length) {
                // Keep the last words for a moment, then let the bubble go.
                if (!clearTimer) {
                    clearTimer = setTimeout(function() {
                        clearTimer = null; shown = []; currentCount = 0; render();
                    }, 2500);
                }
                return;
            }
            if (clearTimer) { clearTimeout(clearTimer); clearTimer = null; }
            var older = shown.filter(function(line) { return lines.indexOf(line) === -1; });
            shown = older.concat(lines).slice(-Math.max(1, config.lines || 2));
            currentCount = Math.min(lines.length, shown.length);
            render();
        }

        function readNative() {
            var windows = document.querySelectorAll('.ytp-caption-window-container .caption-window');
            var parts = [];
            windows.forEach(function(win) {
                var text = (win.innerText || win.textContent || '').replace(/ /g, ' ').trim();
                if (text) { parts.push(text); }
            });
            return parts.join('\n');
        }

        function check() {
            scheduled = false;
            var raw = readNative();
            if (raw === lastRaw) { return; }
            lastRaw = raw;
            var mine = ++sequence;
            if (config.latin && raw && bridge && bridge.postMessage) {
                bridge.postMessage(raw).then(function(reply) {
                    if (mine === sequence) { update(splitLines(typeof reply === 'string' && reply ? reply : raw)); }
                }).catch(function() {
                    if (mine === sequence) { update(splitLines(raw)); }
                });
            } else {
                update(splitLines(raw));
            }
        }

        function schedule() {
            if (scheduled) { return; }
            scheduled = true;
            requestAnimationFrame(check);
        }

        function attach() {
            var player = document.getElementById('movie_player');
            if (!player) { return; }
            if (observedPlayer === player) { return; }
            if (observer) { observer.disconnect(); }
            observedPlayer = player;
            observer = new MutationObserver(function(mutations) {
                // The player changes every frame (time, progress); only caption changes matter.
                for (var i = 0; i < mutations.length; i++) {
                    var node = mutations[i].target;
                    var element = node && node.nodeType === 1 ? node : (node && node.parentElement);
                    if (element && element.closest && element.closest('.ytp-caption-window-container')) { schedule(); return; }
                    var added = mutations[i].addedNodes;
                    for (var j = 0; j < added.length; j++) {
                        var n = added[j];
                        if (n.nodeType === 1 && n.classList && (n.classList.contains('ytp-caption-window-container') || n.classList.contains('caption-window'))) { schedule(); return; }
                    }
                }
            });
            observer.observe(player, { childList: true, subtree: true, characterData: true });
            schedule();
        }

        window.__snowdropCC = {
            configure: function(next) {
                var relayout = next.latin !== config.latin || next.lines !== config.lines;
                for (var key in next) { config[key] = next[key]; }
                ensureBox().style.setProperty('--cc-scale', String(config.scale || 1));
                if (relayout) { lastRaw = null; shown = []; currentCount = 0; schedule(); } else { render(); }
            }
        };

        attach();
        // The player can be replaced when YouTube swaps pages; look again now and then.
        setInterval(attach, 1000);
    })();
    """#
}

// MARK: - YouTubeSubtitleBridge

/// Answers the page's "write this Japanese in Latin letters" requests.
@MainActor
final class YouTubeSubtitleBridge: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard YouTubeWatchWebView.acceptsBridgeSource(
            isMainFrame: message.frameInfo.isMainFrame,
            sourceScheme: message.frameInfo.securityOrigin.protocol,
            sourceHost: message.frameInfo.securityOrigin.host
        ),
            let text = message.body as? String
        else {
            replyHandler(nil, "rejected")
            return
        }
        replyHandler(SubtitleRomanizer.romanize(String(text.prefix(2000))), nil)
    }
}
