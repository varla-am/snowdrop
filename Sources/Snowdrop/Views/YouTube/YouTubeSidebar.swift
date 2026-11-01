import SwiftUI

// MARK: - YouTubeSidebar

/// Icon rail for the YouTube (video) experience, the twin of the music `Sidebar`:
/// a floating glass column of buttons with a sliding selection pill.
struct YouTubeSidebar: View {
    @Binding var selection: YouTubeNavigationItem?
    var onReselect: ((YouTubeNavigationItem) -> Void)?
    @Environment(AuthService.self) private var authService
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 8) {
            // Room for the traffic lights, which float over the rail.
            Color.clear.frame(height: 26)

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(height: 28)
                .accessibilityHidden(true)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    self.railItem(.search)
                    self.railItem(.home)
                    self.railItem(.shorts)
                    self.railItem(.explore)

                    if self.hasPersonalAccount {
                        self.railItem(.subscriptions)

                        self.railDivider
                        self.railItem(.likedVideos)
                        self.railItem(.watchLater)
                        self.railItem(.playlists)
                        self.railItem(.history)
                    }
                }
                .padding(.vertical, 2)
            }

            self.musicSwitchButton
        }
        .padding(.bottom, 10)
        .padding(.horizontal, 7)
        .frame(width: 58)
        .frame(maxHeight: .infinity)
        .compatGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.container)
    }

    private var hasPersonalAccount: Bool {
        self.authService.hasPersonalAccount
    }

    private var railDivider: some View {
        Capsule()
            .fill(.primary.opacity(0.14))
            .frame(width: 22, height: 2)
            .padding(.vertical, 4)
    }

    private func railItem(_ item: YouTubeNavigationItem) -> some View {
        RailButton(
            title: item.displayName,
            systemImage: item.icon,
            isSelected: self.selection == item,
            namespace: self.selectionNamespace
        ) {
            self.select(item)
        }
        .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.item(for: item))
    }

    /// Flips the whole app back to YouTube Music.
    private var musicSwitchButton: some View {
        Button {
            // Pause a docked video in place; don't hand it to the pop-out window.
            self.youtubePlayer.prepareForSourceSwitch()
            withAnimation(.easeInOut(duration: 0.2)) {
                SettingsManager.shared.appSource = .music
            }
            HapticService.navigation()
        } label: {
            Image(systemName: AppSource.music.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Switch to YouTube Music"))
        .accessibilityLabel(String(localized: "Switch to YouTube Music"))
        .accessibilityIdentifier(AccessibilityID.SourceToggle.segment(for: .music))
    }

    private func select(_ item: YouTubeNavigationItem) {
        if self.selection == item {
            self.onReselect?(item)
            HapticService.navigation()
            return
        }
        self.selection = item
        HapticService.navigation()
    }
}

// MARK: - AccessibilityID.YouTubeSidebar

extension AccessibilityID {
    enum YouTubeSidebar {
        static let container = "youtubeSidebar"

        static func item(for item: YouTubeNavigationItem) -> String {
            "youtubeSidebar.\(item.rawValue)"
        }
    }
}

#Preview {
    YouTubeSidebar(selection: .constant(.home))
        .frame(width: 80)
        .environment(AuthService())
        .environment(YouTubePlayerService())
}
