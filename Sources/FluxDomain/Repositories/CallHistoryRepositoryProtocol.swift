import Foundation

/// Contrato do repositório de histórico de chamadas (Ciclo 10 implementa
/// a persistência local; a interface existe desde já para o domínio evoluir).
public protocol CallHistoryRepositoryProtocol: Sendable {
    func append(_ entry: CallHistoryEntry) async throws
    func recentEntries(limit: Int) async throws -> [CallHistoryEntry]
    func clear() async throws
}
