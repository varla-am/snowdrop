import SwiftUI

/// Settings tab for themes and window transparency.
struct AppearanceSettingsView: View {
    @State private var settings = SettingsManager.shared

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        Form {
            Section(String(localized: "Theme")) {
                LazyVGrid(columns: self.columns, spacing: 12) {
                    ForEach(SnowdropTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, isSelected: self.settings.theme == theme) {
                            withAnimation(.smooth(duration: 0.3)) {
                                self.settings.theme = theme
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section(String(localized: "Window")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Transparency"))
                        Spacer()
                        Text("\(Int(self.settings.windowTransparency * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: self.$settings.windowTransparency, in: 0 ... 0.9)
                    Text(String(localized: "Lets your desktop show through the window, like a frosted glass."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(String(localized: "Blur what is behind the window"), isOn: self.$settings.windowBlurEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ThemeSwatch

private struct ThemeSwatch: View {
    let theme: SnowdropTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [self.theme.glow.0, self.theme.glow.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(self.theme.accent)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                            .padding(8)
                    }
                    .frame(height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(self.isSelected ? self.theme.accent : .clear, lineWidth: 2.5)
                    }
                    .scaleEffect(self.isSelected ? 1.04 : 1)

                Text(self.theme.displayName)
                    .font(.caption)
                    .fontWeight(self.isSelected ? .semibold : .regular)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.theme.displayName)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }
}
