import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws the app icon at every size an .icns needs and writes a .iconset
/// folder. build.sh pipes the result through iconutil.
///
/// The mark is the Anthropic four-spoke glyph in coral on the cream canvas —
/// the two colours the design system is built on.

let canvasColor = CGColor(srgbRed: 0.980, green: 0.976, blue: 0.961, alpha: 1) // #faf9f5
let coral       = CGColor(srgbRed: 0.800, green: 0.471, blue: 0.361, alpha: 1) // #cc785c
let coralDeep   = CGColor(srgbRed: 0.663, green: 0.345, blue: 0.243, alpha: 1) // #a9583e
let inkEdge     = CGColor(srgbRed: 0.078, green: 0.078, blue: 0.075, alpha: 0.08)

/// The four-spoke mark: four points with concave shoulders.
func spikePath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let w = rect.width, h = rect.height
    let s: CGFloat = 0.052   // shoulder offset — how sharp the spikes read
    let t: CGFloat = 0.235   // control reach along the perpendicular axis

    p.move(to: CGPoint(x: cx, y: rect.minY))
    p.addCurve(to: CGPoint(x: rect.maxX, y: cy),
               control1: CGPoint(x: cx + w * s, y: cy - h * t),
               control2: CGPoint(x: cx + w * t, y: cy - h * s))
    p.addCurve(to: CGPoint(x: cx, y: rect.maxY),
               control1: CGPoint(x: cx + w * t, y: cy + h * s),
               control2: CGPoint(x: cx + w * s, y: cy + h * t))
    p.addCurve(to: CGPoint(x: rect.minX, y: cy),
               control1: CGPoint(x: cx - w * s, y: cy + h * t),
               control2: CGPoint(x: cx - w * t, y: cy + h * s))
    p.addCurve(to: CGPoint(x: cx, y: rect.minY),
               control1: CGPoint(x: cx - w * t, y: cy - h * s),
               control2: CGPoint(x: cx - w * s, y: cy - h * t))
    p.closeSubpath()
    return p
}

func drawIcon(size: Int) -> CGImage? {
    let dim = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))

    // macOS icons sit inside the canvas with breathing room around them.
    let inset = dim * 0.098
    let plate = CGRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
    let radius = plate.width * 0.2246          // Apple's squircle proportion

    let plancePath = CGPath(roundedRect: plate, cornerWidth: radius,
                            cornerHeight: radius, transform: nil)

    // Soft drop shadow so the plate reads on both light and dark Docks.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dim * 0.006),
                  blur: dim * 0.022,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.20))
    ctx.addPath(plancePath)
    ctx.setFillColor(canvasColor)
    ctx.fillPath()
    ctx.restoreGState()

    // A hairline keeps the cream plate from dissolving into a white background.
    ctx.addPath(plancePath)
    ctx.setStrokeColor(inkEdge)
    ctx.setLineWidth(max(1, dim * 0.003))
    ctx.strokePath()

    // The mark, with a vertical coral gradient for a little depth.
    let markSize = plate.width * 0.60
    let markRect = CGRect(x: plate.midX - markSize / 2,
                          y: plate.midY - markSize / 2,
                          width: markSize, height: markSize)
    ctx.saveGState()
    ctx.addPath(spikePath(in: markRect))
    ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [coral, coralDeep] as CFArray,
        locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: markRect.midX, y: markRect.maxY),
                               end:   CGPoint(x: markRect.midX, y: markRect.minY),
                               options: [])
    } else {
        ctx.setFillColor(coral)
        ctx.fill(markRect)
    }
    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// MARK: - main

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: IconGen <output.iconset>\n".utf8))
    exit(1)
}

let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// (base point size, scale) pairs iconutil expects.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
                              (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

var written = 0
for (base, scale) in variants {
    let pixels = base * scale
    guard let image = drawIcon(size: pixels) else { continue }
    let suffix = scale == 2 ? "@2x" : ""
    let url = outDir.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
    if write(image, to: url) { written += 1 }
}

print("wrote \(written) icon variants to \(outDir.path)")
exit(written == variants.count ? 0 : 1)
