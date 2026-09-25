import AppKit

let sizes = [16, 32, 128, 256, 512]
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let side = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
        let inset = rect.insetBy(dx: side * 0.04, dy: side * 0.04)
        let tile = NSBezierPath(roundedRect: inset, xRadius: side * 0.21, yRadius: side * 0.21)
        let gradient = NSGradient(
            colors: [NSColor(white: 0.16, alpha: 1), NSColor(white: 0.05, alpha: 1)])
        gradient?.draw(in: tile, angle: -90)
        let notchWidth = inset.width * 0.62
        let notchHeight = inset.height * 0.44
        let notch = NSRect(
            x: inset.midX - notchWidth / 2, y: inset.minY, width: notchWidth, height: notchHeight)
        let radius = side * 0.11
        let path = NSBezierPath()
        path.move(to: NSPoint(x: notch.minX, y: notch.minY))
        path.line(to: NSPoint(x: notch.minX, y: notch.maxY - radius))
        path.appendArc(
            withCenter: NSPoint(x: notch.minX + radius, y: notch.maxY - radius), radius: radius,
            startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: notch.maxX - radius, y: notch.maxY))
        path.appendArc(
            withCenter: NSPoint(x: notch.maxX - radius, y: notch.maxY - radius), radius: radius,
            startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: notch.maxX, y: notch.minY))
        path.close()
        NSColor(white: 0.97, alpha: 1).setFill()
        path.fill()
        let dot = side * 0.08
        let bar = NSRect(
            x: notch.minX + side * 0.08, y: notch.maxY - side * 0.135, width: dot, height: dot)
        for index in 0..<3 {
            let colors = [
                NSColor(red: 0.98, green: 0.36, blue: 0.33, alpha: 1),
                NSColor(red: 0.98, green: 0.74, blue: 0.24, alpha: 1),
                NSColor(red: 0.28, green: 0.78, blue: 0.36, alpha: 1),
            ]
            colors[index].setFill()
            NSBezierPath(ovalIn: bar.offsetBy(dx: CGFloat(index) * dot * 1.5, dy: 0)).fill()
        }
        return true
    }
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    representation.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return representation.representation(using: .png, properties: [:])!
}

for size in sizes {
    try render(size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
