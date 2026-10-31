import AppKit
import SwiftUI

// MARK: - WindowBackdrop

/// Backdrop behind the whole main window: a themed glow over a blur of whatever
/// is behind the window. `transparency` runs from 0 (solid) to 1 (clear glass).
struct WindowBackdrop: View {
    let theme: SnowdropTheme
    let transparency: Double
    let blurEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if self.blurEnabled {
                if #available(macOS 26.0, *) {
                    // Frost first, so windows behind this one stay unreadable and the
                    // cards on top stay legible; then real Liquid Glass over it.
                    BehindWindowBlur()
                        .opacity(0.35 + 0.5 * self.transparency)
                    WindowGlass(
                        tint: NSColor(self.theme.glow.0),
                        tintAlpha: 0.10 + 0.30 * (1 - self.transparency),
                        isClear: self.transparency > 0.8
                    )
                } else {
                    BehindWindowBlur()
                }
            }

            // Solid base that fades away as transparency rises.
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .opacity(1 - self.transparency)

            // Themed glow stays visible even when the base is clear.
            LinearGradient(
                colors: [self.theme.glow.0, self.theme.glow.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(self.theme.glowOpacity * (self.colorScheme == .dark ? 1 : 0.55))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - WindowGlass

/// A full-window Liquid Glass layer (macOS 26+).
@available(macOS 26.0, *)
private struct WindowGlass: NSViewRepresentable {
    let tint: NSColor
    let tintAlpha: Double
    let isClear: Bool

    func makeNSView(context _: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = 0
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context _: Context) {
        view.style = self.isClear ? .clear : .regular
        view.tintColor = self.tint.withAlphaComponent(self.tintAlpha)
    }
}

// MARK: - BehindWindowBlur

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

// MARK: - WindowTransparencyConfigurator

/// Lets the window show through: a window with an opaque background would hide
/// the backdrop no matter how transparent the SwiftUI layers are.
private struct WindowTransparencyConfigurator: NSViewRepresentable {
    let isTransparent: Bool
    let chromeless: Bool

    func makeNSView(context _: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.isTransparent = self.isTransparent
        view.chromeless = self.chromeless
        return view
    }

    func updateNSView(_ view: ConfiguratorView, context _: Context) {
        view.isTransparent = self.isTransparent
        view.chromeless = self.chromeless
        view.apply()
    }

    final class ConfiguratorView: NSView {
        var isTransparent = false
        var chromeless = true
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.observers.forEach(NotificationCenter.default.removeObserver)
            self.observers = []
            guard let window = self.window else { return }
            self.apply()
            // SwiftUI resets some window chrome when it updates the scene, so
            // apply again when the window comes forward and shortly after launch.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didExitFullScreenNotification] {
                self.observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            for delay in [0.25, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
            }
        }

        func apply() {
            guard let window = self.window else { return }
            window.isOpaque = !self.isTransparent
            window.backgroundColor = self.isTransparent ? .clear : .windowBackgroundColor
            if self.chromeless {
                // Title text and bar chrome would fight the floating top bar.
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}

// MARK: - SnowdropWindowStyle

private struct SnowdropWindowStyle: ViewModifier {
    let chromeless: Bool
    @State private var settings = SettingsManager.shared

    func body(content: Content) -> some View {
        content
            .background {
                WindowBackdrop(
                    theme: self.settings.theme,
                    transparency: self.settings.windowTransparency,
                    blurEnabled: self.settings.windowBlurEnabled
                )
            }
            .background(WindowTransparencyConfigurator(isTransparent: self.settings.windowTransparency > 0, chromeless: self.chromeless))
            .tint(self.settings.theme.accent)
    }
}

extension View {
    /// Applies the themed, optionally see-through window backdrop and accent.
    func snowdropWindowStyle(chromeless: Bool = true) -> some View {
        self.modifier(SnowdropWindowStyle(chromeless: chromeless))
    }
}
