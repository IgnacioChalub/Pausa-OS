import Cocoa
import Carbon
import CoreAudio
import Network

let claudeDoneNotification = Notification.Name("com.ignacio.pausa.claudeDone")

// Modo CLI: el hook de Claude Code corre `Pausa --claude-done` para avisarle a la app.
if CommandLine.arguments.contains("--claude-done") {
    DistributedNotificationCenter.default().postNotificationName(
        claudeDoneNotification, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// La configuración está en config.yml (ver Config.swift).

func play(_ sound: String) {
    if !sound.isEmpty { NSSound(named: sound)?.play() }
}

func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

// Segundos desde el último movimiento de mouse, click o tecla (no necesita permiso de Accesibilidad).
func idleSeconds() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - Reuniones

// Estás en reunión si alguna app está usando el micrófono (Zoom, Meet, Teams, Slack...).
func micInUse() -> Bool {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return false }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return false }
    addr.mSelector = kAudioProcessPropertyIsRunningInput
    return ids.contains { id in
        var running: UInt32 = 0
        var s = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &s, &running) == noErr && running != 0
    }
}

// MARK: - Atajo de teclado

struct HotKey {
    let code: UInt32
    let carbonMods: UInt32
    let equivalent: String
    let mask: NSEvent.ModifierFlags
}

let keyCodes: [String: (code: Int, equiv: String)] = {
    var m: [String: (code: Int, equiv: String)] = [
        "esc": (kVK_Escape, "\u{1b}"), "escape": (kVK_Escape, "\u{1b}"), "space": (kVK_Space, " "),
        "return": (kVK_Return, "\r"), "enter": (kVK_Return, "\r"), "tab": (kVK_Tab, "\t"),
    ]
    let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
                   kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
                   kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
                   kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z]
    for (c, code) in zip("abcdefghijklmnopqrstuvwxyz", letters) { m[String(c)] = (code, String(c)) }
    let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                  kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    for (c, code) in zip("0123456789", digits) { m[String(c)] = (code, String(c)) }
    let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                 kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
    for (i, code) in fkeys.enumerated() {
        m["f\(i + 1)"] = (code, String(UnicodeScalar(UInt16(NSF1FunctionKey + i)).map(Character.init) ?? " "))
    }
    return m
}()

// "cmd+esc", "ctrl+opt+p"...
func parseHotKey(_ s: String) -> HotKey? {
    var key: (code: Int, equiv: String)?
    var mods = 0
    var mask: NSEvent.ModifierFlags = []
    for part in s.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        switch part {
        case "cmd", "command", "⌘": mods |= cmdKey; mask.insert(.command)
        case "ctrl", "control", "⌃": mods |= controlKey; mask.insert(.control)
        case "opt", "option", "alt", "⌥": mods |= optionKey; mask.insert(.option)
        case "shift", "⇧": mods |= shiftKey; mask.insert(.shift)
        default:
            guard let k = keyCodes[part] else { return nil }
            key = k
        }
    }
    guard let key else { return nil }
    return HotKey(code: UInt32(key.code), carbonMods: UInt32(mods), equivalent: key.equiv, mask: mask)
}

// "cmd+esc" → "⌘ esc", para mostrar el atajo.
func hotKeyLabel(_ s: String) -> String {
    let names = ["cmd": "⌘", "command": "⌘", "ctrl": "⌃", "control": "⌃", "opt": "⌥", "option": "⌥", "alt": "⌥",
                 "shift": "⇧", "esc": "esc", "escape": "esc", "space": "espacio", "return": "↩", "enter": "↩", "tab": "⇥"]
    let parts = s.lowercased().split(separator: "+").map { names[$0.trimmingCharacters(in: .whitespaces)] ?? $0.uppercased() }
    // Las teclas con nombre van separadas: "⌘ esc", "⌃⌥P".
    return parts.reduce("") { out, p in out + (p.count > 1 && !out.isEmpty ? " " : "") + p }
}

// Duración corta para el eyebrow: "20 s", "5 min", "1:30".
func span(_ s: Int) -> String { s < 60 ? "\(s) s" : s % 60 == 0 ? "\(s / 60) min" : clock(s) }

// MARK: - Aviso a pantalla completa

// Ventana sin bordes que igual puede recibir teclado (para el Esc).
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// Pantalla de pausa (componente BreakScreen del design system): eyebrow, instrucción,
// cuenta regresiva grande, barra de progreso y, si la config lo permite, posponer y saltar.
// Con seconds = 0 es la espera de Claude: cuenta hacia arriba, sin barra.
final class BreakOverlay {
    var eyebrow = ""
    var titleText = ""
    var subText = ""
    var hint: String?     // línea al pie (atajo para salir de la espera)
    var seconds = 0       // 0 = sin cuenta regresiva
    var rings = 0
    var sound = ""
    var endSound = ""
    var opacity = 0.94
    var allowSkip = true
    var snoozeTitle: String?  // nil = sin botón de posponer
    private var windows: [NSWindow] = []
    private var timers: [NSTextField] = []
    private var bars: [ProgressBar] = []
    private var timer: Timer?
    private var soundTimer: Timer?
    private var escMonitor: Any?
    private var remaining = 0
    private var elapsed = 0
    var onFinish: (() -> Void)?
    var onSnooze: (() -> Void)?
    var isShowing: Bool { !windows.isEmpty }

    func configure(_ c: BreakConfig, _ cfg: Config, eyebrow: String) {
        self.eyebrow = eyebrow
        titleText = c.title
        subText = c.sub
        seconds = c.duration
        rings = c.rings
        sound = c.sound
        endSound = cfg.endSound
        opacity = cfg.opacity
        allowSkip = cfg.allowSkip
    }

    func show() {
        remaining = seconds
        elapsed = 0
        for screen in NSScreen.screens {
            // Con `screen:` el contentRect es relativo a esa pantalla: pasarle screen.frame (global)
            // manda la ventana fuera de las pantallas secundarias. Se crea en el origen y se ubica después.
            let w = KeyWindow(contentRect: NSRect(origin: .zero, size: screen.frame.size), styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = Palette.restGround.withAlphaComponent(opacity)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = content(screen.frame)
            w.alphaValue = reduceMotion ? 1 : 0
            w.orderFrontRegardless()
            if !reduceMotion {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                    w.animator().alphaValue = 1
                }
            }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        // Esc cierra el aviso (por si estás en una llamada)
        if allowSkip {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.finish(); return nil }
                return event
            }
        }
        update()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.seconds == 0 {
                self.elapsed += 1
                self.update()
                return
            }
            self.remaining -= 1
            if self.remaining <= 0 { self.finish() } else { self.update() }
        }

        guard rings > 0 else { return }
        play(sound)
        soundTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            play(self?.sound ?? "")
        }
        // suena `rings` veces y para
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(rings - 1) * 2 + 0.5) { [weak self] in
            self?.soundTimer?.invalidate()
        }
    }

    // Lo que se ve en cada pantalla.
    func content(_ frame: NSRect) -> NSView {
        let top = label(eyebrow.uppercased(), .systemFont(ofSize: 13, weight: .semibold), Palette.restMuted, kern: 1.1)
        let title = label(titleText, .systemFont(ofSize: 40, weight: .semibold), Palette.restInk)
        let sub = label(subText, .systemFont(ofSize: 19), Palette.restMuted)
        let countUp = seconds == 0
        let count = label("", .monospacedDigitSystemFont(ofSize: countUp ? 96 : 128, weight: .thin),
                          countUp ? Palette.restMuted : Palette.restInk)
        timers.append(count)

        var views: [NSView] = [top, title, sub, count]
        if !countUp {
            let bar = ProgressBar()
            bars.append(bar)
            views.append(bar)
        }
        var buttons: [NSView] = []
        if let t = snoozeTitle {
            buttons.append(PillButton(t, style: .secondary, onRest: true, large: true) { [weak self] in self?.snooze() })
        }
        if allowSkip && !countUp {
            buttons.append(PillButton("Saltar", key: "esc", style: .quiet, onRest: true, large: true) { [weak self] in self?.finish() })
        }
        if !buttons.isEmpty {
            let row = NSStackView(views: buttons)
            row.orientation = .horizontal
            row.spacing = Space.s4
            views.append(row)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Space.s2
        stack.setCustomSpacing(Space.s3, after: top)
        stack.setCustomSpacing(Space.s12, after: sub)
        stack.setCustomSpacing(Space.s6, after: count)
        if let bar = bars.last, !countUp { stack.setCustomSpacing(Space.s16, after: bar) }
        if countUp { stack.setCustomSpacing(Space.s16, after: count) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let v = NSView(frame: frame)
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        if let hint {
            let h = label(hint, .systemFont(ofSize: 13), Palette.restMuted)
            h.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(h)
            NSLayoutConstraint.activate([
                h.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                h.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -Space.s8),
            ])
        }
        return v
    }

    private func update() {
        if seconds == 0 {
            timers.forEach { $0.stringValue = clock(elapsed) }
            return
        }
        timers.forEach { $0.stringValue = clock(remaining) }
        bars.forEach { $0.fraction = CGFloat(seconds - remaining) / CGFloat(seconds) }
    }

    private func close() -> Bool {
        guard !windows.isEmpty else { return false }
        timer?.invalidate()
        soundTimer?.invalidate()
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        let closing = windows
        windows.removeAll()
        timers.removeAll()
        bars.removeAll()
        if reduceMotion {
            closing.forEach { $0.orderOut(nil) }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                closing.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { closing.forEach { $0.orderOut(nil) } })
        }
        return true
    }

    @objc func finish() {
        guard close() else { return }
        play(endSound)
        onFinish?()
    }

    @objc private func snooze() {
        guard close() else { return }
        onSnooze?()
    }
}

// MARK: - Banner

// Cartelito arriba al centro que no roba el foco (componente Banner del design system):
// ícono de estado, texto y botones. Lo que va después del primer " · " sale en gris.
final class Banner: NSObject {
    private var panel: NSPanel?
    private let main = label("", .systemFont(ofSize: 14, weight: .medium), Palette.ink)
    private let detail = label("", .systemFont(ofSize: 14, weight: .medium), Palette.inkMuted)
    var isShowing: Bool { panel != nil }

    func show(_ text: String, symbol name: String, tint: NSColor? = nil,
              buttons: [(String, PillButton.Style, () -> Void)]) {
        hide()
        setLabels(text)
        main.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        detail.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let icon = NSImageView(image: symbol(name, size: 15, color: tint) ?? NSImage())
        icon.contentTintColor = Palette.ink

        let text = NSStackView(views: [icon, main, detail])
        text.orientation = .horizontal
        text.spacing = Space.s2
        var views: [NSView] = [text]
        if !buttons.isEmpty {
            let row = NSStackView(views: buttons.map { b in
                PillButton(b.0, style: b.1, onRest: false) { [weak self] in
                    guard self != nil else { return }
                    b.2()
                }
            })
            row.orientation = .horizontal
            row.spacing = Space.s2
            views.append(row)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = Space.s3 + Space.s2
        stack.edgeInsets = NSEdgeInsets(top: Space.s2, left: Space.s4, bottom: Space.s2,
                                        right: buttons.isEmpty ? Space.s4 : Space.s2)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bg = NSVisualEffectView()
        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            bg.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = bg
        panel = p
        layout()
        p.alphaValue = reduceMotion ? 1 : 0
        p.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                p.animator().alphaValue = 1
            }
        }
    }

    func setText(_ text: String) {
        let before = main.stringValue + detail.stringValue
        setLabels(text)
        if main.stringValue + detail.stringValue != before { layout() }
    }

    private func setLabels(_ text: String) {
        let parts = text.components(separatedBy: " · ")
        main.stringValue = parts[0]
        detail.stringValue = parts.dropFirst().joined(separator: " · ")
        detail.isHidden = detail.stringValue.isEmpty
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func layout() {
        guard let p = panel, let v = p.contentView, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = v.fittingSize
        let vf = screen.visibleFrame
        p.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height - Space.s4,
                          width: size.width, height: size.height), display: true)
    }
}

// MARK: - App

enum Kind: String, Codable { case eye, stand }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var tick: Timer?
    private var fileCfg = Config.load()
    private var cfgDate = Config.modified
    private var remote: SyncSchedule?   // horario del host mientras estás sincronizado
    private var cfg: Config { remote?.apply(to: fileCfg) ?? fileCfg }
    private var sinceEye = 0       // segundos desde la última pausa de vista
    private var sinceStand = 0     // segundos desde la última pausa de pararse
    private var lastFixedSlot: Date?  // último minuto en que disparó el horario fijo (para no repetir)
    private var paused = false
    private var inMeeting = false
    private var pending: Kind?     // pausa que ya tocaba pero espera (reunión o pospuesta)
    private var snoozeLeft = 0     // segundos hasta que vuelve la pausa pospuesta
    private var snoozes = 0        // veces seguidas que se pospuso
    private var warning: Kind?     // cuenta regresiva previa en curso
    private var warnLeft = 0
    private var current: Kind?     // pausa en pantalla
    private var awaitingReturn: Date?  // terminó una pausa y todavía no tocaste nada
    private var inBreak: Bool { warning != nil || current != nil || waitOverlay.isShowing }
    private let eyeOverlay = BreakOverlay()
    private let standOverlay = BreakOverlay()
    private let waitOverlay = BreakOverlay()
    private let warnBanner = Banner()
    private let snoozeBanner = Banner()
    private var hotKey: EventHotKeyRef?
    private let statusInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let problemItem = NSMenuItem(title: "Revisá config.yml", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pausar", action: #selector(togglePause), keyEquivalent: "p")
    private let waitItem = NSMenuItem(title: "Esperar a Claude", action: #selector(toggleWait), keyEquivalent: "")
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?

    private enum SyncState: Equatable { case solo, hosting, joined(String) }
    private var sync = SyncState.solo
    private var host: SyncHost?
    private var guest: Peer?
    private var guestConnected = false
    private var session = SessionClock(eye: 0, stand: 0)
    private let browser = SyncBrowser()
    private let infoBanner = Banner()
    private let syncItem = NSMenuItem(title: "Crear una jam", action: #selector(toggleHosting), keyEquivalent: "")
    private let findItem = NSMenuItem(title: "Unirme a una jam", action: nil, keyEquivalent: "")
    private let leaveItem = NSMenuItem(title: "Salir de la jam", action: #selector(leaveSession), keyEquivalent: "")
    private let syncInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    // pausa://configuracion (lo abre la mini-app "Pausa Configuración" que encuentra Spotlight).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "pausa" && $0.host == "configuracion" }) else { return }
        DispatchQueue.main.async { self.openSettings() }
    }

    // Abrir Pausa cuando ya está corriendo (Spotlight, Finder, Launchpad) abre la Configuración.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // Deja "Pausa Configuración" al lado de Pausa (y la actualiza si cambió de build), así Spotlight
    // la encuentra también en instalaciones desde el .dmg. No toca nada si Pausa corre desde el disco.
    private func installSettingsShortcut() {
        let fm = FileManager.default
        let name = "Pausa Configuración.app"
        let src = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name)")
        let dir = Bundle.main.bundleURL.deletingLastPathComponent()
        let dst = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: src.path), !dir.path.hasPrefix("/Volumes/"),
              !dir.path.contains("AppTranslocation"), fm.isWritableFile(atPath: dir.path) else { return }
        func build(_ u: URL) -> String? { Bundle(url: u)?.infoDictionary?["CFBundleVersion"] as? String }
        guard build(dst) != build(src) || !fm.fileExists(atPath: dst.path) else { return }
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: src, to: dst)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSettingsShortcut()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        let menu = NSMenu()
        menu.addItem(statusInfoItem)
        menu.addItem(problemItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Reiniciar contador", action: #selector(reset), keyEquivalent: "r"))
        menu.addItem(waitItem)
        menu.addItem(.separator())
        menu.addItem(syncInfoItem)
        menu.addItem(syncItem)
        menu.addItem(findItem)
        menu.addItem(leaveItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Configuración…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Acerca de Pausa", action: #selector(about), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Salir de Pausa", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusInfoItem.isEnabled = false
        syncInfoItem.isEnabled = false
        syncInfoItem.image = symbol("person.2")
        problemItem.image = symbol("exclamationmark.triangle", color: Palette.danger)
        findItem.submenu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        installEditMenu()
        browser.onChange = { [weak self] in self?.rebuildFindMenu() }

        eyeOverlay.onFinish = { [weak self] in self?.breakDone(.eye) }
        standOverlay.onFinish = { [weak self] in self?.breakDone(.stand) }
        eyeOverlay.onSnooze = { [weak self] in self?.snooze(.eye) }
        standOverlay.onSnooze = { [weak self] in self?.snooze(.stand) }
        waitOverlay.onFinish = { [weak self] in self?.refresh() }

        // Si la Mac se durmió o se bloqueó, ya estuviste lejos: reiniciar.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(wake), name: .init("com.apple.screenIsUnlocked"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(claudeDone), name: claudeDoneNotification, object: nil)
        installHotKeyHandler()

        restoreCounters()
        applyConfig()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(tick!, forMode: .common)
    }

    // MARK: Config

    private func conf(_ k: Kind) -> BreakConfig { k == .eye ? cfg.eye : cfg.stand }
    private func overlay(_ k: Kind) -> BreakOverlay { k == .eye ? eyeOverlay : standOverlay }

    private func reloadConfigIfChanged() {
        let d = Config.modified
        guard d != cfgDate else { return }
        cfgDate = d
        fileCfg = Config.load()
        applyConfig()
    }

    private func applyConfig() {
        eyeOverlay.configure(cfg.eye, cfg, eyebrow: "Pausa corta · \(span(cfg.eye.duration))")
        standOverlay.configure(cfg.stand, cfg, eyebrow: "Pausa larga · \(span(cfg.stand.duration))")
        waitOverlay.eyebrow = "En espera"
        waitOverlay.hint = "\(hotKeyLabel(cfg.claudeHotKey)) para volver"
        waitOverlay.titleText = cfg.claudeTitle
        waitOverlay.subText = cfg.claudeSub
        waitOverlay.endSound = cfg.endSound
        waitOverlay.opacity = cfg.opacity
        waitOverlay.allowSkip = true  // sin cuenta regresiva: siempre tiene que poder cerrarse

        // Si se apagó la pausa que estaba esperando, se descarta.
        if let k = pending, !conf(k).enabled { pending = nil; snoozeLeft = 0; snoozes = 0 }
        if !cfg.snoozeEnabled { snoozeLeft = 0 }

        problemItem.isHidden = cfg.problems.isEmpty
        let sub = NSMenu()
        cfg.problems.forEach { sub.addItem(NSMenuItem(title: $0, action: nil, keyEquivalent: "")) }
        problemItem.submenu = sub

        registerHotKey()
        settingsModel?.cfg = fileCfg
        refresh()
    }

    // MARK: Ciclo

    private func step() {
        defer { saveCounters() }
        reloadConfigIfChanged()
        if sync == .hosting { hostTick() }  // el reloj del grupo corre aunque vos estés en pausa
        guard !paused else { return }
        if let k = warning {
            warnLeft -= 1
            if warnLeft <= 0 { beginBreak(k) } else { warnBanner.setText(warnText(k)) }
            refresh()
            return
        }
        guard !inBreak else { return }
        if sync != .solo || !cfg.resumeOnActivity { awaitingReturn = nil }
        if let end = awaitingReturn {
            // Sin mouse ni teclado desde que terminó la pausa: seguís afuera, el contador no corre.
            guard idleSeconds() < Date().timeIntervalSince(end) else { refresh(); return }
            awaitingReturn = nil
        }
        if snoozeLeft > 0 { snoozeLeft -= 1 }
        // En reunión el contador sigue, pero los avisos esperan a que cortes.
        inMeeting = cfg.waitForMeetings && micInUse()
        // Sincronizado, los contadores y las pausas los marca el grupo (ver sessionBreak).
        if sync == .solo {
            sinceEye += 1
            sinceStand += 1
            if cfg.fixedSchedule {
                // Horario fijo: dispara según el minuto del reloj, no desde la última pausa.
                if let k = fixedDue(), k == .stand || pending == nil { pending = k }
            } else if cfg.stand.enabled && sinceStand >= cfg.stand.every {
                pending = .stand  // la de pararse le gana a la de vista
            } else if pending == nil && cfg.eye.enabled && sinceEye >= cfg.eye.every {
                pending = .eye
            }
        }
        if let k = pending, snoozeLeft == 0, !inMeeting { announce(k) }
        refresh()
    }

    // Los contadores sobreviven a un reinicio de la app (un build nuevo, por ejemplo).
    // El rato que estuvo cerrada cuenta como pantalla; si fueron más de 5 min, se toma como descanso.
    private func saveCounters() {
        let d = UserDefaults.standard
        d.set(sinceEye, forKey: "sinceEye")
        d.set(sinceStand, forKey: "sinceStand")
        d.set(Date().timeIntervalSince1970, forKey: "countersSavedAt")
    }

    private func restoreCounters() {
        let d = UserDefaults.standard
        guard let at = d.object(forKey: "countersSavedAt") as? Double else { return }
        let gap = Int(Date().timeIntervalSince1970 - at)
        guard (0..<5 * 60).contains(gap) else { return }
        sinceEye = d.integer(forKey: "sinceEye") + gap
        sinceStand = d.integer(forKey: "sinceStand") + gap
    }

    // Horario fijo: ¿toca una pausa en este minuto del reloj? Dispara una sola vez por minuto.
    private func fixedDue() -> Kind? {
        let cal = Calendar.current
        let now = Date()
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        guard let minute = c.minute, let slot = cal.date(from: c), slot != lastFixedSlot else { return nil }
        var kind: Kind?
        if cfg.stand.enabled && cfg.fixedStandMinutes.contains(minute) { kind = .stand }  // la larga gana
        else if cfg.eye.enabled && cfg.fixedEyeMinutes.contains(minute) { kind = .eye }
        if kind != nil { lastFixedSlot = slot }
        return kind
    }

    // Próxima pausa del horario fijo y cuántos segundos faltan (para la barra de menú).
    private func nextFixed() -> (Kind, Int)? {
        var targets: [(Int, Kind)] = []
        if cfg.stand.enabled { targets += cfg.fixedStandMinutes.map { ($0, .stand) } }
        if cfg.eye.enabled { targets += cfg.fixedEyeMinutes.map { ($0, .eye) } }
        guard !targets.isEmpty else { return nil }
        let cal = Calendar.current
        let now = Date()
        let m = cal.component(.minute, from: now)
        let s = cal.component(.second, from: now)
        var best: (Kind, Int)?
        for (tm, k) in targets {
            var secs = ((tm - m + 60) % 60) * 60 - s
            if secs <= 0 { secs += 3600 }  // este minuto ya pasó: la próxima es dentro de una hora
            if secs < best?.1 ?? .max { best = (k, secs) }
        }
        return best
    }

    private var canSnooze: Bool { cfg.snoozeEnabled && (cfg.snoozeMax == 0 || snoozes < cfg.snoozeMax) }

    private var snoozeLabel: String {
        let s = cfg.snoozeSeconds
        return s % 60 == 0 ? "Posponer \(s / 60) min" : "Posponer \(clock(s))"
    }

    private func warnText(_ k: Kind) -> String {
        conf(k).warningText.replacingOccurrences(of: "{s}", with: "\(warnLeft)")
    }

    // Cuenta regresiva arriba antes de tapar la pantalla.
    private func announce(_ k: Kind) {
        let c = conf(k)
        guard c.warning > 0 else { beginBreak(k); return }
        warning = k
        warnLeft = c.warning
        var buttons: [(String, PillButton.Style, () -> Void)] = [("Empezar ahora", .quiet, { [weak self] in self?.beginBreak(k) })]
        if canSnooze { buttons.insert((snoozeLabel, .secondary, { [weak self] in self?.snooze(k) }), at: 0) }
        warnBanner.show(warnText(k), symbol: icon(k), buttons: buttons)
        refresh()
    }

    private func beginBreak(_ k: Kind) {
        warning = nil
        warnBanner.hide()
        current = k
        let o = overlay(k)
        o.snoozeTitle = canSnooze ? snoozeLabel : nil
        o.show()
        refresh()
    }

    private func snooze(_ k: Kind) {
        warning = nil
        warnBanner.hide()
        current = nil
        pending = k
        snoozes += 1
        snoozeLeft = cfg.snoozeSeconds
        refresh()
    }

    private func breakDone(_ k: Kind) {
        current = nil
        pending = nil
        snoozes = 0
        snoozeLeft = 0
        sinceEye = 0
        if k == .stand { sinceStand = 0 }
        // Sincronizado manda el reloj del grupo, así que no tiene sentido esperar.
        if cfg.resumeOnActivity && sync == .solo { awaitingReturn = Date() }
        refresh()
    }

    private func cancelWarning() {
        guard warning != nil else { return }
        warning = nil
        warnBanner.hide()
    }

    // MARK: Barra de menú

    private func refresh() {
        pauseItem.title = paused ? "Reanudar" : "Pausar"
        waitItem.isHidden = !cfg.claudeEnabled
        updateSnoozeBanner()
        updateSyncMenu()
        let st = status()
        statusInfoItem.title = st.long
        statusInfoItem.image = symbol(st.icon, color: st.tint)
        var img = symbol(st.icon, size: 13, color: sync == .solo ? st.tint : nil)
        if sync != .solo, let i = img, let people = symbol("person.2", size: 13) { img = joined(people, i) }
        statusItem.button?.image = img
        statusItem.button?.title = st.short
        statusItem.button?.imagePosition = st.short.isEmpty ? .imageOnly : .imageLeading
    }

    private func icon(_ k: Kind) -> String { k == .stand ? "figure.walk" : "eye" }
    private func name(_ k: Kind) -> String { k == .stand ? "Pausa larga" : "Pausa corta" }

    // Estado para la barra de menú (componente MenuBarItem) y la primera línea del menú.
    private func status() -> (icon: String, short: String, long: String, tint: NSColor?) {
        if paused { return ("pause", "", "Pausado", nil) }
        if waitOverlay.isShowing { return ("hourglass", "", "Esperando a Claude", nil) }
        if let k = warning { return (icon(k), "\(warnLeft)", "\(name(k)) en \(warnLeft)", nil) }
        if let k = current { return (icon(k), "ahora", "\(name(k)) ahora", nil) }
        if inMeeting && pending != nil && snoozeLeft == 0 { return ("phone", "después", "En reunión · la pausa espera", nil) }
        if awaitingReturn != nil {
            return ("cursorarrow.motionlines", "", "Esperando que vuelvas · arranca al mover el mouse", nil)
        }
        if snoozeLeft > 0 {
            return ("moon.zzz", cfg.showCountdown ? clock(snoozeLeft) : "", "Pospuesta · vuelve en \(clock(snoozeLeft))", Palette.amber)
        }
        var next: (Kind, Int)?
        if cfg.fixedSchedule {
            next = nextFixed()
        } else {
            if cfg.eye.enabled { next = (.eye, cfg.eye.every - sinceEye) }
            if cfg.stand.enabled, cfg.stand.every - sinceStand <= next?.1 ?? .max {
                next = (.stand, cfg.stand.every - sinceStand)
            }
        }
        guard let (k, left) = next else { return ("eye.slash", "", "Todo apagado", nil) }
        let t = clock(max(left, 0))
        let long = "\(name(k)) en \(t)"
        if inMeeting { return ("phone", cfg.showCountdown ? t : "", "En reunión · " + long.lowercased(), nil) }
        return (icon(k), cfg.showCountdown ? t : "", long, nil)
    }

    private func updateSnoozeBanner() {
        guard cfg.snoozeBanner, snoozeLeft > 0, !paused, !inBreak else { snoozeBanner.hide(); return }
        let text = cfg.snoozeText.replacingOccurrences(of: "{t}", with: clock(snoozeLeft))
        if snoozeBanner.isShowing {
            snoozeBanner.setText(text)
        } else {
            snoozeBanner.show(text, symbol: "moon.zzz", tint: Palette.amber,
                              buttons: [("Empezar ahora", .primary, { [weak self] in self?.startPendingNow() })])
        }
    }

    private func startPendingNow() {
        guard let k = pending else { return }
        snoozeLeft = 0
        beginBreak(k)
    }

    // MARK: Sincronización

    private var sessionName: String { "Jam de \(Host.current().localizedName ?? NSFullUserName())" }

    private func hostTick() {
        let s = SyncSchedule(fileCfg)
        if let k = session.tick(s) {
            host?.broadcast(.breakStarts(k))
            sessionBreak(k)
        }
        host?.broadcast(.state(s, session))
        sinceEye = max(session.eye, 0)
        sinceStand = max(session.stand, 0)
    }

    // Arranca una pausa del grupo. Si estás en reunión o con una pospuesta, queda pendiente
    // como cualquier otra y el ciclo normal la larga cuando puedas.
    private func sessionBreak(_ k: Kind) {
        guard !paused, !inBreak else { return }
        if pending == nil || k == .stand { pending = k }
        if snoozeLeft == 0 && !inMeeting { announce(k) }
    }

    private func received(_ m: SyncMessage) {
        switch m.type {
        case "state":
            guard let s = m.schedule else { return }
            guestConnected = true
            if s != remote { remote = s; applyConfig() }
            sinceEye = max(m.eye ?? 0, 0)
            sinceStand = max(m.stand ?? 0, 0)
            refresh()
        case "break":
            if let k = m.kind { sessionBreak(k) }
        default:
            break
        }
    }

    @objc private func toggleHosting() {
        if sync == .hosting { stopHosting(); return }
        let h = SyncHost()
        h.onChange = { [weak self] in self?.refresh() }
        h.onFail = { [weak self] in
            self?.stopHosting()
            self?.flash("No se pudo crear la jam en la red")
        }
        do {
            try h.start(name: sessionName)
        } catch {
            flash("No se pudo crear la jam: \(error.localizedDescription)")
            return
        }
        session = SessionClock(eye: sinceEye, stand: sinceStand)
        host = h
        sync = .hosting
        refresh()
    }

    private func stopHosting() {
        host?.stop()
        host = nil
        sync = .solo
        refresh()
    }

    @objc private func joinFound(_ sender: NSMenuItem) {
        guard sender.tag < browser.results.count else { return }
        let r = browser.results[sender.tag]
        let name = serviceName(r)
        let p = Peer(NWConnection(to: r.endpoint, using: .tcp))
        p.onMessage = { [weak self] m in self?.received(m) }
        p.onClose = { [weak self] in
            self?.endGuest()
            self?.flash("Se cortó la conexión con \(name)")
        }
        // Sin el permiso de Red local la conexión queda esperando para siempre: cortar y avisar.
        let giveUp = { [weak self, weak p] in
            guard let self, let p, self.guest === p, !self.guestConnected else { return }
            self.leaveSession()
            self.flash("No se pudo entrar a la jam. · Prendé Pausa en Ajustes del Sistema › Privacidad y seguridad › Red local.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { giveUp() }
        p.start()
        p.send(.hello(NSFullUserName()))
        guest = p
        guestConnected = false
        sync = .joined(name)
        refresh()
    }

    @objc private func leaveSession() {
        guest?.onClose = nil
        guest?.conn.cancel()
        endGuest()
    }

    // De vuelta a tu horario, siguiendo desde donde iba el grupo.
    private func endGuest() {
        guest = nil
        sync = .solo
        remote = nil
        applyConfig()
    }

    private func flash(_ text: String) {
        infoBanner.show(text, symbol: "exclamationmark.triangle", tint: Palette.danger, buttons: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.infoBanner.hide() }
    }

    private func updateSyncMenu() {
        syncItem.title = sync == .hosting ? "Terminar la jam" : "Crear una jam"
        syncItem.isHidden = !(sync == .solo || sync == .hosting)
        findItem.isHidden = sync != .solo
        leaveItem.isHidden = { if case .joined = sync { return false }; return true }()
        switch sync {
        case .solo:
            syncInfoItem.isHidden = true
        case .hosting:
            let names = host?.peers.map(\.name).filter { !$0.isEmpty } ?? []
            let n = host?.peers.count ?? 0
            syncInfoItem.title = n == 0 ? "Tu jam · esperando a que se unan"
                : "Tu jam con \(n): " + (names.isEmpty ? "\(n) conectados" : names.joined(separator: ", "))
            syncInfoItem.isHidden = false
        case .joined(let name):
            syncInfoItem.title = guestConnected ? "Estás en: \(name)" : "Entrando a \(name)…"
            syncInfoItem.isHidden = false
        }
    }

    // Busca sesiones solo mientras el menú está abierto.
    func menuWillOpen(_ menu: NSMenu) {
        guard sync == .solo else { return }
        browser.start()
        rebuildFindMenu()
    }

    func menuDidClose(_ menu: NSMenu) { browser.stop() }

    private func rebuildFindMenu() {
        guard let m = findItem.submenu else { return }
        m.removeAllItems()
        if browser.results.isEmpty {
            let it = NSMenuItem(title: "Buscando jams en la red…", action: nil, keyEquivalent: "")
            it.isEnabled = false
            m.addItem(it)
        }
        for (i, r) in browser.results.enumerated() {
            let it = NSMenuItem(title: serviceName(r), action: #selector(joinFound(_:)), keyEquivalent: "")
            it.tag = i
            it.target = self
            m.addItem(it)
        }
    }

    // MARK: Claude

    // Atajo global (Carbon no necesita permiso de Accesibilidad)
    private func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggleWait() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func registerHotKey() {
        if let h = hotKey { UnregisterEventHotKey(h); hotKey = nil }
        waitItem.keyEquivalent = ""
        guard cfg.claudeEnabled else { return }
        guard let hk = parseHotKey(cfg.claudeHotKey) else {
            problemItem.isHidden = false
            problemItem.submenu?.addItem(NSMenuItem(title: "Atajo inválido: \(cfg.claudeHotKey)", action: nil, keyEquivalent: ""))
            return
        }
        waitItem.keyEquivalent = hk.equivalent
        waitItem.keyEquivalentModifierMask = hk.mask
        RegisterEventHotKey(hk.code, hk.carbonMods, EventHotKeyID(signature: 0x5041_5553, id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    @objc private func toggleWait() {
        if waitOverlay.isShowing { waitOverlay.finish(); return }
        guard cfg.claudeEnabled, !inBreak else { return }
        waitOverlay.show()
        refresh()
    }

    @objc private func claudeDone() {
        if waitOverlay.isShowing {
            waitOverlay.finish()  // suena el sonido de fin
        } else {
            play(cfg.claudeDoneSound)
        }
    }

    // MARK: Menú

    @objc private func togglePause() {
        paused.toggle()
        if paused { cancelWarning() }  // al reanudar, la pausa pendiente vuelve a avisar
        refresh()
    }
    // Panel estándar: toma el ícono, el nombre y la versión del Info.plist.
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(fileCfg)
            model.test = { [weak self] k in if self?.inBreak == false { self?.announce(k) } }
            settingsModel = model
            settingsWindow = makeSettingsWindow(model)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // Sin menú Edición, Cmd+C / Cmd+V no andan en los campos de texto de la configuración.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Cerrar ventana", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let main = NSMenu()
        main.addItem(NSMenuItem())  // menú de la app
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc private func wake() { if cfg.resetOnWake { reset() } }
    @objc private func reset() {
        sinceEye = 0
        sinceStand = 0
        pending = nil
        snoozeLeft = 0
        snoozes = 0
        awaitingReturn = nil
        cancelWarning()
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
