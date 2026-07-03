import Foundation
import FluxDomain

/// Histórico de chamadas em arquivo JSON local (Ciclo 7/10).
///
/// O diretório deve ser único por marca (AppComposition monta
/// `Application Support/<bundle>/<brandId>/`) — docs/05: um tenant nunca
/// lê histórico de outro. O arquivo guarda apenas os campos de
/// `CallHistoryEntry`; nunca senha, payload SIP ou áudio.
public actor FileCallHistoryRepository: CallHistoryRepositoryProtocol {
    private let fileURL: URL
    /// Limite de registros persistidos — histórico não cresce sem teto.
    private let maxEntries: Int
    /// Cache em memória, do mais recente para o mais antigo.
    private var cache: [CallHistoryEntry]?

    public init(
        directory: URL,
        fileName: String = "call-history.json",
        maxEntries: Int = 500
    ) {
        self.fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        self.maxEntries = max(1, maxEntries)
    }

    public func append(_ entry: CallHistoryEntry) async throws {
        var entries = try loadIfNeeded()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        try persist(entries)
        cache = entries
    }

    public func recentEntries(limit: Int) async throws -> [CallHistoryEntry] {
        Array(try loadIfNeeded().prefix(max(0, limit)))
    }

    public func clear() async throws {
        cache = []
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func loadIfNeeded() throws -> [CallHistoryEntry] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        // Arquivo corrompido não é dado crítico o bastante para travar o
        // app: recomeça vazio (o arquivo antigo é sobrescrito no próximo
        // append). O erro fica registrado para diagnóstico.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries: [CallHistoryEntry]
        do {
            entries = try decoder.decode([CallHistoryEntry].self, from: data)
        } catch {
            AppLog.persistence.error(
                "Histórico corrompido; recomeçando vazio: \(String(describing: error), privacy: .public)"
            )
            entries = []
        }
        cache = entries
        return entries
    }

    private func persist(_ entries: [CallHistoryEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
