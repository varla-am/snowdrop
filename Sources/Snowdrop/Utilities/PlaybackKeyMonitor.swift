import AppKit

// MARK: - PlaybackKeyMonitor

/// Space (play / pause) and F (fullscreen), plus the YouTube letters J / K / L / C,
/// handled before AppKit routes the key.
///
/// The menu shortcut for Space only works while no text field looks focused and
/// while no web view takes the key first. The YouTube page also reacts to Space
/// and F on its own, so the key sometimes paused the page and sometimes did
/// nothing. Handling it here, once, makes it consistent.
@MainActor
final class PlaybackKeyMonitor {
    private static let spaceKeyCode: UInt16 = 49
    private static let fKeyCode: UInt16 = 3

    /// YouTube's own letter shortcuts, by key code.
    enum VideoKey {
        case back10, playPause, forward10, captions
    }

    private static let videoKeys: [UInt16: VideoKey] = [38: .back10, 40: .playPause, 37: .forward10, 8: .captions]

    private var monitor: Any?

    private let togglePlayback: @MainActor () -> Bool
    private let toggleFullscreen: @MainActor () -> Bool
    private let handleVideoKey: @MainActor (VideoKey) -> Bool

    /// - Parameters:
    ///   - togglePlayback: Pauses or resumes the routed player. Returns false when nothing is playable.
    ///   - toggleFullscreen: Toggles the video fullscreen. Returns false when no video is showing.
    ///   - handleVideoKey: Runs a YouTube letter shortcut. Returns false when the video is not the routed player.
    init(
        togglePlayback: @escaping @MainActor () -> Bool,
        toggleFullscreen: @escaping @MainActor () -> Bool,
        handleVideoKey: @escaping @MainActor (VideoKey) -> Bool
    ) {
        self.togglePlayback = togglePlayback
        self.toggleFullscreen = toggleFullscreen
        self.handleVideoKey = handleVideoKey
    }

    func start() {
        guard self.monitor == nil else { return }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard !event.isARepeat,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .control, .option, .shift]),
              let window = event.window, window.isKeyWindow,
              !window.isSheet,
              !Self.isEditingText(in: window)
        else { return false }

        switch event.keyCode {
        case Self.spaceKeyCode:
            return self.togglePlayback()
        case Self.fKeyCode:
            return self.toggleFullscreen()
        default:
            guard let key = Self.videoKeys[event.keyCode] else { return false }
            return self.handleVideoKey(key)
        }
    }

    /// A text field, a text view or a focused button (full keyboard access) keeps its keys.
    private static func isEditingText(in window: NSWindow) -> Bool {
        let responder = window.firstResponder
        // Inside a web view the page owns text editing; the YouTube surface has no text input.
        if responder is NSText || responder is NSTextField { return true }
        if responder is NSButton, NSApp.isFullKeyboardAccessEnabled { return true }
        return false
    }

}
