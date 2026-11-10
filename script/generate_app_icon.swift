import AppKit
import Foundation

// Listr's icon in the "air" style of the app: a near-white tile with soft washes of color and
// one black disc carrying three level bars — the app's play button, speaking.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset")
let iconOutput = URL(fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().first ?? "Resources/AppIcon.icns")

let fileManager = FileManager.default
try? fileManager.removeItem(at: outputDirectory)
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let paper = NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
let ink = NSColor(calibratedRed: 0.114, green: 0.114, blue: 0.122, alpha: 1.0)
// Soft blobs: color, center (fractions of the tile, origin bottom-left), radius fraction.
let blobs: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
    (NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.82, alpha: 0.95), 0.22, 0.80, 0.62),
    (NSColor(calibratedRed: 0.72, green: 0.64, blue: 1.00, alpha: 0.95), 0.84, 0.70, 0.60),
    (NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.62, alpha: 0.95), 0.52, 0.10, 0.62),
]

let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(pixels: Int, to url: URL) throws {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = size * 0.055
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.205
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).setClip()
    paper.setFill()
    rect.fill()
    for (color, x, y, radiusFraction) in blobs {
        let center = NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?.draw(
            fromCenter: center, radius: 0, toCenter: center, radius: rect.width * radiusFraction, options: []
        )
    }

    let disc = size * 0.46
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: (size - disc) / 2, y: (size - disc) / 2, width: disc, height: disc)).fill()

    // Three bars, tallest in the middle — a book spine read as a level meter.
    let barWidth = size * 0.052
    let gap = size * 0.042
    let centerX = size * 0.5
    let heights: [CGFloat] = [0.13, 0.22, 0.16]
    NSColor.white.setFill()
    for (index, fraction) in heights.enumerated() {
        let height = size * fraction
        let x = centerX + CGFloat(index - 1) * (barWidth + gap) - barWidth / 2
        let bar = NSRect(x: x, y: (size - height) / 2, width: barWidth, height: height)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try data.write(to: url)
}

for iconFile in iconFiles {
    try drawIcon(pixels: iconFile.pixels, to: outputDirectory.appendingPathComponent(iconFile.name))
}

try? fileManager.removeItem(at: iconOutput)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", outputDirectory.path, "-o", iconOutput.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print("Generated \(iconOutput.path)")
