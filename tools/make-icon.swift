// Generates Resources/AppIcon.icns:  swiftc tools/make-icon.swift -o /tmp/mkicon && /tmp/mkicon
import Cocoa

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.17, blue: 0.32, alpha: 1), NSColor(red: 0.0, green: 0.62, blue: 0.62, alpha: 1)])!
        .draw(in: path, angle: -60)
    if let sym = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s * 0.5, weight: .medium)) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: (s - sym.size.width) / 2, y: (s - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = "/tmp/SimWatchdog.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
