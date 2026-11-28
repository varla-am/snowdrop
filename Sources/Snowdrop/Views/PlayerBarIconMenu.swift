import SwiftUI

// MARK: - PlayerBarIconMenu

struct PlayerBarIconMenu<MenuContent: View, Icon: View>: View {
    var isSelected = false
    var accessibilityID: String?
    var accessibilityLabel: String?
    @ViewBuilder var menuContent: () -> MenuContent
    @ViewBuilder var icon: () -> Icon

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        // The visible icon is the menu's own label, so the click lands on the menu
        // itself (an invisible overlay label stopped receiving clicks on newer macOS).
        Menu {
            self.menuContent()
        } label: {
            self.icon()
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.backgroundColor)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .playerBarMenuAccessibilityIdentifier(self.accessibilityID)
        .playerBarMenuAccessibilityLabel(self.accessibilityLabel)
        .frame(width: 28, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(self.isEnabled ? 1 : 0.38)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        let baseColor: Color = self.colorScheme == .dark ? .white : .black
        if self.isHovering, self.isEnabled {
            return baseColor.opacity(0.08)
        }
        if self.isSelected {
            return baseColor.opacity(0.06)
        }
        return .clear
    }
}

// MARK: - Accessibility Helpers

private extension View {
    @ViewBuilder
    func playerBarMenuAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            self.accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    @ViewBuilder
    func playerBarMenuAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }
    }
}
