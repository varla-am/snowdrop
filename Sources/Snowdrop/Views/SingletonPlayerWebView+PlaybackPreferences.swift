import Foundation

// MARK: - SingletonPlayerWebView Media Controls

extension SingletonPlayerWebView {
    /// Updates the current page and the bootstrap state used by future page loads.
    func setMediaControlStyle(useNextPrev: Bool) {
        self.mediaControlUsesNextPrev = useNextPrev
        self.refreshInstalledUserScripts()

        guard let webView = self.webView else { return }
        let script = Self.mediaControlStyleSyncScript(useNextPrev: useNextPrev)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func mediaControlBootstrapScript() -> String {
        Self.mediaControlStyleBootstrapScript(useNextPrev: self.mediaControlUsesNextPrev)
    }

    /// Re-asserts Snowdrop's `nexttrack`/`previoustrack` media-session override immediately.
    ///
    /// The document-start `setActionHandler` wrapper keeps YouTube from overwriting
    /// Snowdrop-owned next/previous handlers, so normal operation relies on bounded
    /// event-driven refreshes instead of a steady animation-frame loop.
    func reassertMediaControlOverride() {
        guard self.mediaControlUsesNextPrev, let webView = self.webView else { return }
        webView.evaluateJavaScript(
            "if (typeof window.__snowdropRefreshMediaControlStyle === 'function') { window.__snowdropRefreshMediaControlStyle(); }",
            completionHandler: nil
        )
    }

    /// Performs a bounded re-assertion when the app enters the background.
    ///
    /// YouTube handler writes are blocked by the document-start wrapper while Snowdrop owns
    /// next/previous, so no steady background timer is needed.
    func beginBackgroundMediaControlReassertion() {
        guard self.mediaControlUsesNextPrev else { return }
        self.reassertMediaControlOverride()
        self.mediaControlReassertTimer?.invalidate()
        self.mediaControlReassertTimer = nil
    }

    /// Clears any legacy background re-assertion timer.
    func endBackgroundMediaControlReassertion() {
        self.mediaControlReassertTimer?.invalidate()
        self.mediaControlReassertTimer = nil
    }

    static func mediaControlStyleBootstrapScript(useNextPrev: Bool) -> String {
        let jsBoolean = useNextPrev ? "true" : "false"
        return """
            (function() {
                try {
                    localStorage.setItem('snowdropUseNextPrev', '\(jsBoolean)');
                } catch (e) {}
                window.__snowdropUseNextPrev = \(jsBoolean);
                // Wrap setActionHandler at document start so YouTube registrations cannot
                // steal remote-command ownership. Seek handlers always stay native-owned;
                // next/previous stay Snowdrop-owned in nextPrev mode unless Snowdrop is installing
                // its own handlers under the temporary install flag.
                try {
                    if (typeof window.__snowdropInstallingMediaControlHandlers !== 'boolean') {
                        window.__snowdropInstallingMediaControlHandlers = false;
                    }
                    var ms = navigator.mediaSession;
                    if (ms && !ms.__snowdropSetActionHandlerWrapped) {
                        var orig = ms.setActionHandler.bind(ms);
                        ms.setActionHandler = function(type, handler) {
                            var isSeekSkip = type === 'seekforward' || type === 'seekbackward';
                            var isNextPrevious = type === 'nexttrack' || type === 'previoustrack';
                            if (isSeekSkip) {
                                return orig(type, null);
                            }
                            if (isNextPrevious) {
                                if (window.__snowdropUseNextPrev) {
                                    if (!window.__snowdropInstallingMediaControlHandlers) {
                                        return undefined;
                                    }
                                } else {
                                    return orig(type, null);
                                }
                            }
                            return orig(type, handler);
                        };
                        ms.__snowdropSetActionHandlerWrapped = true;
                    }
                } catch (e) {}
            })();
        """
    }

    static func mediaControlStyleSyncScript(useNextPrev: Bool) -> String {
        let jsBoolean = useNextPrev ? "true" : "false"
        let clearWebViewSkipHandlers = if useNextPrev {
            ""
        } else {
            """
                try {
                    var ms = navigator.mediaSession;
                    ms.setActionHandler('nexttrack', null);
                    ms.setActionHandler('previoustrack', null);
                    ms.setActionHandler('seekforward', null);
                    ms.setActionHandler('seekbackward', null);
                } catch (e) {}
            """
        }

        return """
            (function() {
                try {
                    localStorage.setItem('snowdropUseNextPrev', '\(jsBoolean)');
                } catch (e) {}
                window.__snowdropUseNextPrev = \(jsBoolean);
                if (typeof window.__snowdropRefreshMediaControlStyle === 'function') {
                    window.__snowdropRefreshMediaControlStyle();
                }
                \(clearWebViewSkipHandlers)
            })();
        """
    }

    static var mediaControlOverrideScript: String {
        """
        (function() {
            \(eventTimestampFunctionJS)
            const observerEpoch = (window.performance && performance.timeOrigin)
                ? performance.timeOrigin : Date.now();
            const documentID = Number(window.__snowdropDocumentID || 0);
            if (typeof window.__snowdropUseNextPrev !== 'boolean') {
                try {
                    window.__snowdropUseNextPrev =
                        localStorage.getItem('snowdropUseNextPrev') === 'true';
                } catch (e) {
                    window.__snowdropUseNextPrev = false;
                }
            }

            function withSnowdropMediaControlInstall(action) {
                var previousFlag = window.__snowdropInstallingMediaControlHandlers === true;
                window.__snowdropInstallingMediaControlHandlers = true;
                try {
                    action();
                } finally {
                    window.__snowdropInstallingMediaControlHandlers = previousFlag;
                }
            }

            function applyOverride() {
                if (!window.__snowdropUseNextPrev) {
                    return;
                }
                try {
                    var ms = navigator.mediaSession;
                    withSnowdropMediaControlInstall(function() {
                        ms.setActionHandler('seekforward', null);
                        ms.setActionHandler('seekbackward', null);
                        ms.setActionHandler('nexttrack', function() {
                            window.webkit.messageHandlers.singletonPlayer
                                .postMessage({
                                    type: 'REMOTE_NEXT',
                                    documentGeneration: window.__snowdropDocumentGeneration,
                                    commandIssuedAtMilliseconds: __snowdropEventTimestampMilliseconds(),
                                    observerEpoch: observerEpoch,
                                    documentID: documentID
                                });
                        });
                        ms.setActionHandler('previoustrack', function() {
                            window.webkit.messageHandlers.singletonPlayer
                                .postMessage({
                                    type: 'REMOTE_PREVIOUS',
                                    documentGeneration: window.__snowdropDocumentGeneration,
                                    commandIssuedAtMilliseconds: __snowdropEventTimestampMilliseconds(),
                                    observerEpoch: observerEpoch,
                                    documentID: documentID
                                });
                        });
                    });
                } catch (e) {}
            }

            window.__snowdropRefreshMediaControlStyle = function() {
                applyOverride();
            };

            window.__snowdropRefreshMediaControlStyle();

            // Re-apply on bounded page lifecycle events where YouTube recreates the player.
            function attachVideoOverride() {
                var v = document.querySelector('video');
                if (!v || v.__snowdropOverrideAttached) return;
                v.__snowdropOverrideAttached = true;
                ['playing','loadedmetadata','loadeddata','canplay','seeked']
                    .forEach(function(e) { v.addEventListener(e, applyOverride); });
                applyOverride();
            }

            attachVideoOverride();
            new MutationObserver(attachVideoOverride)
                .observe(document.documentElement, {childList:true, subtree:true});
        })();
        """
    }

    // MARK: - Playback Audio Quality

    /// Updates the current page and the bootstrap state used by future page loads.
    func setPlaybackAudioQuality(_ quality: SettingsManager.PlaybackAudioQuality) {
        self.playbackAudioQuality = quality
        self.refreshInstalledUserScripts()

        guard let webView = self.webView else { return }
        let script = Self.playbackAudioQualitySyncScript(quality: quality)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func playbackAudioQualityBootstrapScript() -> String {
        Self.playbackAudioQualityBootstrapScript(quality: self.playbackAudioQuality)
    }
}
