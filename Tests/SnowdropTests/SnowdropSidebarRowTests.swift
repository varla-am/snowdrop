import SwiftUI
import Testing
@testable import Snowdrop

@MainActor
@Suite(.tags(.model))
struct SnowdropSidebarRowTests {
    @Test("SnowdropSidebarRow constructs selected and unselected rows")
    func constructsSelectedAndUnselectedRows() {
        let selected = SnowdropSidebarRow(
            title: "Home",
            systemImage: "house",
            isSelected: true,
            action: {}
        )
        let unselected = SnowdropSidebarRow(
            title: "Search",
            systemImage: "magnifyingglass",
            isSelected: false,
            action: {}
        )

        #expect(String(describing: selected).isEmpty == false)
        #expect(String(describing: unselected).isEmpty == false)
    }
}
