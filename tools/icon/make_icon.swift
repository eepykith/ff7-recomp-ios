// The app icon (original art, FF7-flavoured: a glowing green orb under a falling red meteor
// on a night sky over a city's lights). Draws 1024x1024 PNG.
//   swift tools/icon/make_icon.swift ios/FF7Recomp/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

// night sky: deep blue at the top, near black below (y grows up in AppKit)
let sky = CGGradient(colorsSpace: rgb, colors: [color(0.01, 0.02, 0.06), color(0.04, 0.07, 0.20), color(0.10, 0.06, 0.22)] as CFArray,
                     locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// a few stars
var seed: UInt64 = 7
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<70 {
    let x = rnd() * size, y = size * 0.45 + rnd() * size * 0.55, r = 1.5 + rnd() * 2.5
    ctx.setFillColor(color(1, 1, 1, 0.25 + rnd() * 0.5))
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
}

// the meteor: a red-orange fireball falling from the top right, with a fading trail
let head = CGPoint(x: size * 0.70, y: size * 0.78)
ctx.saveGState()
let trailPath = CGMutablePath()
trailPath.move(to: CGPoint(x: size * 1.05, y: size * 1.08))
trailPath.addLine(to: CGPoint(x: head.x + 46, y: head.y - 30))
trailPath.addLine(to: CGPoint(x: head.x - 30, y: head.y + 46))
trailPath.closeSubpath()
ctx.addPath(trailPath)
ctx.clip()
let trail = CGGradient(colorsSpace: rgb, colors: [color(1, 0.35, 0.1, 0), color(1, 0.4, 0.12, 0.85)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(trail, start: CGPoint(x: size * 1.05, y: size * 1.08), end: head, options: [])
ctx.restoreGState()
let fire = CGGradient(colorsSpace: rgb, colors: [color(1, 0.95, 0.75), color(1, 0.45, 0.12), color(0.8, 0.08, 0.05, 0)] as CFArray,
                      locations: [0, 0.35, 1])!
ctx.drawRadialGradient(fire, startCenter: head, startRadius: 0, endCenter: head, endRadius: 120, options: [])

// the city: a dark skyline across the bottom, with green lights
ctx.setFillColor(color(0.02, 0.03, 0.05))
let city = CGMutablePath()
city.move(to: CGPoint(x: 0, y: 0))
var x: CGFloat = 0
while x < size {
    let w = 40 + rnd() * 70, h = 120 + rnd() * 150
    city.addLine(to: CGPoint(x: x, y: h)); city.addLine(to: CGPoint(x: x + w, y: h))
    x += w
}
city.addLine(to: CGPoint(x: size, y: 0)); city.closeSubpath()
ctx.addPath(city); ctx.fillPath()
for _ in 0..<60 {
    let lx = rnd() * size, ly = 20 + rnd() * 140
    ctx.setFillColor(color(0.35, 1, 0.55, 0.35 + rnd() * 0.4))
    ctx.fill(CGRect(x: lx, y: ly, width: 6, height: 6))
}

// the orb: a glowing green sphere, low in the middle
let c = CGPoint(x: size * 0.46, y: size * 0.44), r: CGFloat = 250
let glow = CGGradient(colorsSpace: rgb, colors: [color(0.3, 1, 0.5, 0.55), color(0.1, 0.9, 0.4, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: c, startRadius: r * 0.8, endCenter: c, endRadius: r * 1.65, options: [])
let orb = CGGradient(colorsSpace: rgb, colors: [color(0.85, 1, 0.85), color(0.25, 0.95, 0.45), color(0.02, 0.45, 0.18), color(0.0, 0.18, 0.08)] as CFArray,
                     locations: [0, 0.25, 0.75, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
ctx.drawRadialGradient(orb, startCenter: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.4), startRadius: 0,
                       endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
// inner swirl
ctx.setStrokeColor(color(0.8, 1, 0.85, 0.35)); ctx.setLineWidth(14)
ctx.addArc(center: CGPoint(x: c.x + 30, y: c.y - 20), radius: r * 0.55, startAngle: 0.4, endAngle: 2.6, clockwise: false)
ctx.strokePath()
ctx.restoreGState()
// highlight
ctx.setFillColor(color(1, 1, 1, 0.75))
ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.35, width: r * 0.42, height: r * 0.24))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
