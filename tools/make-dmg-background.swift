// Fondo de la ventana del instalador (.dmg), en 1x y 2x.
//   swift tools/make-dmg-background.swift <carpeta de salida> <versión>
//
// Finder pinta el nombre de los íconos en negro (tema claro) o blanco (oscuro) sin mirar el fondo,
// así que la fila de íconos va sobre un eucalipto de tono medio, legible con los dos.
// Las posiciones tienen que coincidir con icon_locations de tools/dmg-settings.py.

import AppKit

let width: CGFloat = 640
let height: CGFloat = 400
let appCenter = CGPoint(x: 180, y: 205)   // desde arriba, como Finder
let appsCenter = CGPoint(x: 460, y: 205)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(scale: CGFloat, version: String) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)  // 2x = mismo tamaño en puntos, el doble de píxeles
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    func y(_ top: CGFloat) -> CGFloat { height - top }

    // Fondo: eucalipto, un poco más oscuro arriba a la izquierda.
    NSGradient(colors: [color(0x2c6f5b), color(0x3a8670), color(0x3f8d76)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -35)

    // Título con la marca (las dos barras) a la izquierda, centrados juntos.
    let title = NSAttributedString(string: "Pausa", attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.white, .kern: -0.3,
    ])
    let markWidth: CGFloat = 9 * 2 + 7, markGap: CGFloat = 12
    let left = (width - (markWidth + markGap + title.size().width)) / 2
    let baseline = y(70)
    color(0xd4ecdf).setFill()
    for (i, h) in [CGFloat(16), 28].enumerated() {
        let r = NSRect(x: left + CGFloat(i) * 16, y: baseline + 20 - h / 2, width: 9, height: h)
        NSBezierPath(roundedRect: r, xRadius: 4.5, yRadius: 4.5).fill()
    }
    title.draw(at: NSPoint(x: left + markWidth + markGap, y: baseline))
    let sub = NSAttributedString(string: "Arrastrá Pausa a Aplicaciones", attributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.82),
    ])
    sub.draw(at: NSPoint(x: (width - sub.size().width) / 2, y: y(96)))

    // Halo suave detrás de cada ícono.
    for c in [appCenter, appsCenter] {
        let halo = NSGradient(colors: [color(0xffffff, 0.16), color(0xffffff, 0)])!
        halo.draw(fromCenter: NSPoint(x: c.x, y: y(c.y)), radius: 0,
                  toCenter: NSPoint(x: c.x, y: y(c.y)), radius: 100, options: [])
    }

    // Flecha de arrastrar, en un arco suave.
    let start = NSPoint(x: appCenter.x + 84, y: y(appCenter.y))
    let end = NSPoint(x: appsCenter.x - 88, y: y(appsCenter.y))
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end, controlPoint1: NSPoint(x: start.x + 30, y: start.y + 26),
              controlPoint2: NSPoint(x: end.x - 34, y: end.y))
    arc.lineWidth = 3.5
    arc.lineCapStyle = .round
    arc.setLineDash([0.1, 9], count: 2, phase: 0)  // puntos
    NSColor.white.withAlphaComponent(0.85).setStroke()
    arc.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x - 12, y: end.y + 11))
    head.line(to: NSPoint(x: end.x + 1, y: end.y))
    head.line(to: NSPoint(x: end.x - 13, y: end.y - 8))
    head.lineWidth = 3.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Pie.
    let foot = NSAttributedString(string: "Versión \(version) · Recordatorios de descanso para macOS", attributes: [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.7),
    ])
    foot.draw(at: NSPoint(x: (width - foot.size().width) / 2, y: 22))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let version = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1.0.0"
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] as [(CGFloat, String)] {
    try! render(scale: scale, version: version).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name))
}
print("OK: \(out.path)/background.png")
