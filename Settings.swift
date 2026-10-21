import SwiftUI

// Ventana de configuración: cada cambio se escribe al toque en config.yml
// y la app lo toma en el próximo segundo, igual que si editaras el archivo.

let systemSounds: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
    .map { ($0 as NSString).deletingPathExtension }
    .sorted()

func openConfigFile() {
    if !NSWorkspace.shared.open(configURL) {
        NSWorkspace.shared.open([configURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

func makeSettingsWindow(_ model: SettingsModel) -> NSWindow {
    let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
    w.title = "Configuración de Pausa"
    w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    w.isReleasedWhenClosed = false
    w.setContentSize(NSSize(width: 540, height: 720))
    w.center()
    return w
}

final class SettingsModel: ObservableObject {
    @Published var cfg: Config

    init(_ cfg: Config) { self.cfg = cfg }

    private func bind<T>(_ kp: WritableKeyPath<Config, T>, write: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: { self.cfg[keyPath: kp] }, set: { self.cfg[keyPath: kp] = $0; write($0) })
    }

    func bool(_ path: String, _ kp: WritableKeyPath<Config, Bool>) -> Binding<Bool> {
        bind(kp) { Config.set(path, $0 ? "true" : "false") }
    }

    func int(_ path: String, _ kp: WritableKeyPath<Config, Int>) -> Binding<Int> {
        bind(kp) { Config.set(path, "\(max($0, 0))") }
    }

    func string(_ path: String, _ kp: WritableKeyPath<Config, String>) -> Binding<String> {
        bind(kp) { Config.set(path, $0.contains("\"") ? "'\($0)'" : "\"\($0)\"") }
    }

    func opacity(_ path: String, _ kp: WritableKeyPath<Config, Double>) -> Binding<Double> {
        bind(kp) { Config.set(path, String(format: "%.2f", $0)) }
    }

    // Config guarda segundos; en el archivo y en la pantalla van minutos.
    func minutes(_ path: String, _ kp: WritableKeyPath<Config, Int>) -> Binding<Double> {
        Binding(get: { Double(self.cfg[keyPath: kp]) / 60 }, set: { m in
            let s = max(Int((m * 60).rounded()), 1)
            self.cfg[keyPath: kp] = s
            let m = Double(s) / 60
            Config.set(path, m == m.rounded() ? "\(Int(m))" : "\(m)")
        })
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            if !model.cfg.problems.isEmpty {
                Section {
                    ForEach(model.cfg.problems, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            breakSection("Pausa corta · vista", "vista", \.eye)
            breakSection("Pausa larga · pararse", "pararse", \.stand)

            Section("Posponer") {
                Toggle("Permitir posponer", isOn: model.bool("posponer.activado", \.snoozeEnabled))
                Group {
                    MinutesField(label: "Posponer por", value: model.minutes("posponer.minutos", \.snoozeSeconds))
                    IntField(label: "Máximo seguidas", value: model.int("posponer.maximo_veces", \.snoozeMax),
                             unit: "(0 = sin límite)")
                    Toggle("Mostrar banner mientras está pospuesta", isOn: model.bool("posponer.mostrar_banner", \.snoozeBanner))
                    TextField("Texto del banner", text: model.string("posponer.texto_banner", \.snoozeText))
                    Text("{t} se reemplaza por el tiempo que falta.").font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!model.cfg.snoozeEnabled)
            }

            Section("Pantalla") {
                LabeledContent("Opacidad") {
                    HStack {
                        Slider(value: model.opacity("pantalla.opacidad", \.opacity), in: 0.3...1)
                        Text("\(Int((model.cfg.opacity * 100).rounded()))%").monospacedDigit().frame(width: 40)
                    }
                }
                Toggle("Permitir saltar (botón y Esc)", isOn: model.bool("pantalla.permitir_saltar", \.allowSkip))
                SoundPicker(label: "Sonido al terminar", value: model.string("pantalla.sonido_fin", \.endSound))
            }

            Section("General") {
                Toggle("Esperar si hay una reunión (micrófono en uso)",
                       isOn: model.bool("reuniones.esperar_si_hay_microfono", \.waitForMeetings))
                Toggle("Reiniciar al despertar o desbloquear la Mac",
                       isOn: model.bool("general.reiniciar_al_despertar", \.resetOnWake))
                Toggle("Mostrar el tiempo en la barra de menú",
                       isOn: model.bool("general.mostrar_contador", \.showCountdown))
            }

            Section("Esperando a Claude") {
                Toggle("Activado", isOn: model.bool("claude.activado", \.claudeEnabled))
                Group {
                    LabeledContent("Atajo") {
                        HStack {
                            TextField("", text: model.string("claude.atajo", \.claudeHotKey)).labelsHidden().frame(width: 120)
                            let ok = parseHotKey(model.cfg.claudeHotKey) != nil
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? .green : .red)
                                .help("cmd/ctrl/opt/shift + tecla (esc, space, return, tab, a-z, 0-9, f1-f12)")
                        }
                    }
                    TextField("Título", text: model.string("claude.titulo", \.claudeTitle))
                    TextField("Subtítulo", text: model.string("claude.subtitulo", \.claudeSub))
                    SoundPicker(label: "Sonido cuando responde", value: model.string("claude.sonido_al_responder", \.claudeDoneSound))
                }
                .disabled(!model.cfg.claudeEnabled)
            }

            Section {
                HStack {
                    Text("Se guarda solo en config.yml.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Abrir config.yml") { openConfigFile() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 400)
    }

    private func breakSection(_ title: String, _ s: String, _ kp: WritableKeyPath<Config, BreakConfig>) -> some View {
        Section(title) {
            Toggle("Activada", isOn: model.bool("\(s).activado", kp.appending(path: \.enabled)))
            Group {
                MinutesField(label: "Cada", value: model.minutes("\(s).cada_minutos", kp.appending(path: \.every)))
                IntField(label: "Dura", value: model.int("\(s).duracion_segundos", kp.appending(path: \.duration)),
                         unit: "seg", step: 5)
                IntField(label: "Cuenta regresiva antes", value: model.int("\(s).aviso_previo_segundos", kp.appending(path: \.warning)),
                         unit: "seg (0 = sin aviso)")
                TextField("Texto de la cuenta regresiva", text: model.string("\(s).aviso_previo_texto", kp.appending(path: \.warningText)))
                TextField("Título", text: model.string("\(s).titulo", kp.appending(path: \.title)))
                TextField("Subtítulo", text: model.string("\(s).subtitulo", kp.appending(path: \.sub)))
                SoundPicker(label: "Sonido", value: model.string("\(s).sonido", kp.appending(path: \.sound)))
                IntField(label: "Veces que suena", value: model.int("\(s).repeticiones_sonido", kp.appending(path: \.rings)), unit: "")
            }
            .disabled(!model.cfg[keyPath: kp].enabled)
        }
    }
}

struct IntField: View {
    let label: String
    @Binding var value: Int
    var unit: String
    var step = 1

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.grouping(.never))
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 64)
                Stepper("", value: $value, in: 0...100_000, step: step).labelsHidden()
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

struct MinutesField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 64)
                Stepper("", value: $value, in: 0.1...1_440, step: 1).labelsHidden()
                Text("min").foregroundStyle(.secondary)
            }
        }
    }
}

struct SoundPicker: View {
    let label: String
    @Binding var value: String

    var body: some View {
        let options = value.isEmpty || systemSounds.contains(value) ? systemSounds : [value] + systemSounds
        Picker(label, selection: Binding(get: { value }, set: { value = $0; play($0) })) {
            Text("Ninguno").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }
}
