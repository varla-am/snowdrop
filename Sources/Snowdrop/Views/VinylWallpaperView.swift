import AppKit
import QuartzCore

// MARK: - VinylSpinPolicy

/// Decides when the wallpaper record turns and how often it is redrawn. Pure, so the
/// battery rules can be tested without a window.
enum VinylSpinPolicy {
    /// 33 1/3 rpm: one turn every 1.8 seconds, like a real record.
    static let secondsPerTurn: CFTimeInterval = 1.8

    /// 60 Hz keeps the turn and the tonearm silky; Low Power Mode halves it.
    static func framesPerSecond(lowPowerMode: Bool) -> Float {
        lowPowerMode ? 30 : 60
    }

    /// Spins only while music plays and somebody can actually see the wallpaper: a
    /// window that is fully covered, a sleeping display or Reduce Motion all hold it still.
    static func shouldSpin(
        isPlaying: Bool,
        isWindowVisible: Bool,
        isDisplayAwake: Bool,
        reduceMotion: Bool
    ) -> Bool {
        isPlaying && isWindowVisible && isDisplayAwake && !reduceMotion
    }
}

// MARK: - VinylSpinDynamics

/// How a turntable platter really moves: the motor brings it up to speed in about a second,
/// and when the motor lets go it coasts to a stop over a few seconds, fast at first and then
/// slower (viscous drag), with a little constant friction so it does stop. Pure maths, so it
/// is tested without a window.
struct VinylSpinDynamics {
    /// Radians per second at 33 1/3 rpm.
    static let cruiseSpeed: Double = 2 * .pi / VinylSpinPolicy.secondsPerTurn
    /// Time constant of the motor pulling the platter up to speed.
    static let spinUpTimeConstant: Double = 0.45
    /// Time constant of the coast-down, and the constant friction under it (rad/s^2).
    static let coastTimeConstant: Double = 1.5
    static let friction: Double = 0.35
    /// Below this the platter counts as stopped.
    static let restSpeed: Double = 0.02

    var angle: Double = 0
    var speed: Double = 0
    var targetSpeed: Double = 0

    var isMoving: Bool {
        self.speed > 0 || self.targetSpeed > 0
    }

    /// Advances by `dt` seconds. Returns whether the platter is still moving or wanted to move.
    @discardableResult
    mutating func advance(by dt: Double) -> Bool {
        guard dt > 0 else { return self.isMoving }
        if self.targetSpeed > self.speed {
            let blend = 1 - exp(-dt / Self.spinUpTimeConstant)
            self.speed += (self.targetSpeed - self.speed) * blend
            if self.targetSpeed - self.speed < 0.005 { self.speed = self.targetSpeed }
        } else if self.targetSpeed < self.speed {
            self.speed -= (self.speed / Self.coastTimeConstant + Self.friction) * dt
            if self.speed < Self.restSpeed { self.speed = self.targetSpeed }
        }
        // Clockwise seen from above is negative about y.
        self.angle -= self.speed * dt
        return self.isMoving
    }
}

// MARK: - VinylWallpaperView

/// The wallpaper: a desk seen from above, drawn live. A brushed-metal top, the cover in its
/// sleeve, a record with grooves and a static highlight, and a tonearm.
///
/// Only the label (which carries the cover) turns, as on a real record; the grooves and the
/// highlight are symmetric and stay put. The tonearm swings as one layer, and its shadow is a
/// blurred silhouette that swings with it and drifts away as the arm lifts, so the shadow can
/// never fall out of step with the arm.
///
/// Power: a display link runs only while something moves (the label, its coast-down, the arm,
/// or the change between day and night), at 60 fps, 30 in Low Power Mode. Otherwise nothing is
/// drawn.
final class VinylWallpaperView: NSView {
    private let stage = CALayer()
    private let backgroundDay = CALayer()
    private let backgroundNight = CALayer()
    private let sleeve = CALayer()
    private let sleeveGloss = CAGradientLayer()
    private let record = CALayer()
    private let highlight = CAGradientLayer()
    private let highlightMask = CAShapeLayer()
    private let labelHost = CALayer()
    private let spindle = CALayer()
    private let armShadow = CALayer()
    private let arm = CALayer()

    nonisolated(unsafe) private var displayLink: CADisplayLink?
    private var dynamics = VinylSpinDynamics()
    private var armMotion = VinylArmMotion()
    private var lookBlend: Double = 0
    private var lookTarget: Double = 0
    private var lookRate: Double = 1.0 / 6

    private(set) var isSpinning = false
    private(set) var isNeedleDown = false
    private var framesPerSecond: Float = 60

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.layer?.backgroundColor = CGColor(srgbRed: 0.1, green: 0.11, blue: 0.13, alpha: 1)
        self.buildLayers()
        self.apply()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated { self.displayLink?.invalidate() }
    }

    // MARK: Layers

    private func buildLayers() {
        let size = VinylDesk.size
        self.stage.anchorPoint = .zero
        self.stage.bounds = CGRect(origin: .zero, size: size)
        self.layer?.addSublayer(self.stage)

        for layer in [self.backgroundDay, self.backgroundNight] {
            layer.anchorPoint = .zero
            layer.frame = self.stage.bounds
            self.stage.addSublayer(layer)
        }
        self.backgroundDay.contents = VinylDeskRenderer.background(night: false)
        self.backgroundNight.contents = VinylDeskRenderer.background(night: true)

        // Sleeve, with its cover, a glossy sheen and a thin dark edge.
        let side = VinylDesk.sleeveSide
        self.sleeve.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        self.sleeve.position = VinylDesk.up(VinylDesk.sleeveCenter)
        self.sleeve.transform = CATransform3DMakeRotation(-VinylDesk.sleeveTilt, 0, 0, 1)
        self.sleeve.contentsGravity = .resizeAspectFill
        self.sleeve.masksToBounds = false
        self.sleeve.backgroundColor = CGColor(srgbRed: 0.93, green: 0.70, blue: 0.78, alpha: 1)
        self.sleeve.borderColor = CGColor(gray: 0, alpha: 0.65)
        self.sleeve.borderWidth = 3
        self.sleeve.shadowColor = CGColor(gray: 0, alpha: 1)
        self.sleeve.shadowRadius = 26
        self.sleeve.shadowOffset = CGSize(width: 6, height: -18)
        self.sleeve.shadowPath = CGPath(rect: self.sleeve.bounds, transform: nil)
        self.sleeveGloss.frame = self.sleeve.bounds
        self.sleeveGloss.colors = [
            CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.07),
        ]
        self.sleeveGloss.locations = [0, 0.5, 1]
        self.sleeveGloss.startPoint = CGPoint(x: 0, y: 1)
        self.sleeveGloss.endPoint = CGPoint(x: 1, y: 0)
        self.sleeve.addSublayer(self.sleeveGloss)
        self.stage.addSublayer(self.sleeve)

        // Record.
        let radius = VinylDesk.recordRadius
        let center = VinylDesk.up(VinylDesk.recordCenter)
        self.record.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        self.record.position = center
        self.record.contents = VinylDeskRenderer.record()
        self.record.minificationFilter = .trilinear
        self.record.shadowColor = CGColor(gray: 0, alpha: 1)
        self.record.shadowRadius = 32
        self.record.shadowOffset = CGSize(width: 8, height: -20)
        self.record.shadowPath = CGPath(ellipseIn: self.record.bounds, transform: nil)
        self.stage.addSublayer(self.record)

        // A static highlight: two soft wedges of light across the grooves.
        self.highlight.frame = self.record.frame
        self.highlight.type = .conic
        self.highlight.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.highlight.endPoint = CGPoint(x: 0.5, y: 1)
        let wedge = { (alpha: CGFloat) in CGColor(gray: 1, alpha: alpha) }
        let clear = CGColor(gray: 1, alpha: 0)
        self.highlight.colors = [
            clear, clear, wedge(0.05), wedge(0.2), wedge(0.05), clear,
            clear, wedge(0.04), wedge(0.15), wedge(0.04), clear, clear,
        ]
        self.highlight.locations = [0, 0.05, 0.085, 0.11, 0.135, 0.17, 0.55, 0.585, 0.61, 0.635, 0.67, 1]
        let ring = CGMutablePath()
        let local = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        ring.addEllipse(in: local.insetBy(dx: 4, dy: 4))
        ring.addEllipse(in: local.insetBy(dx: radius - VinylDesk.labelRadius - 14, dy: radius - VinylDesk.labelRadius - 14))
        self.highlightMask.path = ring
        self.highlightMask.fillRule = .evenOdd
        self.highlightMask.frame = self.highlight.bounds
        self.highlight.mask = self.highlightMask
        self.stage.addSublayer(self.highlight)

        // Label and spindle.
        let labelSide = VinylDesk.labelRadius * 2
        self.labelHost.bounds = CGRect(x: 0, y: 0, width: labelSide, height: labelSide)
        self.labelHost.position = center
        self.labelHost.contents = VinylLabelRenderer.labelImage(artwork: nil)
        self.labelHost.minificationFilter = .trilinear
        self.stage.addSublayer(self.labelHost)
        self.spindle.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
        self.spindle.position = center
        self.spindle.cornerRadius = 7
        self.spindle.backgroundColor = CGColor(gray: 0.82, alpha: 1)
        self.spindle.borderColor = CGColor(gray: 0.35, alpha: 1)
        self.spindle.borderWidth = 1
        self.stage.addSublayer(self.spindle)

        // Tonearm and its shadow share one pivot.
        let rect = VinylDesk.armRect
        let anchor = CGPoint(x: -rect.minX / rect.width, y: -rect.minY / rect.height)
        for layer in [self.armShadow, self.arm] {
            layer.bounds = CGRect(origin: .zero, size: rect.size)
            layer.anchorPoint = anchor
            layer.minificationFilter = .trilinear
            self.stage.addSublayer(layer)
        }
        self.arm.contents = VinylDeskRenderer.arm(silhouette: false)
        self.armShadow.contents = VinylDeskRenderer.armShadow()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let size = VinylDesk.size
        // Aspect fill: crop the edges rather than stretch.
        let scale = max(self.bounds.width / size.width, self.bounds.height / size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.stage.position = CGPoint(
            x: (self.bounds.width - size.width * scale) / 2,
            y: (self.bounds.height - size.height * scale) / 2
        )
        self.stage.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    // MARK: Day and night

    /// Shows the day or the night desk. Animated, one fades into the other slowly, like dusk.
    func setLook(_ look: VinylWallpaperLook, animated: Bool, duration: TimeInterval = 6) {
        let target: Double = look == .night ? 1 : 0
        guard target != self.lookTarget || (!animated && self.lookBlend != target) else { return }
        self.lookTarget = target
        self.lookRate = 1 / max(duration, 0.1)
        if !animated { self.lookBlend = target }
        self.apply()
        self.updateDisplayLink()
    }

    // MARK: Content

    /// Shows a new cover (nil for none) in the sleeve and as the record's label.
    func setArtwork(_ image: NSImage?, animated: Bool) {
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.6
            self.sleeve.add(fade, forKey: "snowdrop.vinyl.cover")
            self.labelHost.add(fade, forKey: "snowdrop.vinyl.label")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let image, let cgImage = VinylLabelRenderer.cgImage(from: image) {
            self.sleeve.contents = cgImage
            self.sleeve.backgroundColor = nil
        } else {
            self.sleeve.contents = nil
            self.sleeve.backgroundColor = CGColor(srgbRed: 0.93, green: 0.70, blue: 0.78, alpha: 1)
        }
        self.labelHost.contents = VinylLabelRenderer.labelImage(artwork: image)
        CATransaction.commit()
    }

    // MARK: Motion

    /// Starts the motor, or lets the platter coast to a stop.
    func setSpinning(_ spinning: Bool, framesPerSecond: Float) {
        guard spinning != self.isSpinning || framesPerSecond != self.framesPerSecond else { return }
        self.isSpinning = spinning
        self.framesPerSecond = framesPerSecond
        self.dynamics.targetSpeed = spinning ? VinylSpinDynamics.cruiseSpeed : 0
        self.updateDisplayLink()
    }

    /// Swings the arm onto the record (playing) or back to its rest (paused).
    func setNeedleDown(_ down: Bool, animated: Bool) {
        guard down != self.isNeedleDown else { return }
        self.isNeedleDown = down
        self.armMotion.move(toPlaying: down, animated: animated)
        self.apply()
        self.updateDisplayLink()
    }

    private var needsFrames: Bool {
        self.dynamics.isMoving || self.armMotion.isMoving || self.lookBlend != self.lookTarget
    }

    /// Runs the display link only while something moves.
    private func updateDisplayLink() {
        if self.needsFrames {
            if self.displayLink == nil {
                let link = self.displayLink(target: self, selector: #selector(self.tick(_:)))
                link.add(to: .main, forMode: .common)
                self.displayLink = link
            }
            let fps = self.framesPerSecond
            self.displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(fps, 30), maximum: fps, preferred: fps)
        } else {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(max(link.targetTimestamp - link.timestamp, 0), 0.1)
        self.dynamics.advance(by: dt)
        self.armMotion.advance(by: dt)
        let step = self.lookRate * dt
        if self.lookBlend < self.lookTarget {
            self.lookBlend = min(self.lookBlend + step, self.lookTarget)
        } else if self.lookBlend > self.lookTarget {
            self.lookBlend = max(self.lookBlend - step, self.lookTarget)
        }
        self.apply()
        if !self.needsFrames { self.updateDisplayLink() }
    }

    // MARK: Frame

    /// Sets every moving layer from the current state.
    private func apply() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Day to night, eased.
        let t = self.lookBlend
        let night = t * t * (3 - 2 * t)
        self.backgroundNight.opacity = Float(night)
        let shadow = Float(0.38 + 0.32 * night)
        self.sleeve.shadowOpacity = shadow
        self.record.shadowOpacity = shadow

        // The label turns.
        self.labelHost.transform = CATransform3DMakeRotation(CGFloat(self.dynamics.angle), 0, 0, 1)

        // The arm swings; its shadow is the same shape, shifted away by how high it is lifted.
        let pose = self.armMotion.pose
        let angle = VinylDesk.armRestAngle + (VinylDesk.armPlayAngle - VinylDesk.armRestAngle) * pose
        let lift = pose >= 0.82 ? (1 - pose) / 0.18 : 0.35 + 0.65 * min(pose / 0.15, 1)
        let rotation = CATransform3DMakeRotation(CGFloat(-angle), 0, 0, 1)
        let pivot = VinylDesk.up(VinylDesk.armPivot)
        self.arm.position = pivot
        self.arm.transform = rotation
        self.armShadow.position = CGPoint(x: pivot.x + 6 + 20 * CGFloat(lift), y: pivot.y - 10 - 28 * CGFloat(lift))
        self.armShadow.transform = rotation
        self.armShadow.opacity = Float((0.42 + 0.3 * night) * (1 - 0.45 * lift))
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
