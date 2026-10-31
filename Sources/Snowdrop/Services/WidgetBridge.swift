#if SNOWDROP_WIDGETS
    import AppKit
    import Foundation
    import Observation
    import WidgetKit

    // MARK: - WidgetBridge

    /// Publishes what is playing to the widget extension through the app group,
    /// and routes the widget's transport buttons back to the player.
    @MainActor
    final class WidgetBridge {
        static let shared = WidgetBridge()

        private var playerService: PlayerService?
        private var artworkID = ""
        private var reloadTask: Task<Void, Never>?
        private var artworkTask: Task<Void, Never>?

        func start(playerService: PlayerService) {
            guard self.playerService == nil else { return }
            self.playerService = playerService

            WidgetIntentRouter.handler = { command in
                let payload: RemoteMusicCommandPayload = switch command {
                case .togglePlayPause: .togglePlayPause
                case .next: .trackNavigation(direction: .forward)
                case .previous: .trackNavigation(direction: .backward)
                }
                try? AppIntentsBridge.shared.sendTransportCommand(payload)
            }

            self.publish()
            self.observe()
        }

        /// Re-runs whenever anything the widget shows changes. Progress is left out on
        /// purpose: the widget animates it, so seconds ticking must not reload it.
        private func observe() {
            guard let player = self.playerService else { return }
            withObservationTracking {
                _ = player.currentTrack?.videoId
                _ = player.state
                _ = player.currentIndex
                _ = player.queue.count
                _ = player.duration
                _ = SettingsManager.shared.theme
            } onChange: {
                Task { @MainActor in
                    self.publish()
                    self.observe()
                }
            }
        }

        private func publish() {
            guard let player = self.playerService else { return }
            let accent = Self.components(of: SettingsManager.shared.theme)

            guard let track = player.currentTrack else {
                var idle = NowPlayingSnapshot.idle
                idle.accent = accent
                idle.save()
                self.scheduleReload()
                return
            }

            let queue = player.queue
            let next = queue.dropFirst(player.currentIndex + 1).prefix(3).map {
                NowPlayingSnapshot.UpNext(title: $0.title, artist: $0.artistsDisplay)
            }

            NowPlayingSnapshot(
                hasTrack: true,
                title: track.title,
                artist: track.artistsDisplay,
                album: track.album?.title ?? "",
                isPlaying: player.isPlaying,
                progress: player.progress,
                duration: player.duration > 0 ? player.duration : (track.duration ?? 0),
                updatedAt: Date(),
                upNext: Array(next),
                accent: accent,
                artworkID: track.videoId
            ).save()

            self.updateArtwork(for: track)
            self.scheduleReload()
        }

        private func updateArtwork(for track: Song) {
            guard track.videoId != self.artworkID else { return }
            self.artworkID = track.videoId
            self.artworkTask?.cancel()
            guard let source = track.thumbnailURL?.highQualityThumbnailURL ?? track.thumbnailURL,
                  let destination = SnowdropShared.artworkURL
            else { return }
            let videoId = track.videoId

            self.artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: source),
                      !Task.isCancelled,
                      let jpeg = Self.downscaledJPEG(from: data, maxSide: 480)
                else { return }
                try? jpeg.write(to: destination, options: .atomic)
                guard let self, self.artworkID == videoId else { return }
                self.scheduleReload()
            }
        }

        private func scheduleReload() {
            self.reloadTask?.cancel()
            self.reloadTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                WidgetCenter.shared.reloadTimelines(ofKind: SnowdropShared.widgetKind)
            }
        }

        private static func components(of theme: SnowdropTheme) -> [Double] {
            let color = NSColor(theme.accent).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.42, green: 0.72, blue: 0.95, alpha: 1)
            return [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
        }

        private nonisolated static func downscaledJPEG(from data: Data, maxSide: CGFloat) -> Data? {
            guard let source = NSImage(data: data), source.size.width > 0 else { return nil }
            let scale = min(1, maxSide / max(source.size.width, source.size.height))
            let size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            source.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
    }
#endif
