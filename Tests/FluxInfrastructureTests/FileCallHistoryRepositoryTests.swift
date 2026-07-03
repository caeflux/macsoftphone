import Testing
import Foundation
import FluxDomain
@testable import FluxInfrastructure

@Suite("FileCallHistoryRepository")
struct FileCallHistoryRepositoryTests {
    /// Diretório temporário exclusivo por teste.
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flux-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Datas em segundos inteiros para igualdade exata após ISO8601.
    private func makeEntry(number: String, secondsAgo: Int = 0) -> CallHistoryEntry {
        CallHistoryEntry(
            number: number,
            direction: .outgoing,
            outcome: .completed,
            startedAt: Date(timeIntervalSince1970: 1_750_000_000 - TimeInterval(secondsAgo)),
            duration: 42,
            accountURI: "sip:1001@sip.test.local"
        )
    }

    @Test("append e recentEntries preservam dados e ordem (mais novo primeiro)")
    func appendAndRead() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileCallHistoryRepository(directory: dir)

        let older = makeEntry(number: "1001", secondsAgo: 60)
        let newer = makeEntry(number: "1002")
        try await repo.append(older)
        try await repo.append(newer)

        let entries = try await repo.recentEntries(limit: 10)
        #expect(entries == [newer, older])
    }

    @Test("histórico persiste entre instâncias (arquivo em disco)")
    func persistsAcrossInstances() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entry = makeEntry(number: "51999998888")
        try await FileCallHistoryRepository(directory: dir).append(entry)

        let reopened = FileCallHistoryRepository(directory: dir)
        let entries = try await reopened.recentEntries(limit: 10)
        #expect(entries == [entry])
    }

    @Test("limite máximo descarta os registros mais antigos")
    func capsAtMaxEntries() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileCallHistoryRepository(directory: dir, maxEntries: 3)

        for index in 0..<5 {
            try await repo.append(makeEntry(number: "100\(index)", secondsAgo: 100 - index))
        }

        let entries = try await repo.recentEntries(limit: 10)
        #expect(entries.count == 3)
        #expect(entries.map(\.number) == ["1004", "1003", "1002"])
    }

    @Test("clear apaga o histórico e o arquivo")
    func clearRemovesAll() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileCallHistoryRepository(directory: dir)

        try await repo.append(makeEntry(number: "1001"))
        try await repo.clear()

        #expect(try await repo.recentEntries(limit: 10).isEmpty)
        // Nova instância também não vê nada (arquivo removido).
        #expect(try await FileCallHistoryRepository(directory: dir).recentEntries(limit: 10).isEmpty)
    }

    @Test("arquivo corrompido recomeça vazio sem travar")
    func corruptedFileStartsFresh() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("não é json".utf8).write(to: dir.appendingPathComponent("call-history.json"))

        let repo = FileCallHistoryRepository(directory: dir)
        #expect(try await repo.recentEntries(limit: 10).isEmpty)

        // E volta a funcionar normalmente.
        let entry = makeEntry(number: "1001")
        try await repo.append(entry)
        #expect(try await repo.recentEntries(limit: 10) == [entry])
    }

    @Test("arquivo não contém senha nem campos além do contrato")
    func fileContainsOnlyContractFields() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = FileCallHistoryRepository(directory: dir)
        try await repo.append(makeEntry(number: "1001"))

        let content = try String(contentsOf: dir.appendingPathComponent("call-history.json"), encoding: .utf8)
        #expect(!content.lowercased().contains("password"))
        #expect(!content.lowercased().contains("senha"))
        #expect(content.contains("accountURI"))
    }
}
