import SwiftUI

/// Sidebar navigation for the main window, styled like Apple Music.
struct Sidebar: View {
    private enum SidebarSelection: Hashable {
        case navigation(NavigationItem)
        case pinned(SidebarPinnedItem)
    }

    @Binding var selection: NavigationItem?
    @Binding var pinnedSelection: SidebarPinnedItem?
    let client: any YTMusicClientProtocol
    var onReselectNavigationItem: ((NavigationItem) -> Void)?
    var onReselectPinnedItem: ((SidebarPinnedItem) -> Void)?
    @Environment(AuthService.self) private var authService
    @Environment(PlayerService.self) private var playerService
    @Environment(SidebarPinnedItemsManager.self) private var sidebarPinnedItemsManager
    @Environment(PodcastsAvailabilityService.self) private var podcastsAvailability
    @State private var isCreatingPlaylist = false

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 8) {
            // Room for the traffic lights, which float over the rail.
            Color.clear.frame(height: 26)

            Image(systemName: "snowflake")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(height: 28)
                .accessibilityHidden(true)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    self.railItem(.home, id: AccessibilityID.Sidebar.homeItem)
                    self.railItem(.explore, id: AccessibilityID.Sidebar.exploreItem)
                    self.railItem(.charts, id: AccessibilityID.Sidebar.chartsItem)
                    self.railItem(.moodsAndGenres, id: AccessibilityID.Sidebar.moodsAndGenresItem)
                    self.railItem(.newReleases, id: AccessibilityID.Sidebar.newReleasesItem)
                    if self.podcastsAvailability.availability != .unavailable {
                        self.railItem(.podcasts, id: AccessibilityID.Sidebar.podcastsItem)
                    }

                    if self.hasPersonalAccount {
                        self.railDivider
                        self.railItem(.library, id: AccessibilityID.Sidebar.libraryItem)
                        self.railItem(.likedMusic, id: AccessibilityID.Sidebar.likedMusicItem)
                        self.railItem(.history, id: AccessibilityID.Sidebar.historyItem)

                        self.railDivider
                        ForEach(self.sidebarPinnedItemsManager.items) { item in
                            self.sidebarPinnedRow(item)
                        }
                        self.createPlaylistButton
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 10)
        .padding(.horizontal, 7)
        .frame(width: 58)
        .frame(maxHeight: .infinity)
        .compatGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Sidebar.container)
    }

    private var railDivider: some View {
        Capsule()
            .fill(.primary.opacity(0.14))
            .frame(width: 22, height: 2)
            .padding(.vertical, 4)
    }

    private func railItem(_ item: NavigationItem, id: String) -> some View {
        RailButton(
            title: item.displayName,
            systemImage: item.icon,
            isSelected: self.currentSidebarSelection == .navigation(item),
            namespace: self.selectionNamespace
        ) {
            self.selectNavigationItem(item)
        }
        .accessibilityIdentifier(id)
    }

    private var createPlaylistButton: some View {
        Button {
            self.presentCreatePlaylistDialog()
        } label: {
            ZStack {
                if self.isCreatingPlaylist {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Create Playlist"))
        .accessibilityLabel(String(localized: "Create Playlist"))
    }

    private var hasPersonalAccount: Bool {
        self.authService.hasPersonalAccount
    }

    private var currentSidebarSelection: SidebarSelection? {
        if let pinnedSelection {
            return .pinned(pinnedSelection)
        }

        if let selection {
            return .navigation(selection)
        }

        return nil
    }

    private func selectNavigationItem(_ item: NavigationItem) {
        let newSelection = SidebarSelection.navigation(item)
        if self.currentSidebarSelection == newSelection {
            self.onReselectNavigationItem?(item)
            HapticService.navigation()
            return
        }
        self.selection = item
        self.pinnedSelection = nil
        HapticService.navigation()
    }

    private func selectPinnedItem(_ item: SidebarPinnedItem) {
        let newSelection = SidebarSelection.pinned(item)
        if self.currentSidebarSelection == newSelection {
            self.onReselectPinnedItem?(item)
            HapticService.navigation()
            return
        }
        self.selection = nil
        self.pinnedSelection = item
        HapticService.navigation()
    }

    private func presentCreatePlaylistDialog() {
        guard !self.isCreatingPlaylist else { return }
        let owner = self.playerService.currentAccountMutationOwner

        SongActionsHelper.presentCreatePlaylistDialog(
            informativeText: "Create a new playlist.",
            request: SongActionsHelper.PlaylistCreationRequest(
                client: self.client,
                videoIds: [],
                whileValid: { self.playerService.acceptsAccountMutationOwner(owner) }
            ),
            onWillCreate: {
                guard !self.isCreatingPlaylist else { return false }
                self.isCreatingPlaylist = true
                return true
            },
            completion: { result in
                self.isCreatingPlaylist = false
                guard self.playerService.acceptsAccountMutationOwner(owner) else { return }

                switch result {
                case let .success(playlist):
                    let pinnedItem = SidebarPinnedItem.from(playlist)
                    self.sidebarPinnedItemsManager.add(pinnedItem)
                    self.selectPinnedItem(pinnedItem)
                case let .failure(failure):
                    SongActionsHelper.presentPlaylistCreationError(failure)
                }
            }
        )
    }

    private func sidebarPinnedRow(_ item: SidebarPinnedItem) -> some View {
        RailButton(
            title: item.title,
            systemImage: item.systemImage,
            isSelected: self.currentSidebarSelection == .pinned(item),
            namespace: self.selectionNamespace
        ) {
            self.selectPinnedItem(item)
        }
        .contextMenu {
            Button {
                self.sidebarPinnedItemsManager.moveUp(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move Up"), systemImage: "chevron.up")
            }

            Button {
                self.sidebarPinnedItemsManager.moveDown(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move Down"), systemImage: "chevron.down")
            }

            Button {
                self.sidebarPinnedItemsManager.moveToTop(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move to Top"), systemImage: "arrow.up.to.line")
            }

            Button {
                self.sidebarPinnedItemsManager.moveToEnd(contentId: item.contentId)
            } label: {
                Label(String(localized: "Move to End"), systemImage: "arrow.down.to.line")
            }

            Divider()

            Button(role: .destructive) {
                if self.pinnedSelection?.contentId == item.contentId {
                    self.pinnedSelection = nil
                }
                self.sidebarPinnedItemsManager.remove(contentId: item.contentId)
            } label: {
                Label(String(localized: "Remove from Sidebar"), systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    Sidebar(selection: .constant(.home), pinnedSelection: .constant(nil), client: client)
        .frame(width: 220)
        .environment(authService)
        .environment(PlayerService())
        .environment(SidebarPinnedItemsManager(skipLoad: true))
        .environment(PodcastsAvailabilityService())
}


// MARK: - RailButton

/// One icon in the rail. The selection is a glass pill that slides between items.
private struct RailButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: self.action) {
            ZStack {
                if self.isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.tint.opacity(0.30))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
                        )
                        .matchedGeometryEffect(id: "railSelection", in: self.namespace)
                } else if self.isHovering {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.primary.opacity(0.08))
                }

                Image(systemName: self.systemImage)
                    .font(.system(size: 16, weight: self.isSelected ? .semibold : .regular))
                    .foregroundStyle(self.isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.75)))
                    .scaleEffect(self.isHovering ? 1.12 : 1)
            }
            .frame(width: 42, height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(self.title)
        .accessibilityLabel(self.title)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { self.isHovering = hovering }
        }
        .animation(.smooth(duration: 0.28), value: self.isSelected)
    }
}
