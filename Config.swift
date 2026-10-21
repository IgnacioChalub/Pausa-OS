import Foundation

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/pausa/config.yml")

// build.sh lo deja como symlink al config.yml del repo: escribir y mirar cambios en el archivo real.
private var realConfigURL: URL { configURL.resolvingSymlinksInPath() }

// MARK: - YAML mínimo

// Alcanza para config.yml: mapas anidados por indentación, `clave: valor` y comentarios con #.
// No soporta listas ni strings multilínea.
private struct Entry {
    let line: Int
    let path: String     // "vista.activado"
    let body: String     // la línea sin el comentario
    let key: String      // la línea hasta el ":" inclusive
    let value: String    // crudo, todavía con comillas
    let comment: String  // "# ..." o ""
}

private func entries(_ lines: [String]) -> [Entry] {
    var out: [Entry] = []
    var stack: [(indent: Int, key: String)] = []
    for (i, raw) in lines.enumerated() {
        let (body, comment) = splitComment(raw)
        guard let colon = body.firstIndex(of: ":") else { continue }
        let key = body[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { continue }
        let indent = body.prefix { $0 == " " }.count
        let value = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        while let last = stack.last, last.indent >= indent { stack.removeLast() }
        let path = (stack.map(\.key) + [key]).joined(separator: ".")
        if value.isEmpty {
            stack.append((indent, key))  // sección
        } else {
            out.append(Entry(line: i, path: path, body: body, key: String(body[...colon]),
                             value: value, comment: comment))
        }
    }
    return out
}

// Separa el comentario: un # después de un espacio y fuera de comillas.
private func splitComment(_ line: String) -> (String, String) {
    var quote: Character?
    var prev: Character = " "
    for i in line.indices {
        let c = line[i]
        if let q = quote {
            if c == q { quote = nil }
        } else if (c == "\"" || c == "'") && (prev.isWhitespace || prev == ":") {
            quote = c
        } else if c == "#" && prev.isWhitespace {
            return (String(line[..<i]), String(line[i...]))
        }
        prev = c
    }
    return (line, "")
}

private func unquote(_ s: String) -> String {
    guard s.count >= 2, let f = s.first, f == "\"" || f == "'", s.last == f else { return s }
    return String(s.dropFirst().dropLast())
}

// MARK: - Config

struct BreakConfig {
    var enabled: Bool
    var every: Int        // segundos entre pausas
    var duration: Int     // segundos que dura la pausa
    var warning: Int      // segundos de cuenta regresiva antes de arrancar
    var warningText: String
    var title: String
    var sub: String
    var sound: String
    var rings: Int
}

struct Config {
    var eye: BreakConfig
    var stand: BreakConfig
    var snoozeEnabled: Bool
    var snoozeSeconds: Int
    var snoozeMax: Int    // 0 = sin límite
    var snoozeBanner: Bool
    var snoozeText: String
    var opacity: Double
    var allowSkip: Bool
    var endSound: String
    var waitForMeetings: Bool
    var resetOnWake: Bool
    var showCountdown: Bool
    var claudeEnabled: Bool
    var claudeHotKey: String
    var claudeTitle: String
    var claudeSub: String
    var claudeDoneSound: String
    var problems: [String] = []

    static func load() -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configURL.path),
           let bundled = Bundle.main.url(forResource: "config.example", withExtension: "yml") {
            try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: bundled, to: configURL)
        }
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            var c = Config(Values([:]))
            c.problems = ["No pude leer \(configURL.path), uso los valores por defecto"]
            return c
        }
        var raw: [String: String] = [:]
        for e in entries(text.components(separatedBy: "\n")) { raw[e.path] = unquote(e.value) }
        let v = Values(raw)
        var c = Config(v)
        c.problems = v.problems + Set(raw.keys).subtracting(v.used).sorted().map { "Clave desconocida: \($0)" }
        return c
    }

    static var modified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: realConfigURL.path))?[.modificationDate] as? Date
    }

    // Cambia un valor en el archivo sin tocar el resto (comentarios incluidos).
    // Si la clave no está, la agrega al final de su sección.
    static func set(_ path: String, _ value: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        let all = entries(lines)
        if let e = all.first(where: { $0.path == path }) {
            let body = e.key + " " + value
            lines[e.line] = e.comment.isEmpty ? body
                : body.padding(toLength: max(e.body.count, body.count + 1), withPad: " ", startingAt: 0) + e.comment
        } else {
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            let line = "  \(parts[1]): \(value)"
            if let last = all.last(where: { $0.path.hasPrefix(parts[0] + ".") }) {
                lines.insert(line, at: last.line + 1)
            } else if let header = lines.firstIndex(where: { $0.hasPrefix(parts[0] + ":") }) {
                lines.insert(line, at: header + 1)
            } else {
                lines += ["", parts[0] + ":", line]
            }
        }
        try? lines.joined(separator: "\n").write(to: realConfigURL, atomically: true, encoding: .utf8)
    }

    private init(_ v: Values) {
        func brk(_ s: String, every: Double, duration: Int, warning: Int, warningText: String,
                 title: String, sub: String, rings: Int) -> BreakConfig {
            BreakConfig(enabled: v.bool("\(s).activado", true),
                        every: v.minutes("\(s).cada_minutos", every),
                        duration: v.int("\(s).duracion_segundos", duration, min: 1),
                        warning: v.int("\(s).aviso_previo_segundos", warning),
                        warningText: v.string("\(s).aviso_previo_texto", warningText),
                        title: v.string("\(s).titulo", title),
                        sub: v.string("\(s).subtitulo", sub),
                        sound: v.string("\(s).sonido", "Sosumi"),
                        rings: v.int("\(s).repeticiones_sonido", rings))
        }
        eye = brk("vista", every: 20, duration: 20, warning: 3, warningText: "👀  Pausa corta en {s}",
                  title: "👀  Mirá algo lejos", sub: "Algo a unos 6 metros, sin mirar la pantalla.", rings: 1)
        stand = brk("pararse", every: 60, duration: 300, warning: 10, warningText: "🧍  Pausa larga en {s}",
                    title: "🧍  Pará. Levantate.", sub: "Caminá, estirate, tomá agua.", rings: 3)
        snoozeEnabled = v.bool("posponer.activado", true)
        snoozeSeconds = v.minutes("posponer.minutos", 5)
        snoozeMax = v.int("posponer.maximo_veces", 3)
        snoozeBanner = v.bool("posponer.mostrar_banner", true)
        snoozeText = v.string("posponer.texto_banner", "⏸  Pausa pospuesta, activala apenas puedas · vuelve en {t}")
        opacity = v.double("pantalla.opacidad", 0.88, 0...1)
        allowSkip = v.bool("pantalla.permitir_saltar", true)
        endSound = v.string("pantalla.sonido_fin", "Hero")
        waitForMeetings = v.bool("reuniones.esperar_si_hay_microfono", true)
        resetOnWake = v.bool("general.reiniciar_al_despertar", true)
        showCountdown = v.bool("general.mostrar_contador", true)
        claudeEnabled = v.bool("claude.activado", true)
        claudeHotKey = v.string("claude.atajo", "cmd+esc")
        claudeTitle = v.string("claude.titulo", "☕  Esperando a Claude…")
        claudeSub = v.string("claude.subtitulo", "Mirá a otro lado. Te aviso cuando responda.")
        claudeDoneSound = v.string("claude.sonido_al_responder", "Pop")
    }
}

// Lectura tipada con valor por defecto; anota qué claves se usaron y cuáles vinieron mal.
private final class Values {
    let raw: [String: String]
    var used = Set<String>()
    var problems: [String] = []

    init(_ raw: [String: String]) { self.raw = raw }

    private func get(_ k: String) -> String? { used.insert(k); return raw[k] }
    private func bad(_ k: String, _ v: String) { problems.append("Valor inválido en \(k): \(v)") }

    func string(_ k: String, _ d: String) -> String { get(k) ?? d }

    func bool(_ k: String, _ d: Bool) -> Bool {
        guard let v = get(k) else { return d }
        switch v.lowercased() {
        case "true", "yes", "on", "si", "sí": return true
        case "false", "no", "off": return false
        default: bad(k, v); return d
        }
    }

    func int(_ k: String, _ d: Int, min lo: Int = 0) -> Int {
        guard let v = get(k) else { return d }
        guard let n = Int(v) else { bad(k, v); return d }
        return max(n, lo)
    }

    func double(_ k: String, _ d: Double, _ range: ClosedRange<Double>) -> Double {
        guard let v = get(k) else { return d }
        guard let n = Double(v) else { bad(k, v); return d }
        return min(max(n, range.lowerBound), range.upperBound)
    }

    // Minutos (acepta decimales, ej. 0.5) → segundos.
    func minutes(_ k: String, _ d: Double) -> Int {
        guard let v = get(k) else { return Int(d * 60) }
        guard let n = Double(v) else { bad(k, v); return Int(d * 60) }
        return max(Int(n * 60), 1)
    }
}
