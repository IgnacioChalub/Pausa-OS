import Cocoa
import Carbon
import CoreAudio

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

// MARK: - Aviso a pantalla completa

// Ventana sin bordes que igual puede recibir teclado (para el Esc).
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class BreakOverlay {
    var titleText = ""
    var subText = ""
    var seconds = 0       // 0 = sin cuenta regresiva
    var rings = 0
    var sound = ""
    var endSound = ""
    var opacity = 0.88
    var allowSkip = true
    var snoozeTitle: String?  // nil = sin botón de posponer
    private var windows: [NSWindow] = []
    private var labels: [NSTextField] = []
    private var timer: Timer?
    private var soundTimer: Timer?
    private var escMonitor: Any?
    private var remaining = 0
    var onFinish: (() -> Void)?
    var onSnooze: (() -> Void)?
    var isShowing: Bool { !windows.isEmpty }

    func configure(_ c: BreakConfig, _ cfg: Config) {
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
        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = NSColor.black.withAlphaComponent(opacity)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let title = NSTextField(labelWithString: titleText)
            title.font = .systemFont(ofSize: 64, weight: .bold)
            title.textColor = .white
            let sub = NSTextField(labelWithString: subText)
            sub.font = .systemFont(ofSize: 26)
            sub.textColor = NSColor.white.withAlphaComponent(0.75)
            let count = NSTextField(labelWithString: "")
            count.font = .monospacedDigitSystemFont(ofSize: 48, weight: .medium)
            count.textColor = .white
            labels.append(count)

            var buttons: [NSView] = []
            if let t = snoozeTitle {
                buttons.append(button(t, #selector(snooze)))
            }
            if allowSkip {
                buttons.append(button("Saltar (Esc)", #selector(finish)))
            }
            let row = NSStackView(views: buttons)
            row.orientation = .horizontal
            row.spacing = 16

            let stack = NSStackView(views: [title, sub, count, row])
            stack.orientation = .vertical
            stack.spacing = 24
            stack.setCustomSpacing(60, after: count)
            stack.translatesAutoresizingMaskIntoConstraints = false
            let v = NSView(frame: screen.frame)
            v.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            w.contentView = v
            w.alphaValue = 0
            w.orderFrontRegardless()
            w.animator().alphaValue = 1
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

        if seconds > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.finish() } else { self.update() }
            }
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

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        return b
    }

    private func update() {
        guard seconds > 0 else { return }
        labels.forEach { $0.stringValue = clock(remaining) }
    }

    private func close() -> Bool {
        guard !windows.isEmpty else { return false }
        timer?.invalidate()
        soundTimer?.invalidate()
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        labels.removeAll()
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

// Cartelito arriba al centro que no roba el foco: cuenta regresiva y "pausa pospuesta".
final class Banner: NSObject {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var actions: [() -> Void] = []
    var isShowing: Bool { panel != nil }

    func show(_ text: String, buttons: [(String, () -> Void)]) {
        hide()
        label.stringValue = text
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        actions = buttons.map(\.1)
        let views: [NSView] = [label] + buttons.enumerated().map { i, b in
            let btn = NSButton(title: b.0, target: self, action: #selector(tapped(_:)))
            btn.bezelStyle = .rounded
            btn.tag = i
            return btn
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
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
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.animator().alphaValue = 1
    }

    func setText(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        layout()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        actions = []
    }

    private func layout() {
        guard let p = panel, let v = p.contentView, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = v.fittingSize
        let vf = screen.visibleFrame
        p.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 12,
                          width: size.width, height: size.height), display: true)
    }

    @objc private func tapped(_ sender: NSButton) {
        let action = actions[sender.tag]
        action()
    }
}

// MARK: - App

enum Kind { case eye, stand }

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var tick: Timer?
    private var cfg = Config.load()
    private var cfgDate = Config.modified
    private var sinceEye = 0       // segundos desde la última pausa de vista
    private var sinceStand = 0     // segundos desde la última pausa de pararse
    private var paused = false
    private var inMeeting = false
    private var pending: Kind?     // pausa que ya tocaba pero espera (reunión o pospuesta)
    private var snoozeLeft = 0     // segundos hasta que vuelve la pausa pospuesta
    private var snoozes = 0        // veces seguidas que se pospuso
    private var warning: Kind?     // cuenta regresiva previa en curso
    private var warnLeft = 0
    private var current: Kind?     // pausa en pantalla
    private var inBreak: Bool { warning != nil || current != nil || waitOverlay.isShowing }
    private let eyeOverlay = BreakOverlay()
    private let standOverlay = BreakOverlay()
    private let waitOverlay = BreakOverlay()
    private let warnBanner = Banner()
    private let snoozeBanner = Banner()
    private var hotKey: EventHotKeyRef?
    private let problemItem = NSMenuItem(title: "⚠️ Revisá config.yml", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pausar", action: #selector(togglePause), keyEquivalent: "p")
    private let waitItem = NSMenuItem(title: "Esperar a Claude", action: #selector(toggleWait), keyEquivalent: "")
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let menu = NSMenu()
        menu.addItem(problemItem)
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Reiniciar contador", action: #selector(reset), keyEquivalent: "r"))
        menu.addItem(waitItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Configuración…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Probar aviso de vista", action: #selector(testEye), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Probar aviso de pararse", action: #selector(testStand), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
        installEditMenu()

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
        cfg = Config.load()
        applyConfig()
    }

    private func applyConfig() {
        eyeOverlay.configure(cfg.eye, cfg)
        standOverlay.configure(cfg.stand, cfg)
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
        settingsModel?.cfg = cfg
        refresh()
    }

    // MARK: Ciclo

    private func step() {
        reloadConfigIfChanged()
        guard !paused else { return }
        if let k = warning {
            warnLeft -= 1
            if warnLeft <= 0 { beginBreak(k) } else { warnBanner.setText(warnText(k)) }
            refresh()
            return
        }
        guard !inBreak else { return }
        sinceEye += 1
        sinceStand += 1
        if snoozeLeft > 0 { snoozeLeft -= 1 }
        // En reunión el contador sigue, pero los avisos esperan a que cortes.
        inMeeting = cfg.waitForMeetings && micInUse()
        if cfg.stand.enabled && sinceStand >= cfg.stand.every {
            pending = .stand  // la de pararse le gana a la de vista
        } else if pending == nil && cfg.eye.enabled && sinceEye >= cfg.eye.every {
            pending = .eye
        }
        if let k = pending, snoozeLeft == 0, !inMeeting { announce(k) }
        refresh()
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
        var buttons: [(String, () -> Void)] = [("Empezar ya", { [weak self] in self?.beginBreak(k) })]
        if canSnooze { buttons.insert((snoozeLabel, { [weak self] in self?.snooze(k) }), at: 0) }
        warnBanner.show(warnText(k), buttons: buttons)
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
        statusItem.button?.title = statusTitle()
    }

    private func statusTitle() -> String {
        if paused { return "⏸" }
        if waitOverlay.isShowing { return "☕" }
        if let k = warning { return "\(k == .stand ? "🧍" : "👀") \(warnLeft)" }
        if let k = current { return k == .stand ? "🧍 ahora" : "👀 ahora" }
        if inMeeting && pending != nil && snoozeLeft == 0 { return "📞 después" }
        if snoozeLeft > 0 { return cfg.showCountdown ? "💤 \(clock(snoozeLeft))" : "💤" }
        var next: (Kind, Int)?
        if cfg.eye.enabled { next = (.eye, cfg.eye.every - sinceEye) }
        if cfg.stand.enabled, cfg.stand.every - sinceStand <= next?.1 ?? .max {
            next = (.stand, cfg.stand.every - sinceStand)
        }
        guard let (k, left) = next else { return "😌" }  // todo apagado
        let icon = inMeeting ? "📞" : (k == .stand ? "🧍" : "👁")
        return cfg.showCountdown ? "\(icon) \(clock(max(left, 0)))" : icon
    }

    private func updateSnoozeBanner() {
        guard cfg.snoozeBanner, snoozeLeft > 0, !paused, !inBreak else { snoozeBanner.hide(); return }
        let text = cfg.snoozeText.replacingOccurrences(of: "{t}", with: clock(snoozeLeft))
        if snoozeBanner.isShowing {
            snoozeBanner.setText(text)
        } else {
            snoozeBanner.show(text, buttons: [("Empezar ahora", { [weak self] in self?.startPendingNow() })])
        }
    }

    private func startPendingNow() {
        guard let k = pending else { return }
        snoozeLeft = 0
        beginBreak(k)
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
    @objc private func openSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(cfg)
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
        cancelWarning()
        refresh()
    }
    @objc private func testEye() { if !inBreak { announce(.eye) } }
    @objc private func testStand() { if !inBreak { announce(.stand) } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
