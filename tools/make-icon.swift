// Genera el ícono de la app: assets/AppIcon.icns (y assets/AppIcon.png de 1024).
//   swift tools/make-icon.swift
//
// La marca del design system: dos barras redondeadas, la corta es la pausa de la vista y la
// larga la de pararse, en `rest-accent` sobre el fondo de la pantalla de pausa (`rest-ground`).

import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let restGround: UInt32 = 0x0d1311
let restRaised: UInt32 = 0x1e2825
let restAccent: UInt32 = 0x86c4ac

// Geometría de la marca, compartida con assets/Logos/pausa-mark.svg.
let barWidth: CGFloat = 124
let barGap: CGFloat = 92
let shortBar: CGFloat = 268
let longBar: CGFloat = 452

// Rectángulo de esquinas continuas (superelipse), como los íconos de macOS.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let k = CGFloat(size) / 1024
    ctx.scaleBy(x: k, y: k)

    // Cuerpo: grilla de íconos de macOS (824 de 1024), con su sombra.
    let body = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(restGround))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(restRaised), color(restGround)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Filo de luz arriba.
    ctx.addPath(body)
    ctx.setStrokeColor(color(0xffffff, 0.07))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // Las dos barras, centradas.
    let total = barWidth * 2 + barGap
    let x0 = 512 - total / 2
    for (i, h) in [shortBar, longBar].enumerated() {
        let r = CGRect(x: x0 + CGFloat(i) * (barWidth + barGap), y: 512 - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    }
    ctx.setFillColor(color(restAccent))
    ctx.fillPath()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let assets = root.appendingPathComponent("assets")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(size: base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try! render(size: 1024).representation(using: .png, properties: [:])!
    .write(to: assets.appendingPathComponent("AppIcon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "OK: assets/AppIcon.icns" : "iconutil falló")
