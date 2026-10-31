import Testing
@testable import Snowdrop

@Suite("YouTube interstitial script contracts", .tags(.service))
@MainActor
struct YouTubeInterstitialScriptContractTests {
    @Test("Reveal matches the blackout and extraction contracts")
    func interstitialRevealContract() {
        let reveal = YouTubeWatchWebView.revealInterstitialScript
        let blackout = YouTubeWatchWebView.blackoutScript
        let extraction = YouTubeWatchWebView.extractionScript

        #expect(blackout.contains("style.id = 'snowdrop-yt-blackout'"))
        #expect(extraction.contains("const styleId = 'snowdrop-yt-video-style'"))
        #expect(extraction.contains("window.__snowdropStopYTExtraction = stopExtraction"))
        #expect(reveal.contains("typeof window.__snowdropStopYTExtraction === 'function'"))
        #expect(reveal.contains("'snowdrop-yt-blackout', 'snowdrop-yt-video-style'"))
    }
}
