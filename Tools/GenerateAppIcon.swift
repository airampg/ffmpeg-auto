import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("BundleResources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

for item in sizes {
    let pixels = item.points * item.scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    drawIcon(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), scale: CGFloat(pixels) / 1024.0)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not create PNG for \(item.name)")
    }
    try png.write(to: iconset.appendingPathComponent(item.name))
}

func drawIcon(in rect: CGRect, scale: CGFloat) {
    NSGraphicsContext.current?.imageInterpolation = .high

    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 52 * scale, dy: 52 * scale), xRadius: 210 * scale, yRadius: 210 * scale)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.35, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.72, blue: 0.78, alpha: 1)
    ])
    gradient?.draw(in: tile, angle: -35)

    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(ovalIn: CGRect(x: 136 * scale, y: 618 * scale, width: 756 * scale, height: 236 * scale)).fill()

    let waveform = NSBezierPath()
    waveform.lineWidth = 44 * scale
    waveform.lineCapStyle = .round
    waveform.lineJoinStyle = .round
    waveform.move(to: CGPoint(x: 178 * scale, y: 522 * scale))
    let points: [CGPoint] = [
        CGPoint(x: 250, y: 522), CGPoint(x: 292, y: 390), CGPoint(x: 350, y: 660),
        CGPoint(x: 422, y: 318), CGPoint(x: 505, y: 708), CGPoint(x: 588, y: 372),
        CGPoint(x: 664, y: 604), CGPoint(x: 738, y: 480), CGPoint(x: 846, y: 480)
    ].map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
    for point in points { waveform.line(to: point) }
    NSColor.white.setStroke()
    waveform.stroke()

    let chunkColor = NSColor.white.withAlphaComponent(0.90)
    chunkColor.setFill()
    for x in [250, 438, 626] {
        let chunk = NSBezierPath(roundedRect: CGRect(x: CGFloat(x) * scale, y: 206 * scale, width: 150 * scale, height: 74 * scale), xRadius: 30 * scale, yRadius: 30 * scale)
        chunk.fill()
    }

    NSColor.white.withAlphaComponent(0.78).setStroke()
    let cut = NSBezierPath()
    cut.lineWidth = 24 * scale
    cut.lineCapStyle = .round
    cut.move(to: CGPoint(x: 512 * scale, y: 186 * scale))
    cut.line(to: CGPoint(x: 512 * scale, y: 300 * scale))
    cut.stroke()
}
