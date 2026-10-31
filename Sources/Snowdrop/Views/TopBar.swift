import SwiftUI

// MARK: - TopBar

/// Floating bar above the content: section title, a glass search capsule and the account.
struct TopBar: View {
    let title: String
    let subtitle: String?
    let onSearch: () -> Void

    var body: some View {
        ZStack {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(self.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .contentTransition(.interpolate)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.searchCapsule

            HStack {
                Spacer()
                CompactProfileButton()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.3), value: self.title)
    }

    private var searchCapsule: some View {
        Button(action: self.onSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Search songs, albums, artists…"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(width: 340, height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .compatGlass(interactive: true, in: Capsule())
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel(String(localized: "Search"))
    }
}

// MARK: - CompactProfileButton

/// Round avatar that opens the account switcher; falls back to a sign-in button.
struct CompactProfileButton: View {
    @Environment(AccountService.self) private var accountService
    @Environment(AuthService.self) private var authService

    @State private var showingAccountSwitcher = false

    var body: some View {
        Button {
            if self.authService.state.isLoggedIn {
                self.showingAccountSwitcher = true
            } else {
                self.authService.startLogin()
            }
        } label: {
            self.avatar
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .compatGlass(interactive: true, in: Circle())
        .help(self.helpText)
        .accessibilityIdentifier(AccessibilityID.SidebarProfile.profileButton)
        .accessibilityLabel(self.helpText)
        .popover(isPresented: self.$showingAccountSwitcher, arrowEdge: .bottom) {
            AccountSwitcherPopover()
                .environment(self.authService)
                .environment(self.accountService)
        }
    }

    private var helpText: String {
        if let account = self.accountService.currentAccount, self.authService.hasPersonalAccount {
            return account.name
        }
        return self.authService.state.isLoggedIn
            ? String(localized: "Guest mode. Switch back to your account.")
            : String(localized: "Sign in for your library")
    }

    @ViewBuilder
    private var avatar: some View {
        if self.authService.hasPersonalAccount,
           let url = self.accountService.currentAccount?.thumbnailURL
        {
            CachedAsyncImage(url: url, targetSize: CGSize(width: 34, height: 34)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                self.placeholder
            }
            .clipShape(.circle)
            .padding(2)
        } else {
            self.placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
    }
}
