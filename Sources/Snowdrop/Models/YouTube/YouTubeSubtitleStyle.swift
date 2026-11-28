import Foundation

// MARK: - YouTubeSubtitleStyle

/// How Snowdrop draws subtitles on top of the video: size, number of lines and the
/// "Japanese (Latin)" reading mode. The page renders them (see
/// `YouTubeWatchWebView+Subtitles`), this object only holds the choices.
@MainActor
@Observable
final class YouTubeSubtitleStyle {
    static let shared = YouTubeSubtitleStyle()

    struct SizeOption: Identifiable, Hashable {
        let scale: Double
        let name: String
        var id: Double {
            self.scale
        }
    }

    static var sizeOptions: [SizeOption] {
        [
            SizeOption(scale: 0.75, name: String(localized: "Small")),
            SizeOption(scale: 1.0, name: String(localized: "Medium")),
            SizeOption(scale: 1.35, name: String(localized: "Large")),
            SizeOption(scale: 1.8, name: String(localized: "Extra large")),
        ]
    }

    static let lineOptions = [1, 2, 3, 4]

    private enum Keys {
        static let scale = "youtube.subtitles.scale"
        static let lines = "youtube.subtitles.lines"
        static let latin = "youtube.subtitles.japaneseLatin"
    }

    /// Text size multiplier (1 = medium).
    var scale: Double {
        didSet {
            UserDefaults.standard.set(self.scale, forKey: Keys.scale)
            self.pushToPage()
        }
    }

    /// How many lines may be on screen at once (the newest, with older ones dimmed).
    var lines: Int {
        didSet {
            UserDefaults.standard.set(self.lines, forKey: Keys.lines)
            self.pushToPage()
        }
    }

    /// Show Japanese subtitles in Latin letters (romaji).
    var japaneseLatin: Bool {
        didSet {
            UserDefaults.standard.set(self.japaneseLatin, forKey: Keys.latin)
            self.pushToPage()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        let savedScale = defaults.double(forKey: Keys.scale)
        self.scale = savedScale > 0 ? min(max(savedScale, 0.5), 3) : 1
        let savedLines = defaults.integer(forKey: Keys.lines)
        self.lines = Self.lineOptions.contains(savedLines) ? savedLines : 2
        self.japaneseLatin = defaults.bool(forKey: Keys.latin)
    }

    /// The settings as a JSON object literal for the page script.
    var pageConfigJSON: String {
        let object: [String: Any] = ["scale": self.scale, "lines": self.lines, "latin": self.japaneseLatin]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "{\"scale\":1,\"lines\":2,\"latin\":false}" }
        return text
    }

    private func pushToPage() {
        YouTubeWatchWebView.shared.applySubtitleStyle()
    }

    /// Whether a caption track code (`ja`, `.ja`, `a.ja`, `ja-JP`) is Japanese.
    nonisolated static func isJapanese(trackCode code: String) -> Bool {
        let lower = code.lowercased()
        let language = lower.split(separator: ".").last.map(String.init) ?? lower
        return language == "ja" || language.hasPrefix("ja-")
    }
}

// MARK: - SubtitleRomanizer

/// Subtitle-flavoured romaji (the lyrics one keeps punctuation as is): turns Japanese into Latin letters using the system's Japanese readings, so kanji
/// get their Japanese pronunciation (not the Chinese one). Text that is not Japanese
/// (English words, numbers) stays as it is.
enum SubtitleRomanizer {
    static func romanize(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { Self.romanizeLine($0) }
            .joined(separator: "\n")
    }

    private static func romanizeLine(_ line: String) -> String {
        let nsLine = line as NSString
        guard nsLine.length > 0 else { return line }
        let tokenizer = CFStringTokenizerCreate(
            nil,
            line as CFString,
            CFRangeMake(0, nsLine.length),
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja") as CFLocale
        )

        var output = ""
        var cursor = 0
        var previousWasWord = false

        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > cursor {
                // Gap between tokens: spaces and punctuation the tokenizer skipped.
                output += Self.punctuation(nsLine.substring(with: NSRange(location: cursor, length: range.location - cursor)))
                previousWasWord = false
            }
            let original = nsLine.substring(with: NSRange(location: range.location, length: range.length))
            var piece = original
            if Self.containsJapanese(original) {
                switch original {
                case "は": piece = "wa"
                case "を": piece = "o"
                case "へ": piece = "e"
                default:
                    if let reading = CFStringTokenizerCopyCurrentTokenAttribute(
                        tokenizer,
                        kCFStringTokenizerAttributeLatinTranscription
                    ) as? String {
                        piece = Self.fixReading(reading)
                    }
                }
            } else {
                piece = Self.punctuation(original)
            }
            let isWord = piece.first?.isLetter == true || piece.first?.isNumber == true
            if previousWasWord, isWord { output += " " }
            output += piece
            previousWasWord = isWord
            cursor = range.location + range.length
        }
        if cursor < nsLine.length {
            output += Self.punctuation(nsLine.substring(from: cursor))
        }
        return output
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Hepburn tidy-ups the system reading doesn't do: "kon'nichiha" -> "konnichiwa".
    private static func fixReading(_ reading: String) -> String {
        var text = reading
        for (from, to) in [("kon'nichiha", "konnichiwa"), ("konbanha", "konbanwa"), ("n'n", "nn")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }

    /// Japanese and half-width punctuation to its Latin form.
    private static func punctuation(_ text: String) -> String {
        var result = ""
        for char in text {
            switch char {
            case "、", "､": result += ", "
            case "。", "｡": result += ". "
            case "「", "｢", "『": result += "\""
            case "」", "｣", "』": result += "\""
            case "・", "･": result += " "
            case "！": result += "!"
            case "？": result += "?"
            case "～", "〜": result += "~"
            case "　": result += " "
            default: result.append(char)
            }
        }
        return result
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xFF66 ... 0xFF9F: true
            default: false
            }
        }
    }
}
