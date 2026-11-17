// Draws the app icon. Run: swift Tools/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func fill(_ path: NSBezierPath, from top: NSColor, to bottom: NSColor) {
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
}

// Background tile, on the macOS icon grid: 824 pt square with a soft shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35).cgColor)
color(20, 60, 140).setFill()
tilePath.fill()
context.restoreGState()
fill(tilePath, from: color(74, 158, 255), to: color(18, 72, 190))

// Folder: a back panel with a tab, then a lighter front panel.
let back = NSBezierPath()
back.move(to: NSPoint(x: 232, y: 420))
back.line(to: NSPoint(x: 232, y: 712))
back.appendArc(withCenter: NSPoint(x: 268, y: 712), radius: 36, startAngle: 180, endAngle: 90, clockwise: true)
back.line(to: NSPoint(x: 430, y: 748))
back.line(to: NSPoint(x: 492, y: 690))
back.line(to: NSPoint(x: 756, y: 690))
back.appendArc(withCenter: NSPoint(x: 756, y: 654), radius: 36, startAngle: 90, endAngle: 0, clockwise: true)
back.line(to: NSPoint(x: 792, y: 420))
back.close()
fill(back, from: color(240, 170, 30), to: color(224, 148, 16))

let front = NSBezierPath(roundedRect: NSRect(x: 232, y: 372, width: 560, height: 268), xRadius: 40, yRadius: 40)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: color(120, 70, 0, 0.35).cgColor)
color(255, 205, 70).setFill()
front.fill()
context.restoreGState()
fill(front, from: color(255, 220, 104), to: color(250, 190, 48))

// Drive capacity bar: the This Mac page in one shape.
let track = NSBezierPath(roundedRect: NSRect(x: 232, y: 262, width: 560, height: 52), xRadius: 26, yRadius: 26)
color(255, 255, 255, 0.28).setFill()
track.fill()
let used = NSBezierPath(roundedRect: NSRect(x: 232, y: 262, width: 360, height: 52), xRadius: 26, yRadius: 26)
color(255, 255, 255).setFill()
used.fill()

NSGraphicsContext.current = nil
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
