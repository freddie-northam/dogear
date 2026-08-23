import AppKit

// Renders assets/logo-glyph.png onto a white rounded rect at every icon size,
// producing build/AppIcon.iconset for iconutil.
let glyph = NSImage(contentsOfFile: "assets/logo-glyph.png")!
let iconsetPath = "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let full = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    // Apple icon grid: the squircle occupies ~80% of the canvas.
    let rect = full.insetBy(dx: Double(pixels) * 0.1, dy: Double(pixels) * 0.1)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    NSColor.white.setFill()
    path.fill()
    NSColor.black.withAlphaComponent(0.08).setStroke()
    path.lineWidth = max(1, Double(pixels) / 256)
    path.stroke()
    let glyphInset = rect.width * 0.22
    glyph.draw(in: rect.insetBy(dx: glyphInset, dy: glyphInset))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// The ten names iconutil requires.
for size in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: size)
        .write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size).png"))
    try renderPNG(pixels: size * 2)
        .write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_\(size)x\(size)@2x.png"))
}
print("Wrote \(iconsetPath)")
