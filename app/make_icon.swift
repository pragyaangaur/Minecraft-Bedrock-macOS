// Draw the app icon: an isometric grass block on a rounded night-sky tile.
// The art is drawn here from plain colours, so it uses nothing from the game.
//
// Usage: swift app/make_icon.swift <output.png>
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// The tile follows Apple's icon grid: an 824 point rounded square in a 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x1b2a4a))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let sky = CGGradient(colorsSpace: space, colors: [rgb(0x4d86c8), rgb(0x22407a), rgb(0x0c1430)] as CFArray,
                     locations: [0, 0.6, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

// A few stars in the upper part of the tile, where the sky is darkest.
var seed: UInt64 = 7
func rand() -> Double {
  seed = seed &* 6364136223846793005 &+ 1442695040888963407
  return Double(seed >> 11) / Double(1 << 53)
}
for _ in 0..<26 {
  let s = 6 + 8 * rand()
  ctx.setFillColor(rgb(0xffffff, 0.35 + 0.5 * rand()))
  ctx.fill(CGRect(x: 130 + 760 * rand(), y: 560 + 330 * rand(), width: s, height: s))
}
ctx.restoreGState()

// The cube. Each face is an 8 by 8 grid of pixels with a little noise, sheared
// onto its isometric parallelogram.
let n = 8
let edge = 280.0
let cx = 512.0, cy = 372.0
let ux = edge * cos(.pi / 6), uy = edge * sin(.pi / 6)

func face(origin: CGPoint, a: CGVector, b: CGVector, color: (Int, Int) -> UInt32, shade: CGFloat) {
  for i in 0..<n {
    for j in 0..<n {
      let p0 = CGPoint(x: origin.x + a.dx * CGFloat(i) / CGFloat(n) + b.dx * CGFloat(j) / CGFloat(n),
                       y: origin.y + a.dy * CGFloat(i) / CGFloat(n) + b.dy * CGFloat(j) / CGFloat(n))
      let path = CGMutablePath()
      path.move(to: p0)
      path.addLine(to: CGPoint(x: p0.x + a.dx / CGFloat(n), y: p0.y + a.dy / CGFloat(n)))
      path.addLine(to: CGPoint(x: p0.x + a.dx / CGFloat(n) + b.dx / CGFloat(n), y: p0.y + a.dy / CGFloat(n) + b.dy / CGFloat(n)))
      path.addLine(to: CGPoint(x: p0.x + b.dx / CGFloat(n), y: p0.y + b.dy / CGFloat(n)))
      path.closeSubpath()
      let c = color(i, j)
      let k = shade * CGFloat(0.9 + 0.2 * rand())
      let fill = CGColor(srgbRed: min(1, CGFloat((c >> 16) & 0xff) / 255 * k),
                         green: min(1, CGFloat((c >> 8) & 0xff) / 255 * k),
                         blue: min(1, CGFloat(c & 0xff) / 255 * k), alpha: 1)
      // Stroking each pixel in its own colour closes the hairline gaps between them.
      ctx.setFillColor(fill)
      ctx.setStrokeColor(fill)
      ctx.addPath(path)
      ctx.drawPath(using: .fillStroke)
    }
  }
}

let grass: [UInt32] = [0x5fa83a, 0x6bb843, 0x4f9431, 0x74c24b]
let dirt: [UInt32] = [0x8a5a35, 0x7a4e2c, 0x9a6a42, 0x6e4426]
func top(_ i: Int, _ j: Int) -> UInt32 { grass[Int(rand() * 4)] }
// Side faces run from the bottom edge (j = 0) to the top edge (j = n - 1).
// The top two rows are grass, with a ragged edge.
func side(_ i: Int, _ j: Int) -> UInt32 {
  let grassRows = (i % 3 == 1) ? 3 : 2
  return j >= n - grassRows ? grass[Int(rand() * 4)] : dirt[Int(rand() * 4)]
}

let bottom = CGPoint(x: cx, y: cy - edge / 2)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: rgb(0x000000, 0.5))
let silhouette = CGMutablePath()
silhouette.move(to: bottom)
silhouette.addLine(to: CGPoint(x: cx + ux, y: bottom.y + uy))
silhouette.addLine(to: CGPoint(x: cx + ux, y: bottom.y + uy + edge))
silhouette.addLine(to: CGPoint(x: cx, y: bottom.y + 2 * uy + edge))
silhouette.addLine(to: CGPoint(x: cx - ux, y: bottom.y + uy + edge))
silhouette.addLine(to: CGPoint(x: cx - ux, y: bottom.y + uy))
silhouette.closeSubpath()
ctx.addPath(silhouette)
ctx.setFillColor(rgb(0x3d2a1a))
ctx.fillPath()
ctx.restoreGState()

// Left face, right face, then the top.
face(origin: bottom, a: CGVector(dx: -ux, dy: uy), b: CGVector(dx: 0, dy: edge), color: side, shade: 0.78)
face(origin: bottom, a: CGVector(dx: ux, dy: uy), b: CGVector(dx: 0, dy: edge), color: side, shade: 0.62)
face(origin: CGPoint(x: cx, y: bottom.y + edge), a: CGVector(dx: -ux, dy: uy), b: CGVector(dx: ux, dy: uy),
     color: top, shade: 1.0)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
