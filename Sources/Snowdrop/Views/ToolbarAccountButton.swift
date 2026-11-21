import SwiftUI

// MARK: - ToolbarAccountButton

/// The signed-in account's avatar in the window toolbar; opens the account switcher.
struct ToolbarAccountButton: View {
    @Environment(AccountService.self) private var accountService
    @Environment(AuthService.self) private var authService

    @State private var showingSwitcher = false

    private static let size: CGFloat = 26

    var body: some View {
        Button {
            if self.authService.state.isLoggedIn {
                self.showingSwitcher = true
            } else {
                self.authService.startLogin()
            }
        } label: {
            self.avatar
        }
        .buttonStyle(.plain)
        .help(self.helpText)
        .accessibilityLabel(self.helpText)
        .popover(isPresented: self.$showingSwitcher, arrowEdge: .bottom) {
            AccountSwitcherPopover()
                .environment(self.authService)
                .environment(self.accountService)
        }
    }

    private var helpText: String {
        if self.authService.hasPersonalAccount, let name = self.accountService.currentAccount?.name {
            return name
        }
        return self.authService.state.isLoggedIn
            ? String(localized: "Guest mode. Switch back to your account.")
            : String(localized: "Sign in")
    }

    @ViewBuilder
    private var avatar: some View {
        if self.authService.hasPersonalAccount, let url = self.accountService.currentAccount?.thumbnailURL {
            CachedAsyncImage(
                url: url,
                targetSize: CGSize(width: Self.size * 2, height: Self.size * 2)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                self.placeholder
            }
            .frame(width: Self.size, height: Self.size)
            .clipShape(.circle)
        } else {
            self.placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: Self.size))
            .foregroundStyle(.secondary)
            .frame(width: Self.size, height: Self.size)
    }
}
