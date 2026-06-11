// Renders the Hotstash app icon (1024x1024) programmatically.
// Usage: swift tools/render-icon.swift <output.png>
// Regenerate the full appiconset with tools/generate-icons.sh

import AppKit

// MARK: - Canvas constants

let canvas: CGFloat = 1024
// Apple macOS icon grid: 824x824 squircle centered in 1024 canvas
let tileOrigin: CGFloat = 100
let tileSize: CGFloat = 824
let tileCornerRadius: CGFloat = 185

// MARK: - Color helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - Flame path (y-up coordinates, 1024 canvas)

/// Builds the flame silhouette. `scale` shrinks toward the flame base so
/// inner layers nest inside the outer one. `lean` shifts the tip sideways.
func flamePath(scale: CGFloat, baseY: CGFloat, centerX: CGFloat, lean: CGFloat) -> NSBezierPath {
    // Reference geometry at scale 1
    let h: CGFloat = 500 * scale          // total flame height
    let w: CGFloat = 330 * scale          // max half-spread * 2

    let tip = NSPoint(x: centerX + lean * scale, y: baseY + h)
    let right = NSPoint(x: centerX + w / 2, y: baseY + h * 0.34)
    let bottom = NSPoint(x: centerX, y: baseY)
    let left = NSPoint(x: centerX - w / 2, y: baseY + h * 0.34)

    let p = NSBezierPath()
    p.move(to: tip)
    // Right side: gentle convex sweep from tip down to right bulge
    p.curve(to: right,
            controlPoint1: NSPoint(x: tip.x + 10 * scale, y: tip.y - h * 0.16),
            controlPoint2: NSPoint(x: right.x + 4 * scale, y: right.y + h * 0.26))
    // Bottom right: round belly
    p.curve(to: bottom,
            controlPoint1: NSPoint(x: right.x, y: baseY + h * 0.10),
            controlPoint2: NSPoint(x: centerX + w * 0.28, y: baseY))
    // Bottom left: round belly
    p.curve(to: left,
            controlPoint1: NSPoint(x: centerX - w * 0.28, y: baseY),
            controlPoint2: NSPoint(x: left.x, y: baseY + h * 0.10))
    // Left side: characteristic concave lick up to the tip
    p.curve(to: tip,
            controlPoint1: NSPoint(x: left.x + 6 * scale, y: baseY + h * 0.62),
            controlPoint2: NSPoint(x: tip.x - 90 * scale, y: tip.y - h * 0.30))
    p.close()
    return p
}

// MARK: - Render

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// --- Squircle tile ---
let tileRect = NSRect(x: tileOrigin, y: tileOrigin, width: tileSize, height: tileSize)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: tileCornerRadius, yRadius: tileCornerRadius)

// Background: deep charcoal with a warm ember floor
tile.addClip()
let bg = NSGradient(colors: [rgb(0x101018), rgb(0x1C1A22), rgb(0x2B1410)],
                    atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB)!
bg.draw(in: tileRect, angle: -90)

// Radial ember glow behind the flame
let glowColors = [rgb(0xFF6A00, 0.50).cgColor, rgb(0xFF6A00, 0.0).cgColor] as CFArray
if let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                         colors: glowColors, locations: [0, 1]) {
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 500), endRadius: 400,
                           options: [])
}

// --- Flame layers ---
func fillFlame(_ path: NSBezierPath, top: NSColor, bottom: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: bottom, ending: top)!
        .draw(in: path.bounds, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}

// --- Stash: stacked sheets the flame rises from ---
// Three rounded bars, widest on top, fading downward — the "history stack".
let barSpecs: [(width: CGFloat, y: CGFloat, alpha: CGFloat)] = [
    (400, 268, 0.92),
    (312, 206, 0.42),
    (228, 152, 0.18),
]
for spec in barSpecs {
    let barHeight: CGFloat = 38
    let rect = NSRect(x: 512 - spec.width / 2, y: spec.y,
                      width: spec.width, height: barHeight)
    rgb(0xF5EDE2, spec.alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
}

// Soft drop shadow under the flame for depth
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 60,
              color: rgb(0x000000, 0.55).cgColor)
let outer = flamePath(scale: 0.92, baseY: 346, centerX: 512, lean: 56)
fillFlame(outer, top: rgb(0xFF3D00), bottom: rgb(0xFF9F0A))
ctx.restoreGState()

let mid = flamePath(scale: 0.60, baseY: 356, centerX: 512, lean: 36)
fillFlame(mid, top: rgb(0xFF9500), bottom: rgb(0xFFD60A))

let core = flamePath(scale: 0.31, baseY: 366, centerX: 512, lean: 18)
fillFlame(core, top: rgb(0xFFE066), bottom: rgb(0xFFF7CC))

image.unlockFocus()

// --- Write PNG ---
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode png")
}
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
