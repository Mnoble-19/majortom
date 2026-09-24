// Renders the MajorTom icons: a violet tile holding a speech bubble, with a
// highlighted word inside it — saving the words you hear, in one picture. The
// calls app swaps the words for a waveform.
//
//   swift make-icon.swift Resources/AppIcon.icns            the library, macOS
//   swift make-icon.swift Calls.icns --calls                the calls app, macOS
//   swift make-icon.swift AppIcon.png --calls --ios         1024px, full bleed
import AppKit

let args = CommandLine.arguments.dropFirst()
let out = args.first { !$0.hasPrefix("--") } ?? "Resources/AppIcon.icns"
let calls = args.contains("--calls")
let ios = args.contains("--ios")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(_ size: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (ios ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // iOS masks the corners itself; macOS icons sit in an inset squircle.
    let box = ios ? CGRect(x: 0, y: 0, width: 1024, height: 1024)
                  : CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = ios ? CGPath(rect: box, transform: nil)
                   : CGPath(roundedRect: box, cornerWidth: 185, cornerHeight: 185, transform: nil)

    if !ios {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.28))
        ctx.addPath(tile)
        ctx.setFillColor(color(0x6C4DF5))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0x8A6BFF), color(0x5A36E6)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: box.maxY),
                           end: CGPoint(x: 0, y: box.minY), options: [])
    ctx.restoreGState()

    // The bubble, with its tail at the lower left.
    let bubble = CGMutablePath()
    bubble.addRoundedRect(in: CGRect(x: 252, y: 344, width: 520, height: 380),
                          cornerWidth: 120, cornerHeight: 120)
    bubble.move(to: CGPoint(x: 318, y: 400))
    bubble.addLine(to: CGPoint(x: 282, y: 262))
    bubble.addLine(to: CGPoint(x: 452, y: 360))
    bubble.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x2A1080, 0.35))
    ctx.addPath(bubble)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    func bar(_ rect: CGRect, _ fill: CGColor) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                           cornerHeight: rect.height / 2, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    if calls {
        let heights: [CGFloat] = [90, 170, 230, 150, 100]
        for (i, h) in heights.enumerated() {
            let x = 348 + CGFloat(i) * 70
            bar(CGRect(x: x, y: 534 - h / 2, width: 46, height: h),
                i == 2 ? color(0xFFC933) : color(0x6C4DF5))
        }
    } else {
        bar(CGRect(x: 330, y: 560, width: 250, height: 76), color(0xFFC933))
        bar(CGRect(x: 330, y: 438, width: 364, height: 58), color(0xCFC4FF))
    }

    return ctx.makeImage()!
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(cgImage: draw(CGFloat(px)))
    rep.size = NSSize(width: px, height: px)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let dest = URL(fileURLWithPath: out)
try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

if dest.pathExtension == "png" {
    try png(1024).write(to: dest)
} else {
    let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MajorTom.iconset")
    try? fm.removeItem(at: work)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    for (px, names) in [
        (16, ["icon_16x16.png"]), (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
        (64, ["icon_32x32@2x.png"]), (128, ["icon_128x128.png"]),
        (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
        (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
        (1024, ["icon_512x512@2x.png"]),
    ] {
        let data = png(px)
        for name in names { try data.write(to: work.appendingPathComponent(name)) }
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", work.path, "-o", dest.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
}
print("wrote \(dest.path)")
