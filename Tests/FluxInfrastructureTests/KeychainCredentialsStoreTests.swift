import Testing
import Foundation
import Security
import FluxDomain
@testable import FluxInfrastructure

/// Testes contra o Keychain real do usuário logado, usando um service
/// exclusivo por teste (`dev.fluxsoftphone.tests.<uuid>`) com limpeza ao final.
@Suite("KeychainCredentialsStore", .serialized)
struct KeychainCredentialsStoreTests {
    private static let servicePrefix = "dev.fluxsoftphone.tests."

    init() {
        // Remove itens órfãos de execuções anteriores abortadas (crash/kill
        // do runner impede o defer de limpar). Idempotente e barato.
        Self.sweepOrphanedItems()
    }

    private static func sweepOrphanedItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(servicePrefix) else { continue }
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ] as CFDictionary)
        }
    }

    private func makeStore() -> KeychainCredentialsStore {
        KeychainCredentialsStore(service: "\(Self.servicePrefix)\(UUID().uuidString)")
    }

    @Test("salvar e carregar preserva todos os campos, incluindo senha")
    func roundtrip() throws {
        let store = makeStore()
        defer { try? store.clear() }

        let account = SIPAccount(
            username: "1001",
            password: "s3nh4-com-#簡体!",
            domain: "sip.test.local",
            displayName: "Ramal Teste",
            authUsername: "auth1001",
            outboundProxy: "proxy.test.local",
            transport: .tls,
            port: 15061
        )
        try store.save(account: account)

        let loaded = try store.loadAccount()
        #expect(loaded == account)
    }

    @Test("carregar sem conta salva retorna nil")
    func loadEmpty() throws {
        let store = makeStore()
        #expect(try store.loadAccount() == nil)
    }

    @Test("salvar de novo sobrescreve a conta anterior")
    func overwrite() throws {
        let store = makeStore()
        defer { try? store.clear() }

        try store.save(account: SIPAccount(username: "antiga", password: "a", domain: "d1.local"))
        try store.save(account: SIPAccount(username: "nova", password: "b", domain: "d2.local"))

        let loaded = try store.loadAccount()
        #expect(loaded?.username == "nova")
        #expect(loaded?.domain == "d2.local")
    }

    @Test("clear remove as credenciais e é idempotente")
    func clearRemoves() throws {
        let store = makeStore()
        try store.save(account: SIPAccount(username: "u", password: "p", domain: "d.local"))

        try store.clear()
        #expect(try store.loadAccount() == nil)
        // Segundo clear não pode falhar (errSecItemNotFound é aceito).
        try store.clear()
    }

    @Test("services diferentes são isolados entre si (separação por marca)")
    func serviceIsolation() throws {
        let storeA = makeStore()
        let storeB = makeStore()
        defer {
            try? storeA.clear()
            try? storeB.clear()
        }

        try storeA.save(account: SIPAccount(username: "marca-a", password: "pa", domain: "a.local"))

        #expect(try storeB.loadAccount() == nil)
        try storeB.save(account: SIPAccount(username: "marca-b", password: "pb", domain: "b.local"))
        #expect(try storeA.loadAccount()?.username == "marca-a")
    }
}
