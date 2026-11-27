import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Workspace/offerflow-icon.png")
guard let original = NSImage(contentsOf: source) else { fatalError("Missing OfferFlow icon asset") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // macOS icon canvas: transparent corners around the rounded app tile.
        // Keep the supplied source artwork unchanged; apply the platform mask at export.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        let length = CGFloat(pixels)
        let tile = NSRect(x: length * 0.09, y: length * 0.09, width: length * 0.82, height: length * 0.82)
        NSBezierPath(roundedRect: tile, xRadius: length * 0.17, yRadius: length * 0.17).addClip()
        original.draw(in: NSRect(x: 0, y: 0, width: length, height: length), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
