import Foundation
import Testing
@testable import Snowdrop

@Suite("YouTube subtitle style")
struct YouTubeSubtitleStyleTests {
    @Test("Japanese caption track codes are recognised")
    func detectsJapaneseTracks() {
        #expect(YouTubeSubtitleStyle.isJapanese(trackCode: "ja"))
        #expect(YouTubeSubtitleStyle.isJapanese(trackCode: ".ja"))
        #expect(YouTubeSubtitleStyle.isJapanese(trackCode: "a.ja"))
        #expect(YouTubeSubtitleStyle.isJapanese(trackCode: "ja-JP"))
        #expect(!YouTubeSubtitleStyle.isJapanese(trackCode: "en"))
        #expect(!YouTubeSubtitleStyle.isJapanese(trackCode: ".en"))
        #expect(!YouTubeSubtitleStyle.isJapanese(trackCode: "jv"))
    }

    @Test("Kana and kanji come out as Japanese readings")
    func romanizesJapanese() {
        #expect(SubtitleRomanizer.romanize("こんにちは") == "konnichiwa")
        #expect(SubtitleRomanizer.romanize("夜に駆ける") == "yoru ni kakeru")
        #expect(SubtitleRomanizer.romanize("君の名は。") == "kimi no na wa.")
    }

    @Test("Latin words, digits and line breaks are kept")
    func keepsLatinText() {
        #expect(SubtitleRomanizer.romanize("Hello 2026") == "Hello 2026")
        #expect(SubtitleRomanizer.romanize("ありがとう\nHello") == "arigatou\nHello")
    }

    @Test("The page config is valid JSON with the three settings")
    @MainActor
    func configJSON() throws {
        let data = try #require(YouTubeSubtitleStyle.shared.pageConfigJSON.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["scale"] is Double)
        #expect(object["lines"] is Int)
        #expect(object["latin"] is Bool)
    }
}
