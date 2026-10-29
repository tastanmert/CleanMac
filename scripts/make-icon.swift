// Renders the app icon: usage `swift scripts/make-icon.swift <out.png>`
// Same mark as AppMark in the app: an open "C" ring with a dot at its tip, in flat colours (no gradients).
import AppKit

let size: CGFloat = 1024
let ink = NSColor(red: 0x16 / 255.0, green: 0x1A / 255.0, blue: 0x2C / 255.0, alpha: 1)     // body
let mint = NSColor(red: 0x5E / 255.0, green: 0xE6 / 255.0, blue: 0xC0 / 255.0, alpha: 1)    // ring
let coral = NSColor(red: 0xFF / 255.0, green: 0x7A / 255.0, blue: 0x59 / 255.0, alpha: 1)   // dot

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon body: 824 pt squircle centred on the 1024 canvas, with the usual drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.4).cgColor)
ctx.addPath(bodyPath)
ctx.setFillColor(ink.cgColor)
ctx.fillPath()
ctx.restoreGState()

// The ring: an arc from 43° to 317°, open on the right.
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 240
let lineWidth: CGFloat = 112
let startAngle = CGFloat.pi * 2 * 0.12, endAngle = CGFloat.pi * 2 * 0.88
let arc = CGMutablePath()
arc.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
ctx.addPath(arc.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.setFillColor(mint.cgColor)
ctx.fillPath()

// The dot at the ring's upper tip, set a little apart from it.
let tip = CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))
let dot = CGPoint(x: tip.x + 92, y: tip.y + 64)
ctx.setFillColor(coral.cgColor)
ctx.fillEllipse(in: CGRect(x: dot.x - 52, y: dot.y - 52, width: 104, height: 104))

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[1]))
