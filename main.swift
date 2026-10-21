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

// MARK: - Config

let eyeInterval = 20 * 60        // cada 20 min: mirar a lo lejos
let standInterval = 60 * 60      // cada 1 hora: pararse
let eyeBreakSeconds = 20         // duración del aviso de vista
let standBreakSeconds = 5 * 60   // duración de la pausa para pararse

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

// MARK: - Aviso a pantalla completa

// Ventana sin bordes que igual puede recibir teclado (para el Esc).
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class BreakOverlay {
    private let titleText: String
    private let subText: String
    private let seconds: Int
    private let rings: Int
    private var windows: [NSWindow] = []
    private var labels: [NSTextField] = []
    private var timer: Timer?
    private var soundTimer: Timer?
    private var escMonitor: Any?
    private var remaining = 0
    var onFinish: (() -> Void)?
    var isShowing: Bool { !windows.isEmpty }

    init(title: String, sub: String, seconds: Int, rings: Int) {
        titleText = title
        subText = sub
        self.seconds = seconds
        self.rings = rings
    }

    func show() {
        remaining = seconds
        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = NSColor.black.withAlphaComponent(0.88)
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

            let skip = NSButton(title: "Saltar (Esc)", target: self, action: #selector(finish))
            skip.bezelStyle = .rounded
            skip.controlSize = .large

            let stack = NSStackView(views: [title, sub, count, skip])
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
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(); return nil }
            return event
        }
        update()

        if seconds > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.finish() } else { self.update() }
            }
        }

        guard rings > 0 else { return }  // seconds == 0 implica sin cuenta regresiva
        NSSound(named: "Sosumi")?.play()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            NSSound(named: "Sosumi")?.play()
        }
        // suena `rings` veces y para
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(rings - 1) * 2 + 0.5) { [weak self] in
            self?.soundTimer?.invalidate()
        }
    }

    private func update() {
        guard seconds > 0 else { return }
        let s = String(format: "%d:%02d", remaining / 60, remaining % 60)
        labels.forEach { $0.stringValue = s }
    }

    @objc func finish() {
        guard !windows.isEmpty else { return }
        timer?.invalidate()
        soundTimer?.invalidate()
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        labels.removeAll()
        NSSound(named: "Hero")?.play()
        onFinish?()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var tick: Timer?
    private var elapsed = 0
    private var paused = false
    private var inBreak = false
    private var inMeeting = false
    private var pendingEye = false  // aviso de vista que quedó pendiente por una reunión
    private let eyeOverlay = BreakOverlay(title: "👀  Mirá algo lejos",
                                          sub: "Algo a unos 6 metros, sin mirar la pantalla.",
                                          seconds: eyeBreakSeconds, rings: 1)
    private let overlay = BreakOverlay(title: "🧍  Pará. Levantate.",
                                       sub: "Caminá, estirate, tomá agua.",
                                       seconds: standBreakSeconds, rings: 3)
    private let waitOverlay = BreakOverlay(title: "☕  Esperando a Claude…",
                                           sub: "Mirá a otro lado. Te aviso cuando responda.",
                                           seconds: 0, rings: 0)
    private var hotKey: EventHotKeyRef?
    private let pauseItem = NSMenuItem(title: "Pausar", action: #selector(togglePause), keyEquivalent: "p")
    private let standItem = NSMenuItem(title: "Aviso de 1 hora", action: #selector(toggleStand), keyEquivalent: "")
    private var standEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "standEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "standEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let menu = NSMenu()
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Reiniciar contador", action: #selector(reset), keyEquivalent: "r"))
        menu.addItem(standItem)
        let waitItem = NSMenuItem(title: "Esperar a Claude", action: #selector(toggleWait), keyEquivalent: "\u{1b}")
        waitItem.keyEquivalentModifierMask = .command
        menu.addItem(waitItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Probar aviso de vista", action: #selector(testEye), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Probar aviso de pararse", action: #selector(testStand), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu

        eyeOverlay.onFinish = { [weak self] in
            guard let self else { return }
            self.inBreak = false
            if self.elapsed >= standInterval { self.elapsed = 0 }
            self.refresh()
        }
        waitOverlay.onFinish = { [weak self] in
            self?.inBreak = false
            self?.refresh()
        }
        overlay.onFinish = { [weak self] in
            self?.inBreak = false
            self?.elapsed = 0
            self?.refresh()
        }

        // Si la Mac se durmió o se bloqueó, ya estuviste lejos: reiniciar.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(reset), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reset), name: .init("com.apple.screenIsUnlocked"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(claudeDone), name: claudeDoneNotification, object: nil)
        registerHotKey()

        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(tick!, forMode: .common)
        refresh()
    }

    private func step() {
        guard !paused, !inBreak else { return }
        elapsed += 1
        // En reunión el contador sigue, pero los avisos esperan a que cortes.
        inMeeting = micInUse()
        if standEnabled && elapsed >= standInterval {
            guard !inMeeting else { refresh(); return }
            pendingEye = false
            inBreak = true
            overlay.show()
        } else if elapsed % eyeInterval == 0 || pendingEye {
            guard !inMeeting else { pendingEye = true; refresh(); return }
            pendingEye = false
            inBreak = true
            eyeOverlay.show()
        }
        refresh()
    }

    private func refresh() {
        pauseItem.title = paused ? "Reanudar" : "Pausar"
        standItem.state = standEnabled ? .on : .off
        let toEye = eyeInterval - elapsed % eyeInterval
        let nextIsStand = standEnabled && elapsed + toEye >= standInterval
        let icon = paused ? "⏸" : inMeeting ? "📞" : (nextIsStand ? "🧍" : "👁")
        if inMeeting && (pendingEye || (standEnabled && elapsed >= standInterval)) {
            statusItem.button?.title = "📞 después"
            return
        }
        let m = toEye / 60, s = toEye % 60
        statusItem.button?.title = inBreak ? (waitOverlay.isShowing ? "☕" : standEnabled && elapsed >= standInterval ? "🧍 ahora" : "👀 ahora") : String(format: "%@ %d:%02d", icon, m, s)
    }

    // Cmd+Esc global (Carbon no necesita permiso de Accesibilidad)
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggleWait() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_Escape), UInt32(cmdKey), EventHotKeyID(signature: 0x5041_5553, id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    @objc private func toggleWait() {
        if waitOverlay.isShowing { waitOverlay.finish(); return }
        guard !inBreak else { return }
        inBreak = true
        waitOverlay.show()
        refresh()
    }

    @objc private func claudeDone() {
        if waitOverlay.isShowing {
            waitOverlay.finish()  // suena "Hero"
        } else {
            NSSound(named: "Pop")?.play()
        }
    }

    @objc private func togglePause() { paused.toggle(); refresh() }
    @objc private func toggleStand() { standEnabled.toggle(); refresh() }
    @objc private func reset() { elapsed = 0; refresh() }
    @objc private func testEye() { inBreak = true; eyeOverlay.show(); refresh() }
    @objc private func testStand() { inBreak = true; overlay.show(); refresh() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
