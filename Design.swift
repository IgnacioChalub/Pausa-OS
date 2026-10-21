import Cocoa

// Tokens del design system de Pausa (design/tokens.json, guía en design/README.md).
// Los colores de interfaz tienen versión clara y oscura; los de la pantalla de pausa son fijos.

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    static func pausa(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) }
    }
}

enum Palette {
    static let ink = NSColor.pausa(0x141a18, 0xe9eeeb)
    static let inkMuted = NSColor.pausa(0x5a6662, 0x9aa6a1)
    static let lineStrong = NSColor.pausa(0x808b87, 0x66726d)
    static let surface = NSColor.pausa(0xffffff, 0x1a201e)
    static let accent = NSColor.pausa(0x2b735e, 0x86c4ac)
    static let onAccent = NSColor.pausa(0xffffff, 0x0c1a15)
    static let amber = NSColor.pausa(0x8a5a0f, 0xe0b26a)
    static let danger = NSColor.pausa(0xb0261c, 0xf0a097)

    static let restGround = NSColor(hex: 0x0d1311)
    static let restRaised = NSColor(hex: 0x1e2825)
    static let restLine = NSColor(hex: 0x6b7a74)
    static let restTrack = NSColor(hex: 0x25302c)
    static let restInk = NSColor(hex: 0xedf2ef)
    static let restMuted = NSColor(hex: 0x93a19b)
    static let restAccent = NSColor(hex: 0x86c4ac)
    static let restOnAccent = NSColor(hex: 0x0c1a15)
}

enum Space {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
    static let s6: CGFloat = 24, s8: CGFloat = 32, s12: CGFloat = 48, s16: CGFloat = 64
}

var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

// MARK: - Íconos (SF Symbols)

// Sin color: plantilla, toma el color de donde se dibuja. Con color: queda teñido.
func symbol(_ name: String, size: CGFloat = 14, color: NSColor? = nil) -> NSImage? {
    var config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    if let color { config = config.applying(.init(paletteColors: [color])) }
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    img?.isTemplate = color == nil
    return img
}

// Dos íconos juntos (en una jam: person.2 + el estado).
func joined(_ a: NSImage, _ b: NSImage) -> NSImage {
    let gap = Space.s1
    let size = NSSize(width: a.size.width + gap + b.size.width, height: max(a.size.height, b.size.height))
    let img = NSImage(size: size, flipped: false) { _ in
        a.draw(in: NSRect(x: 0, y: (size.height - a.size.height) / 2, width: a.size.width, height: a.size.height))
        b.draw(in: NSRect(x: a.size.width + gap, y: (size.height - b.size.height) / 2,
                          width: b.size.width, height: b.size.height))
        return true
    }
    img.isTemplate = a.isTemplate && b.isTemplate
    return img
}

// MARK: - Botón píldora

// Botones de la pantalla de pausa y de los banners. Configuración usa los nativos.
final class PillButton: NSButton {
    enum Style { case primary, secondary, quiet }

    private let style: Style
    private let onRest: Bool
    private let large: Bool
    private let handler: () -> Void
    private let textWidth: CGFloat

    init(_ text: String, key: String? = nil, style: Style, onRest: Bool, large: Bool = false,
         action: @escaping () -> Void) {
        self.style = style
        self.onRest = onRest
        self.large = large
        handler = action
        let font = NSFont.systemFont(ofSize: large ? 15 : 13, weight: .medium)
        let fg: NSColor = switch (style, onRest) {
        case (.primary, true): Palette.restOnAccent
        case (.primary, false): Palette.onAccent
        case (.secondary, true): Palette.restInk
        case (.secondary, false): Palette.ink
        case (.quiet, true): Palette.restMuted
        case (.quiet, false): Palette.inkMuted
        }
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let title = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: fg, .paragraphStyle: center])
        if let key {
            title.append(NSAttributedString(string: "  " + key, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: fg.withAlphaComponent(0.72), .paragraphStyle: center,
            ]))
        }
        textWidth = ceil(title.size().width)
        super.init(frame: .zero)
        attributedTitle = title
        isBordered = false
        wantsLayer = true
        target = self
        self.action = #selector(fire)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: textWidth + (large ? Space.s6 : Space.s3) * 2, height: large ? 40 : 28)
    }

    override var wantsUpdateLayer: Bool { true }

    override var isHighlighted: Bool { didSet { needsDisplay = true } }

    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let bg: NSColor? = switch (style, onRest) {
            case (.primary, true): Palette.restAccent
            case (.primary, false): Palette.accent
            case (.secondary, true): Palette.restRaised
            case (.secondary, false): Palette.surface
            case (.quiet, _): nil
            }
            let border: NSColor? = style == .secondary ? (onRest ? Palette.restLine : Palette.lineStrong) : nil
            layer.backgroundColor = bg?.cgColor
            layer.borderColor = border?.cgColor
            layer.borderWidth = border == nil ? 0 : 1
            layer.cornerRadius = bounds.height / 2
            layer.opacity = isHighlighted ? 0.75 : 1
        }
    }
}

// MARK: - Barra de progreso de la pausa

final class ProgressBar: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 4) }

    override func draw(_ dirtyRect: NSRect) {
        Palette.restTrack.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
        var done = bounds
        done.size.width *= min(max(fraction, 0), 1)
        guard done.width > 0 else { return }
        Palette.restAccent.setFill()
        NSBezierPath(roundedRect: done, xRadius: 2, yRadius: 2).fill()
    }
}

// Texto fijo (NSTextField de solo lectura) con fuente y color.
func label(_ text: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    if kern != 0 {
        l.attributedStringValue = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }
    return l
}
