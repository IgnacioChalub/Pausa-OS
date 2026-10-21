import Foundation
import Network

// Sincronización en la red local ("jamear" las pausas).
//
// Uno arranca la sesión y la anuncia por Bonjour; los demás la encuentran y se conectan.
// El host lleva un reloj del grupo (SessionClock) y le manda a todos, una vez por segundo,
// el horario y cuánto falta, más un aviso cuando arranca cada pausa. Lo personal (posponer,
// reuniones, pausar) no viaja: cada uno lo resuelve en su Mac y se reengancha en la próxima.

let syncServiceType = "_pausa._tcp"

// Lo que el host impone: cada cuánto, cuánto dura y la cuenta regresiva de cada pausa.
struct SyncSchedule: Codable, Equatable {
    var eyeEnabled: Bool
    var eyeEvery: Int
    var eyeDuration: Int
    var eyeWarning: Int
    var standEnabled: Bool
    var standEvery: Int
    var standDuration: Int
    var standWarning: Int

    init(_ c: Config) {
        eyeEnabled = c.eye.enabled
        eyeEvery = c.eye.every
        eyeDuration = c.eye.duration
        eyeWarning = c.eye.warning
        standEnabled = c.stand.enabled
        standEvery = c.stand.every
        standDuration = c.stand.duration
        standWarning = c.stand.warning
    }

    func apply(to c: Config) -> Config {
        var c = c
        c.eye.enabled = eyeEnabled
        c.eye.every = eyeEvery
        c.eye.duration = eyeDuration
        c.eye.warning = eyeWarning
        c.stand.enabled = standEnabled
        c.stand.every = standEvery
        c.stand.duration = standDuration
        c.stand.warning = standWarning
        return c
    }
}

// Reloj del grupo. Corre aparte de las pausas del host, así su posponer no corre a nadie.
struct SessionClock {
    var eye: Int
    var stand: Int

    // Avanza un segundo; devuelve la pausa que arranca, si toca.
    // Después de disparar queda en negativo por lo que dura la pausa, para no contarla.
    mutating func tick(_ s: SyncSchedule) -> Kind? {
        eye += 1
        stand += 1
        if s.standEnabled && stand >= s.standEvery {
            stand = -(s.standWarning + s.standDuration)
            eye = stand  // la de pararse también cuenta como descanso de la vista
            return .stand
        }
        if s.eyeEnabled && eye >= s.eyeEvery {
            eye = -(s.eyeWarning + s.eyeDuration)
            return .eye
        }
        return nil
    }
}

struct SyncMessage: Codable {
    var type: String               // "hello" (invitado → host), "state", "break" (host → invitados)
    var name: String?
    var schedule: SyncSchedule?
    var eye: Int?
    var stand: Int?
    var kind: Kind?

    static func hello(_ name: String) -> SyncMessage { SyncMessage(type: "hello", name: name) }
    static func state(_ s: SyncSchedule, _ c: SessionClock) -> SyncMessage {
        SyncMessage(type: "state", schedule: s, eye: c.eye, stand: c.stand)
    }
    static func breakStarts(_ k: Kind) -> SyncMessage { SyncMessage(type: "break", kind: k) }
}

// Una conexión TCP que manda y recibe un JSON por línea.
final class Peer {
    let conn: NWConnection
    var name = ""
    var onMessage: ((SyncMessage) -> Void)?
    var onClose: (() -> Void)?
    private var buffer = Data()

    init(_ conn: NWConnection) { self.conn = conn }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        conn.start(queue: .main)
        receive()
    }

    func send(_ m: SyncMessage) {
        guard var data = try? JSONEncoder().encode(m) else { return }
        data.append(10)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        guard let cb = onClose else { return }
        onClose = nil
        conn.cancel()
        cb()
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            while let i = self.buffer.firstIndex(of: 10) {
                let line = self.buffer.prefix(upTo: i)
                self.buffer = Data(self.buffer.suffix(from: i + 1))
                if let m = try? JSONDecoder().decode(SyncMessage.self, from: line) { self.onMessage?(m) }
            }
            if done || error != nil { self.close() } else { self.receive() }
        }
    }
}

final class SyncHost {
    private var listener: NWListener?
    private(set) var peers: [Peer] = []
    var onChange: (() -> Void)?
    var onFail: (() -> Void)?

    func start(name: String) throws {
        let l = try NWListener(using: .tcp)
        l.service = NWListener.Service(name: name, type: syncServiceType)
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            let p = Peer(conn)
            p.onMessage = { [weak self, weak p] m in
                guard m.type == "hello" else { return }
                p?.name = m.name ?? ""
                self?.onChange?()
            }
            p.onClose = { [weak self, weak p] in
                self?.peers.removeAll { $0 === p }
                self?.onChange?()
            }
            self.peers.append(p)
            p.start()
            self.onChange?()
        }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.onFail?() }
        }
        l.start(queue: .main)
        listener = l
    }

    func broadcast(_ m: SyncMessage) { peers.forEach { $0.send(m) } }

    func stop() {
        listener?.cancel()
        listener = nil
        peers.forEach { $0.onClose = nil; $0.conn.cancel() }
        peers = []
    }
}

final class SyncBrowser {
    private var browser: NWBrowser?
    private(set) var results: [NWBrowser.Result] = []
    var onChange: (() -> Void)?

    func start() {
        guard browser == nil else { return }
        results = []
        let b = NWBrowser(for: .bonjour(type: syncServiceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            self?.results = results.sorted { serviceName($0) < serviceName($1) }
            self?.onChange?()
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

func serviceName(_ r: NWBrowser.Result) -> String {
    if case let .service(name, _, _, _) = r.endpoint { return name }
    return "\(r.endpoint)"
}
