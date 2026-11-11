import AppKit
import Observation

// MARK: - VinylWallpaperController

/// Puts a turntable on the desktop: a window under the icons, on every Desktop, showing the
/// current track's cover as the label of a vinyl record that turns while music plays.
///
/// Built to cost almost nothing. The record is drawn once per track and spun by Core
/// Animation (see `VinylWallpaperView`), and the spin is held still whenever it could not
/// be seen or is not wanted: music paused, the wallpaper fully covered by other windows, the
/// display asleep, or Reduce Motion on. Low Power Mode lowers the frame rate.
@MainActor
@Observable
final class VinylWallpaperController {
    static let shared = VinylWallpaperController()

    private(set) var isVisible = false

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var view: VinylWallpaperView?
    @ObservationIgnored private weak var playerService: PlayerService?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var observationGeneration: UInt64 = 0
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var shownArtworkURL: URL?
    @ObservationIgnored private var isDisplayAwake = true
    @ObservationIgnored private var isFirstSpinUpdate = true
    @ObservationIgnored private var lookTimer: Timer?
    @ObservationIgnored private var lookObservationGeneration: UInt64 = 0
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let logger = DiagnosticsLogger.player

    private enum Keys {
        static let visible = "vinylWallpaperVisible"
    }

    private init() {}

    /// Brings the wallpaper back at launch if it was on when Snowdrop last quit.
    func restore(playerService: PlayerService) {
        if self.defaults.bool(forKey: Keys.visible) {
            self.show(playerService: playerService)
        }
    }

    func toggle(playerService: PlayerService) {
        self.isVisible ? self.hide() : self.show(playerService: playerService)
    }

    func show(playerService: PlayerService) {
        guard self.window == nil else { return }
        self.playerService = playerService
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }

        let view = VinylWallpaperView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Just above the system wallpaper and below the desktop icons.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Cmd+H hides every window of the app unless it opts out; the wallpaper must stay.
        window.canHide = false
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()

        self.window = window
        self.view = view
        self.isFirstSpinUpdate = true
        self.isVisible = true
        self.defaults.set(true, forKey: Keys.visible)
        self.installObservers(for: window)
        self.restartPlaybackObservation()
        self.applyLook(animated: false)
        self.restartLookObservation()
        self.refreshArtwork(animated: false)
        self.updateSpin()
        self.logger.info("Vinyl wallpaper shown")
    }

    func hide() {
        self.lookTimer?.invalidate()
        self.lookTimer = nil
        self.lookObservationGeneration &+= 1
        self.artworkTask?.cancel()
        self.artworkTask = nil
        self.observationGeneration &+= 1
        self.removeObservers()
        self.view?.setSpinning(false, framesPerSecond: 30)
        self.window?.orderOut(nil)
        self.window?.contentView = nil
        self.window = nil
        self.view = nil
        self.shownArtworkURL = nil
        self.isVisible = false
        self.defaults.set(false, forKey: Keys.visible)
        self.logger.info("Vinyl wallpaper hidden")
    }

    // MARK: Day and night

    /// The look the settings ask for right now.
    private func currentLook(at date: Date = Date()) -> VinylWallpaperLook {
        let settings = SettingsManager.shared
        switch settings.vinylWallpaperTime {
        case .day: return .day
        case .night: return .night
        case .automatic: return settings.vinylDaySchedule.isNight(at: date) ? .night : .day
        }
    }

    /// Shows the right desk and arms a timer for the next dusk or dawn.
    private func applyLook(animated: Bool) {
        let now = Date()
        self.view?.setLook(self.currentLook(at: now), animated: animated)
        self.lookTimer?.invalidate()
        self.lookTimer = nil
        let settings = SettingsManager.shared
        guard settings.vinylWallpaperTime == .automatic,
              let next = settings.vinylDaySchedule.nextChange(after: now) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLook(animated: true) }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.lookTimer = timer
    }

    /// Re-runs `applyLook` whenever the day/night settings change.
    private func restartLookObservation() {
        self.lookObservationGeneration &+= 1
        self.observeLook(generation: self.lookObservationGeneration)
    }

    private func observeLook(generation: UInt64) {
        withObservationTracking {
            let settings = SettingsManager.shared
            _ = settings.vinylWallpaperTime
            _ = settings.vinylNightStart
            _ = settings.vinylNightEnd
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.lookObservationGeneration == generation, self.isVisible else { return }
                self.applyLook(animated: true)
                self.observeLook(generation: generation)
            }
        }
    }

    // MARK: Playback

    /// Re-runs whenever the playing state or the cover changes; a one-shot tracking loop,
    /// like `NowPlayingManager`'s.
    private func restartPlaybackObservation() {
        self.observationGeneration &+= 1
        self.observePlayback(generation: self.observationGeneration)
    }

    private func observePlayback(generation: UInt64) {
        withObservationTracking {
            _ = self.playerService?.isPlaying
            _ = self.playerService?.currentTrack?.thumbnailURL
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation, self.isVisible else { return }
                self.refreshArtwork(animated: true)
                self.updateSpin()
                self.observePlayback(generation: generation)
            }
        }
    }

    private func refreshArtwork(animated: Bool) {
        let url = self.playerService?.currentTrack?.thumbnailURL?.highQualityThumbnailURL
        guard url != self.shownArtworkURL || self.shownArtworkURL == nil else { return }
        self.shownArtworkURL = url
        self.artworkTask?.cancel()
        guard let url else {
            self.view?.setArtwork(nil, animated: animated)
            return
        }
        self.artworkTask = Task { [weak self] in
            let image = await ImageCache.shared.image(for: url, targetSize: CGSize(width: 600, height: 600))
            guard !Task.isCancelled, let self, self.shownArtworkURL == url else { return }
            self.view?.setArtwork(image, animated: animated)
        }
    }

    // MARK: Power

    /// Applies the policy: spin or hold still, at the right frame rate.
    private func updateSpin() {
        guard let view, let window else { return }
        let spin = VinylSpinPolicy.shouldSpin(
            isPlaying: self.playerService?.isPlaying ?? false,
            isWindowVisible: window.occlusionState.contains(.visible),
            isDisplayAwake: self.isDisplayAwake,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let fps = VinylSpinPolicy.framesPerSecond(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        view.setSpinning(spin, framesPerSecond: fps)
        // The needle follows the music, not visibility: it stays on a record that is playing
        // under a covered wallpaper.
        view.setNeedleDown(self.playerService?.isPlaying ?? false, animated: !self.isFirstSpinUpdate)
        self.isFirstSpinUpdate = false
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSpin() }
        })
        self.observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSpin() }
        })
        self.observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        })

        for name in [NSNotification.Name.NSSystemClockDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyLook(animated: true) }
            })
        }

        let workspace = NSWorkspace.shared.notificationCenter
        self.workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isDisplayAwake = false
                self?.updateSpin()
            }
        })
        self.workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isDisplayAwake = true
                self?.updateSpin()
                self?.applyLook(animated: false)
            }
        })
        self.workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSpin() }
        })
    }

    private func removeObservers() {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in self.workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        self.observers.removeAll()
        self.workspaceObservers.removeAll()
    }

    /// Follows a resolution change or a different primary display.
    private func fitToScreen() {
        guard let window, let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
    }
}
