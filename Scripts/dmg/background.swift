import AppKit
import CoreGraphics

let W: CGFloat = 480, H: CGFloat = 680
let appC = CGPoint(x: 240, y: 190)      // top-left origin coords (Finder)
let appsC = CGPoint(x: 240, y: 500)

var seed: UInt64 = 0x5AC0_A11
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 1_000_000) / 1_000_000 }
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }

func render(scale: CGFloat, to path: String) {
    let pw = Int(W*scale), ph = Int(H*scale)
    let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // top-left origin
    seed = 0x5AC0_A11
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Night sky
    let sky = CGGradient(colorsSpace: space, colors: [c(8,10,32), c(22,20,62), c(58,32,88), c(120,60,110)] as CFArray, locations: [0, 0.45, 0.8, 1])!
    ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    // Nebula glows
    for (p, r, col) in [(CGPoint(x: 90, y: 120), 220.0, c(110,70,200,0.22)), (CGPoint(x: 420, y: 330), 240.0, c(230,110,170,0.16)), (CGPoint(x: 240, y: 640), 300.0, c(255,150,190,0.20))] {
        let g = CGGradient(colorsSpace: space, colors: [col, col.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: CGFloat(r), options: [])
    }
    // Stars
    for _ in 0..<170 {
        let p = CGPoint(x: rnd()*W, y: rnd()*H*0.85)
        let r = 0.3 + pow(rnd(), 3) * 1.4
        ctx.setFillColor(c(255, 245, 255, 0.35 + rnd()*0.6))
        ctx.fillEllipse(in: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2))
    }
    for _ in 0..<7 { // sparkles
        let p = CGPoint(x: rnd()*W, y: rnd()*H*0.7), s = 3 + rnd()*4
        ctx.setFillColor(c(255,250,255,0.9))
        ctx.move(to: CGPoint(x: p.x, y: p.y-s)); ctx.addQuadCurve(to: CGPoint(x: p.x+s, y: p.y), control: p)
        ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y+s), control: p); ctx.addQuadCurve(to: CGPoint(x: p.x-s, y: p.y), control: p)
        ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y-s), control: p); ctx.fillPath()
    }
    // Crescent moon
    let m = CGPoint(x: 405, y: 70)
    let mg = CGGradient(colorsSpace: space, colors: [c(255,230,240,0.35), c(255,230,240,0)] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(mg, startCenter: m, startRadius: 0, endCenter: m, endRadius: 70, options: [])
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: m.x-24, y: m.y-24, width: 48, height: 48)); ctx.clip()
    ctx.addRect(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.addEllipse(in: CGRect(x: m.x-12, y: m.y-34, width: 48, height: 48))
    ctx.clip(using: .evenOdd)
    ctx.setFillColor(c(255,240,235)); ctx.fill(CGRect(x: m.x-30, y: m.y-30, width: 60, height: 60))
    ctx.restoreGState()

    // Vinyl record behind the app icon
    let vr: CGFloat = 132
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: c(0,0,0,0.6))
    ctx.setFillColor(c(14,12,20)); ctx.fillEllipse(in: CGRect(x: appC.x-vr, y: appC.y-vr, width: vr*2, height: vr*2))
    ctx.restoreGState()
    var rr: CGFloat = vr - 4
    while rr > 94 {
        ctx.setStrokeColor(c(255,255,255, 0.035 + rnd()*0.05)); ctx.setLineWidth(0.7)
        ctx.strokeEllipse(in: CGRect(x: appC.x-rr, y: appC.y-rr, width: rr*2, height: rr*2)); rr -= 2.6
    }
    // Sheen
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: appC.x-vr, y: appC.y-vr, width: vr*2, height: vr*2)); ctx.clip()
    for a in [CGFloat.pi*0.25, CGFloat.pi*1.25] {
        ctx.move(to: appC)
        ctx.addArc(center: appC, radius: vr, startAngle: a-0.22, endAngle: a+0.22, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(c(255,200,230,0.05)); ctx.fillPath()
    }
    ctx.restoreGState()
    ctx.setStrokeColor(c(255,170,210,0.35)); ctx.setLineWidth(1.2)
    ctx.strokeEllipse(in: CGRect(x: appC.x-vr, y: appC.y-vr, width: vr*2, height: vr*2))
    // Label
    let lr: CGFloat = 94
    let lg = CGGradient(colorsSpace: space, colors: [c(255,190,215), c(235,120,170)] as CFArray, locations: [0,1])!
    ctx.saveGState(); ctx.addEllipse(in: CGRect(x: appC.x-lr, y: appC.y-lr, width: lr*2, height: lr*2)); ctx.clip()
    ctx.drawLinearGradient(lg, start: CGPoint(x: appC.x, y: appC.y-lr), end: CGPoint(x: appC.x, y: appC.y+lr), options: [])
    ctx.restoreGState()

    // Arrow down between icons
    ctx.setStrokeColor(c(255,200,225,0.85)); ctx.setLineWidth(3); ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 9])
    ctx.move(to: CGPoint(x: 240, y: 345)); ctx.addLine(to: CGPoint(x: 240, y: 408)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.move(to: CGPoint(x: 226, y: 400)); ctx.addLine(to: CGPoint(x: 240, y: 416)); ctx.addLine(to: CGPoint(x: 254, y: 400)); ctx.strokePath()

    // Glow behind Applications
    let ag = CGGradient(colorsSpace: space, colors: [c(255,190,220,0.30), c(255,190,220,0)] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(ag, startCenter: appsC, startRadius: 0, endCenter: appsC, endRadius: 95, options: [])

    // Sakura branches
    func branch(_ pts: [CGPoint], width: CGFloat) {
        ctx.setStrokeColor(c(46,24,40)); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: pts[0]); for i in stride(from: 1, to: pts.count-1, by: 2) { ctx.addQuadCurve(to: pts[i+1], control: pts[i]) }
        ctx.strokePath()
    }
    func blossom(_ p: CGPoint, _ r: CGFloat, _ rot: CGFloat, alpha: CGFloat = 1) {
        ctx.saveGState(); ctx.translateBy(x: p.x, y: p.y); ctx.rotate(by: rot)
        for i in 0..<5 {
            ctx.saveGState(); ctx.rotate(by: CGFloat(i) * .pi * 2 / 5)
            let pg = CGGradient(colorsSpace: space, colors: [c(255,120,170,alpha), c(255,215,232,alpha)] as CFArray, locations: [0,1])!
            ctx.move(to: .zero)
            ctx.addCurve(to: CGPoint(x: -r*0.18, y: -r), control1: CGPoint(x: -r*0.65, y: -r*0.35), control2: CGPoint(x: -r*0.55, y: -r*0.95))
            ctx.addLine(to: CGPoint(x: 0, y: -r*0.86)); ctx.addLine(to: CGPoint(x: r*0.18, y: -r))
            ctx.addCurve(to: .zero, control1: CGPoint(x: r*0.55, y: -r*0.95), control2: CGPoint(x: r*0.65, y: -r*0.35))
            ctx.saveGState(); ctx.clip()
            ctx.drawRadialGradient(pg, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
            ctx.restoreGState(); ctx.restoreGState()
        }
        ctx.setFillColor(c(255,240,150,alpha)); ctx.fillEllipse(in: CGRect(x: -r*0.16, y: -r*0.16, width: r*0.32, height: r*0.32))
        ctx.restoreGState()
    }
    branch([CGPoint(x: -10, y: 30), CGPoint(x: 60, y: 20), CGPoint(x: 120, y: 60), CGPoint(x: 160, y: 85), CGPoint(x: 200, y: 70)], width: 7)
    branch([CGPoint(x: 80, y: 38), CGPoint(x: 95, y: 90), CGPoint(x: 70, y: 130)], width: 4)
    branch([CGPoint(x: 140, y: 74), CGPoint(x: 150, y: 40), CGPoint(x: 175, y: 25)], width: 3.5)
    branch([CGPoint(x: 490, y: 560), CGPoint(x: 430, y: 575), CGPoint(x: 395, y: 615), CGPoint(x: 380, y: 635), CGPoint(x: 350, y: 650)], width: 6)
    branch([CGPoint(x: 445, y: 572), CGPoint(x: 440, y: 530), CGPoint(x: 465, y: 505)], width: 3.5)
    let flowers: [(CGFloat, CGFloat, CGFloat)] = [(22,28,13),(48,18,11),(70,42,15),(98,62,12),(118,52,10),(92,96,13),(72,128,11),(152,80,14),(178,24,12),(200,70,11),(160,40,9),(30,58,9),(132,90,8),
        (470,505,12),(452,540,13),(425,578,14),(402,605,11),(372,630,12),(440,600,9),(478,572,10)]
    for f in flowers { blossom(CGPoint(x: f.0, y: f.1), f.2, rnd()*6) }
    // Falling petals
    func petal(_ p: CGPoint, _ s: CGFloat, _ rot: CGFloat, _ a: CGFloat) {
        ctx.saveGState(); ctx.translateBy(x: p.x, y: p.y); ctx.rotate(by: rot)
        ctx.move(to: CGPoint(x: 0, y: -s)); ctx.addCurve(to: CGPoint(x: 0, y: s), control1: CGPoint(x: s*1.1, y: -s*0.6), control2: CGPoint(x: s*0.7, y: s*0.8))
        ctx.addCurve(to: CGPoint(x: 0, y: -s), control1: CGPoint(x: -s*0.7, y: s*0.8), control2: CGPoint(x: -s*1.1, y: -s*0.6))
        ctx.setFillColor(c(255,190,215,a)); ctx.fillPath(); ctx.restoreGState()
    }
    let petals: [(CGFloat, CGFloat)] = [(40,190),(85,300),(30,420),(110,520),(400,170),(440,260),(370,330),(420,420),(60,600),(330,470),(150,380),(300,90),(250,40),(350,230)]
    for p in petals { petal(CGPoint(x: p.0, y: p.1), 4 + rnd()*3, rnd()*6, 0.55 + rnd()*0.4) }

    // Caption
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(srgbRed: 1, green: 0.88, blue: 0.94, alpha: 0.85), .paragraphStyle: para, .kern: 0.6]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    ("Drag Snowdrop into Applications" as NSString).draw(in: CGRect(x: 0, y: 606, width: W, height: 20), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: W, height: H)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(scale: 1, to: "bg.png")
render(scale: 2, to: "bg@2x.png")
