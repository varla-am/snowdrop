import AppKit
import CoreImage

// MARK: - VinylWallpaperLook

/// Which light the desk is shown in.
enum VinylWallpaperLook: String, Sendable {
    case day
    case night
}

// MARK: - VinylDesk

/// The fixed layout of the wallpaper, in a 1600 x 1000 design space with the origin at the top left.
enum VinylDesk {
    static let size = CGSize(width: 1600, height: 1000)
    static let recordCenter = CGPoint(x: 900, y: 500)
    static let recordRadius: CGFloat = 320
    static let labelRadius: CGFloat = 104
    static let sleeveCenter = CGPoint(x: 410, y: 525)
    static let sleeveSide: CGFloat = 440
    /// Slight tilt of the sleeve, in radians, clockwise on screen.
    static let sleeveTilt: CGFloat = 3.5 * .pi / 180
    static let armPivot = CGPoint(x: 1400, y: 190)
    static let armLength: CGFloat = 525
    /// Direction of the arm from its pivot, in radians clockwise from the +x axis, y down.
    static let armRestAngle: Double = 98 * .pi / 180
    static let armPlayAngle: Double = 121 * .pi / 180

    /// Where the needle is for an arm direction.
    static func needle(atAngle angle: Double) -> CGPoint {
        CGPoint(
            x: self.armPivot.x + self.armLength * CGFloat(cos(angle)),
            y: self.armPivot.y + self.armLength * CGFloat(sin(angle))
        )
    }

    /// A design-space point (y down) in layer space (y up).
    static func up(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: self.size.height - point.y)
    }

    /// Arm drawing space: pivot at the origin, the arm along +x. The image covers this rect.
    static let armRect = CGRect(x: -150, y: -110, width: armLength + 280, height: 220)
}

// MARK: - VinylDeskRenderer

/// Draws the wallpaper's still pictures once, at start. Everything that moves is a layer made
/// from one of these, so a frame only has to move and blend layers.
enum VinylDeskRenderer {
    private struct Noise {
        var state: UInt64
        mutating func next() -> CGFloat {
            self.state &+= 0x9E37_79B9_7F4A_7C15
            var z = self.state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return CGFloat(z % 10000) / 10000
        }
    }

    private static func context(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map(\.1) as CFArray,
            locations: stops.map(\.0)
        )
    }

    private static func gray(_ value: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: value, green: value, blue: value, alpha: alpha)
    }

    // MARK: Background

    /// A brushed-metal desk top with a soft vignette.
    static func background(night: Bool, scale: CGFloat = 2) -> CGImage? {
        let size = VinylDesk.size
        guard let ctx = self.context(Int(size.width * scale), Int(size.height * scale)) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let top = night ? (0.165, 0.175, 0.200) : (0.89, 0.87, 0.83)
        let bottom = night ? (0.105, 0.112, 0.130) : (0.78, 0.76, 0.72)
        if let g = self.gradient([
            (0, CGColor(srgbRed: top.0, green: top.1, blue: top.2, alpha: 1)),
            (1, CGColor(srgbRed: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)),
        ]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        // Brushed streaks.
        var noise = Noise(state: night ? 11 : 23)
        ctx.setLineCap(.round)
        for _ in 0 ..< 5200 {
            let y = noise.next() * size.height
            let x = noise.next() * (size.width + 200) - 100
            let length = 30 + noise.next() * 340
            let light = noise.next() > 0.5
            let alpha = 0.015 + noise.next() * 0.045
            ctx.setStrokeColor(light ? self.gray(1, alpha * (night ? 0.8 : 1.6)) : self.gray(0, alpha * (night ? 1.6 : 0.9)))
            ctx.setLineWidth(0.6 + noise.next() * 0.9)
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + length, y: y + (noise.next() - 0.5) * 0.6))
            ctx.strokePath()
        }
        // Vignette.
        if let g = self.gradient([(0, self.gray(0, 0)), (0.6, self.gray(0, 0)), (1, self.gray(0, night ? 0.5 : 0.2))]) {
            ctx.drawRadialGradient(
                g, startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width * 0.62, options: .drawsAfterEndLocation
            )
        }
        return ctx.makeImage()
    }

    // MARK: Record

    /// The disc without its label: grooves, track gaps and a worn edge.
    static func record(scale: CGFloat = 3) -> CGImage? {
        let radius = VinylDesk.recordRadius
        let side = Int(radius * 2 * scale)
        guard let ctx = self.context(side, side) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: radius, y: radius)

        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        ctx.clip()
        if let g = self.gradient([(0, self.gray(0.115)), (1, self.gray(0.045))]) {
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
        }
        var noise = Noise(state: 5)
        var r = VinylDesk.labelRadius + 18
        while r < radius - 8 {
            ctx.setStrokeColor(self.gray(1, 0.012 + noise.next() * 0.075))
            ctx.setLineWidth(0.7)
            ctx.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            r += 1.25
        }
        for gap in [178.0, 224.0, 263.0, 296.0] as [CGFloat] {
            ctx.setStrokeColor(self.gray(0, 0.6))
            ctx.setLineWidth(4.5)
            ctx.strokeEllipse(in: CGRect(x: -gap, y: -gap, width: gap * 2, height: gap * 2))
            ctx.setStrokeColor(self.gray(1, 0.10))
            ctx.setLineWidth(0.8)
            let outer = gap + 3
            ctx.strokeEllipse(in: CGRect(x: -outer, y: -outer, width: outer * 2, height: outer * 2))
        }
        // Smooth band around the label.
        ctx.setStrokeColor(self.gray(0.02, 0.9))
        ctx.setLineWidth(16)
        let band = VinylDesk.labelRadius + 10
        ctx.strokeEllipse(in: CGRect(x: -band, y: -band, width: band * 2, height: band * 2))
        ctx.restoreGState()

        ctx.setStrokeColor(self.gray(1, 0.16))
        ctx.setLineWidth(2.5)
        let edge = radius - 1.5
        ctx.strokeEllipse(in: CGRect(x: -edge, y: -edge, width: edge * 2, height: edge * 2))
        ctx.setStrokeColor(self.gray(0, 0.6))
        ctx.setLineWidth(1)
        let inner = radius - 5
        ctx.strokeEllipse(in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))
        return ctx.makeImage()
    }

    // MARK: Tonearm

    /// The tonearm in its own space (pivot at the origin, arm along +x). `silhouette` draws it
    /// all in black, for the shadow.
    static func arm(silhouette: Bool, scale: CGFloat = 3) -> CGImage? {
        let rect = VinylDesk.armRect
        guard let ctx = self.context(Int(rect.width * scale), Int(rect.height * scale)) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        let length = VinylDesk.armLength
        let metal = { (light: CGFloat) -> CGColor in silhouette ? self.gray(0) : self.gray(light) }

        func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        func fill(_ path: CGPath, top: CGFloat, bottom: CGFloat, bounds: CGRect) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if silhouette {
                ctx.setFillColor(self.gray(0))
                ctx.fill(bounds)
            } else if let g = self.gradient([(0, self.gray(top)), (1, self.gray(bottom))]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: bounds.maxY), end: CGPoint(x: 0, y: bounds.minY), options: [])
            }
            ctx.restoreGState()
        }

        // Counterweight and rod.
        let weight = CGRect(x: -104, y: -25, width: 70, height: 50)
        fill(roundedRect(weight, 12), top: 0.62, bottom: 0.18, bounds: weight)
        let rod = CGRect(x: -36, y: -5, width: 64, height: 10)
        fill(roundedRect(rod, 4), top: 0.85, bottom: 0.4, bounds: rod)

        // Tube: layered strokes give it a rounded, metallic look.
        let tube = CGMutablePath()
        tube.move(to: CGPoint(x: 24, y: 0))
        tube.addCurve(
            to: CGPoint(x: length - 54, y: -22),
            control1: CGPoint(x: length * 0.42, y: 8),
            control2: CGPoint(x: length * 0.78, y: -12)
        )
        ctx.setLineCap(.round)
        for (width, shade) in [(16.0, 0.42), (12.0, 0.62), (7.0, 0.82), (2.4, 0.98)] as [(CGFloat, CGFloat)] {
            ctx.addPath(tube)
            ctx.setStrokeColor(metal(shade))
            ctx.setLineWidth(width)
            ctx.strokePath()
        }

        // Headshell and cartridge.
        let shell = CGRect(x: length - 66, y: -52, width: 84, height: 30)
        fill(roundedRect(shell, 6), top: 0.78, bottom: 0.38, bounds: shell)
        let cartridge = CGRect(x: length - 36, y: -70, width: 40, height: 20)
        fill(roundedRect(cartridge, 4), top: 0.3, bottom: 0.1, bounds: cartridge)

        // Pivot base.
        let base = CGRect(x: -42, y: -42, width: 84, height: 84)
        ctx.saveGState()
        ctx.addEllipse(in: base)
        ctx.clip()
        if silhouette {
            ctx.setFillColor(self.gray(0))
            ctx.fill(base)
        } else if let g = self.gradient([(0, self.gray(0.96)), (0.55, self.gray(0.62)), (1, self.gray(0.28))]) {
            ctx.drawRadialGradient(
                g, startCenter: CGPoint(x: -10, y: 12), startRadius: 2,
                endCenter: .zero, endRadius: 46, options: .drawsAfterEndLocation
            )
        }
        ctx.restoreGState()
        if !silhouette {
            ctx.setFillColor(self.gray(0.12))
            ctx.fillEllipse(in: CGRect(x: -15, y: -15, width: 30, height: 30))
            ctx.setStrokeColor(self.gray(1, 0.5))
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: base.insetBy(dx: 1, dy: 1))
        }
        return ctx.makeImage()
    }

    /// The arm's soft shadow: its silhouette, blurred.
    static func armShadow(scale: CGFloat = 3) -> CGImage? {
        guard let silhouette = self.arm(silhouette: true, scale: scale) else { return nil }
        let input = CIImage(cgImage: silhouette)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 9 * scale).cropped(to: input.extent)
        return CIContext().createCGImage(blurred, from: input.extent)
    }
}

// MARK: - Arm motion

/// The tonearm's swing between rest (0) and the record (1), eased at both ends.
struct VinylArmMotion {
    static let lowerDuration: Double = 1.7
    static let raiseDuration: Double = 1.3

    private(set) var pose: Double
    private var from: Double
    private var target: Double
    private var elapsed: Double = 0
    private var duration: Double = 1

    init(pose: Double = 0) {
        self.pose = pose
        self.from = pose
        self.target = pose
    }

    var isMoving: Bool {
        self.pose != self.target
    }

    mutating func move(toPlaying playing: Bool, animated: Bool) {
        let goal: Double = playing ? 1 : 0
        guard goal != self.target || !animated else { return }
        self.target = goal
        guard animated else {
            self.pose = goal
            self.from = goal
            return
        }
        self.from = self.pose
        self.elapsed = 0
        self.duration = playing ? Self.lowerDuration : Self.raiseDuration
    }

    mutating func advance(by dt: Double) {
        guard self.isMoving else { return }
        self.elapsed += dt
        let t = min(self.elapsed / self.duration, 1)
        let eased = t * t * (3 - 2 * t)
        self.pose = t >= 1 ? self.target : self.from + (self.target - self.from) * eased
    }
}

// MARK: - Label

/// The record's centre label: the current cover in a circle with a rim, a notch and a spindle
/// hole. It is the one part of the record that visibly turns.
enum VinylLabelRenderer {
    static func labelImage(artwork: NSImage?, pixels: Int = 512) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let size = CGFloat(pixels)
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2

        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.91, blue: 0.83, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

        let artRadius = radius * 0.84
        let artRect = CGRect(x: center.x - artRadius, y: center.y - artRadius, width: artRadius * 2, height: artRadius * 2)
        context.saveGState()
        context.addEllipse(in: artRect)
        context.clip()
        if let artwork, let cgImage = self.cgImage(from: artwork) {
            let image = CGSize(width: cgImage.width, height: cgImage.height)
            let scale = max(artRect.width / image.width, artRect.height / image.height)
            let drawSize = CGSize(width: image.width * scale, height: image.height * scale)
            context.draw(cgImage, in: CGRect(
                x: artRect.midX - drawSize.width / 2, y: artRect.midY - drawSize.height / 2,
                width: drawSize.width, height: drawSize.height
            ))
        } else {
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.70, blue: 0.78, alpha: 1))
            context.fill(artRect)
        }
        context.restoreGState()

        context.setStrokeColor(CGColor(srgbRed: 0.2, green: 0.12, blue: 0.08, alpha: 0.55))
        context.setLineWidth(size * 0.006)
        context.strokeEllipse(in: artRect)
        context.setLineWidth(size * 0.003)
        context.strokeEllipse(in: artRect.insetBy(dx: -size * 0.045, dy: -size * 0.045))

        // A small notch, so the turning is visible even on a plain cover.
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.12, blue: 0.08, alpha: 0.7))
        context.fillEllipse(in: CGRect(x: center.x - size * 0.018, y: size - size * 0.072, width: size * 0.036, height: size * 0.036))

        context.setBlendMode(.clear)
        let hole = radius * 0.07
        context.fillEllipse(in: CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
        return context.makeImage()
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
