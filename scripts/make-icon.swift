import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: s); transform.concat()
        NSColor(calibratedRed: 0.09, green: 0.18, blue: 0.32, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 190, yRadius: 190).fill()
        let blocks: [(NSRect, NSColor)] = [
            (NSRect(x: 180, y: 180, width: 370, height: 664), NSColor(calibratedRed: 0.63, green: 0.77, blue: 1, alpha: 1)),
            (NSRect(x: 586, y: 460, width: 258, height: 384), NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 1)),
            (NSRect(x: 586, y: 180, width: 258, height: 244), NSColor(calibratedRed: 0.44, green: 0.57, blue: 0.87, alpha: 1))
        ]
        for (rect, color) in blocks { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill() }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
