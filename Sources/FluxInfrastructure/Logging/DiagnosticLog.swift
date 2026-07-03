import Foundation

/// Registro de eventos em memória para a tela de Diagnóstico: cada linha é
/// um fato observável (registro, chamada, mídia, erro), já sanitizado por
/// quem o emite — nunca senha, token ou número completo.
///
/// Ring buffer com teto fixo; um único consumidor (AppState) recebe as
/// entradas novas via AsyncStream para refletir na UI.
public final class DiagnosticLog: @unchecked Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let message: String

        public init(id: UUID = UUID(), timestamp: Date = Date(), message: String) {
            self.id = id
            self.timestamp = timestamp
            self.message = message
        }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let capacity: Int
    private var continuation: AsyncStream<Entry>.Continuation?

    public init(capacity: Int = 300) {
        self.capacity = max(10, capacity)
    }

    /// Fluxo de entradas (consumidor único). Reproduz o histórico já
    /// acumulado e segue com as novas — assim nenhuma entrada entre a
    /// criação do log e a assinatura se perde (ex.: linha de arranque).
    public func updates() -> AsyncStream<Entry> {
        let (stream, continuation) = AsyncStream.makeStream(of: Entry.self)
        lock.lock()
        self.continuation = continuation
        let backlog = entries
        lock.unlock()
        for entry in backlog {
            continuation.yield(entry)
        }
        return stream
    }

    public func append(_ message: String) {
        let entry = Entry(message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(entry)
    }

    public func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
