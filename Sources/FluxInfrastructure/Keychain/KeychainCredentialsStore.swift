import Foundation
import Security
import FluxDomain

/// Persistência de conta SIP no Keychain do macOS (docs/05_SECURITY_PRIVACY.md).
/// A conta inteira (incluindo senha) vive em um único item genérico de senha —
/// nada é gravado em UserDefaults ou arquivo.
///
/// O `service` deve ser único por marca/tenant (docs/05: uma marca nunca
/// acessa credenciais de outra). `AppComposition` monta esse nome.
public struct KeychainCredentialsStore: SecureCredentialsStoreProtocol {
    public enum KeychainError: Error, Equatable, Sendable {
        case unexpectedStatus(OSStatus)
        case corruptedData
    }

    private let service: String
    private static let itemAccount = "sip-account"

    public init(service: String) {
        self.service = service
    }

    /// DTO de persistência. `SIPAccount` não é `Codable` de propósito —
    /// evita que a senha seja serializada acidentalmente em outra camada;
    /// só este store sabe gravá-la e lê-la.
    private struct StoredAccount: Codable {
        let username: String
        let password: String
        let domain: String
        let displayName: String?
        let authUsername: String?
        let outboundProxy: String?
        let transport: String
        let port: Int
    }

    public func save(account: SIPAccount) throws {
        let dto = StoredAccount(
            username: account.username,
            password: account.password,
            domain: account.domain,
            displayName: account.displayName,
            authUsername: account.authUsername,
            outboundProxy: account.outboundProxy,
            transport: account.transport.rawValue,
            port: account.port
        )
        let data = try JSONEncoder().encode(dto)

        var status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func loadAccount() throws -> SIPAccount? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let dto = try? JSONDecoder().decode(StoredAccount.self, from: data),
              let transport = SIPTransport(rawValue: dto.transport)
        else {
            throw KeychainError.corruptedData
        }

        return SIPAccount(
            username: dto.username,
            password: dto.password,
            domain: dto.domain,
            displayName: dto.displayName,
            authUsername: dto.authUsername,
            outboundProxy: dto.outboundProxy,
            transport: transport,
            port: dto.port
        )
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.itemAccount
        ]
    }
}
