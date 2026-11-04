import SwiftUI

// MARK: - YouTubeGridLayout

/// The video grid as youtube.com lays it out: cards of equal width with a 16 pt gutter and
/// 40 pt between rows. The number of columns follows the available width.
enum YouTubeGridLayout {
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 40

    static let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 440), spacing: columnSpacing, alignment: .top),
    ]
}
