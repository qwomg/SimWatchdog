// Composes store/README screenshots (2880x1800) from REAL captures of the app:
//   build/SimWatchdog.app/Contents/MacOS/SimWatchdog --snapshot-menu menu.png --fake-level 62 ...
//   build/SimWatchdog.app/Contents/MacOS/SimWatchdog --snapshot settings.png
// Usage: swiftc tools/compose-screenshots.swift -o /tmp/compose && /tmp/compose menu.png settings.png outdir
import Cocoa

let W = 2880, H = 1800
let args = CommandLine.arguments
guard args.count == 5, let menu = NSImage(contentsOfFile: args[1]), let settings = NSImage(contentsOfFile: args[2]), let menuLow = NSImage(contentsOfFile: args[3]) else {
    print("usage: compose menu.png settings.png menu-low.png outdir"); exit(1)
}
let outDir = args[4]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func canvas(_ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func wallpaper(_ variant: Int) {
    let sets: [[UInt32]] = [[0x141a3d, 0x3b2370, 0x0e4a63], [0x0b1e3a, 0x1d4f7a, 0x2a1f5c], [0x1a1033, 0x4a2a7d, 0x0b3d4f], [0x10241f, 0x1c5a55, 0x23306b]]
    let c = sets[variant % sets.count]
    NSGradient(colors: [color(c[0]), color(c[1]), color(c[2])])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 35)
    for (x, y, r, a) in [(2300, 1300, 900, 0.18), (500, 400, 800, 0.14), (1500, 900, 600, 0.08)] as [(Int, Int, Int, Double)] {
        NSGradient(colors: [NSColor.white.withAlphaComponent(a), NSColor.white.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: CGFloat(r), options: [])
    }
}

/// Menu bar strip with our real status item content (SF Symbol + percentage) at the right.
func menuBar(percent: String, red: Bool = false) -> NSRect {
    let bar = NSRect(x: 0, y: H - 64, width: W, height: 64)
    color(0x000000, 0.42).setFill(); bar.fill()
    let font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .regular)
    let text = NSAttributedString(string: " \(percent)", attributes: [.font: font, .foregroundColor: red ? color(0xff6b6b) : NSColor.white])
    let sym = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 32, weight: .regular))!
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus(); sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1); (red ? color(0xff6b6b) : NSColor.white).set()
    NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop); tinted.unlockFocus()
    let total = sym.size.width + text.size().width
    let x = CGFloat(W) - 330 - total
    tinted.draw(in: NSRect(x: x, y: bar.minY + (64 - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
    text.draw(at: NSPoint(x: x + sym.size.width, y: bar.minY + (64 - text.size().height) / 2))
    return NSRect(x: x, y: bar.minY, width: total, height: 64)
}

func shadowed(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.55); sh.shadowBlurRadius = 60; sh.shadowOffset = NSSize(width: 0, height: -24)
    sh.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}

func caption(_ title: String, _ sub: String, width: CGFloat = 1100) {
    let p = NSMutableParagraphStyle(); p.lineSpacing = 4; p.lineBreakMode = .byWordWrapping
    NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 116, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: p])
        .draw(in: NSRect(x: 170, y: 760, width: width, height: 620))
    NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 52, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: p])
        .draw(in: NSRect(x: 170, y: 340, width: width, height: 380))
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    // Re-encode without an alpha channel (App Store screenshots must not have one). The canvas is fully opaque anyway.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name)")
}

func drawMenuUnderBar(scale: CGFloat, item: NSRect, menu: NSImage? = nil) {
    let menu = menu ?? { () -> NSImage in menuDefault }()
    let w = menu.size.width * scale, h = menu.size.height * scale
    let r = NSRect(x: min(CGFloat(W) - w - 90, item.maxX - w + 60), y: CGFloat(H) - 64 - 14 - h, width: w, height: h)
    shadowed { menu.draw(in: r) }
}

func drawSettings(scale: CGFloat, x: CGFloat, y: CGFloat) {
    let w = settings.size.width * scale, h = settings.size.height * scale
    let r = NSRect(x: x, y: y, width: w, height: h)
    shadowed {
        let path = NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36)
        NSGraphicsContext.saveGraphicsState(); path.addClip(); settings.draw(in: r); NSGraphicsContext.restoreGraphicsState()
    }
}

let menuDefault = menu
// 1. Menu bar + menu
save(canvas {
    wallpaper(0)
    let item = menuBar(percent: "62%")
    drawMenuUnderBar(scale: 1.55, item: item)
    caption("Never lose work to an out-of-memory crash.", "SimWatchdog sits in your menu bar and closes iOS Simulators before your Mac freezes, panics and restarts.")
}, "01-menu-bar.png")

// 2. Settings
save(canvas {
    wallpaper(1)
    _ = menuBar(percent: "62%")
    drawSettings(scale: 2.3, x: 1480, y: 150)
    caption("Your limit.\nYour rules.", "Choose when it acts, what it closes and how often it checks. Changes apply instantly.", width: 1200)
}, "02-settings.png")

// 3. AI coding
save(canvas {
    wallpaper(2)
    let item = menuBar(percent: "14%", red: true)
    drawMenuUnderBar(scale: 1.55, item: item, menu: menuLow)
    caption("Built for AI-assisted coding.", "Coding agents and parallel builds boot simulators fast. SimWatchdog closes them when memory runs low, so your session survives.")
}, "03-ai-coding.png")

// 4. How it works
save(canvas {
    wallpaper(3)
    _ = menuBar(percent: "62%")
    let steps = [("1", "Watches", "Reads macOS's own memory-available figure every few seconds. About 0% CPU."),
                 ("2", "Confirms", "If memory is low it checks again 3 seconds later, so a spike never triggers it."),
                 ("3", "Closes", "Shuts simulators down, force-kills what's left, and tells you what it did.")]
    NSAttributedString(string: "Quiet until it matters.", attributes: [.font: NSFont.systemFont(ofSize: 140, weight: .bold), .foregroundColor: NSColor.white])
        .draw(at: NSPoint(x: 190, y: 1330))
    for (i, s) in steps.enumerated() {
        let r = NSRect(x: 190 + i * 880, y: 420, width: 800, height: 700)
        shadowed { color(0xffffff, 0.12).setFill(); NSBezierPath(roundedRect: r, xRadius: 50, yRadius: 50).fill() }
        NSAttributedString(string: s.0, attributes: [.font: NSFont.systemFont(ofSize: 150, weight: .heavy), .foregroundColor: color(0x5eead4)]).draw(at: NSPoint(x: r.minX + 60, y: r.maxY - 220))
        NSAttributedString(string: s.1, attributes: [.font: NSFont.systemFont(ofSize: 90, weight: .bold), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: r.minX + 60, y: r.maxY - 340))
        let p = NSMutableParagraphStyle(); p.lineSpacing = 8
        NSAttributedString(string: s.2, attributes: [.font: NSFont.systemFont(ofSize: 52), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: p])
            .draw(in: NSRect(x: r.minX + 60, y: r.minY + 50, width: 690, height: 300))
    }
}, "04-how-it-works.png")
