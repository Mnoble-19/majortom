// Renders AppIcon.icns. Two stacked bars — amber over cyan — the same pair the
// overlay uses for original and translation.
//
//   swift make-icon.swift Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let fm = FileManager.default
let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MajorTom.iconset")
try? fm.removeItem(at: work)
try fm.createDirectory(at: work, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(_ size: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = size / 1024

    // macOS icons sit in a squircle inset from the canvas edge.
    let inset: CGFloat = 100 * s
    let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: box, cornerWidth: 185 * s, cornerHeight: 185 * s,
                          transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0x232A38), color(0x0B0D12)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Hairline highlight along the top edge, the usual macOS lift.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.setLineWidth(3 * s)
    ctx.strokePath()
    ctx.restoreGState()

    func bar(width: CGFloat, y: CGFloat, fill: CGColor, glow: Bool) {
        let h = 86 * s
        let rect = CGRect(x: (size - width * s) / 2, y: y * s, width: width * s, height: h)
        let path = CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2,
                          transform: nil)
        if glow {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 44 * s, color: fill.copy(alpha: 0.55))
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
            ctx.restoreGState()
        } else {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
    }

    bar(width: 500, y: 556, fill: color(0xFFD479), glow: true)
    bar(width: 340, y: 392, fill: color(0x7EC8E3), glow: false)

    return ctx.makeImage()!
}

for (px, names) in [
    (16, ["icon_16x16.png"]), (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]), (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
] {
    let image = draw(CGFloat(px))
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: px, height: px)
    let data = rep.representation(using: .png, properties: [:])!
    for name in names { try data.write(to: work.appendingPathComponent(name)) }
}

let dest = URL(fileURLWithPath: out)
try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", work.path, "-o", dest.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
print("wrote \(dest.path)")
