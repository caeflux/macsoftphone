import Foundation

/// Contrato de persistência segura de credenciais (docs/05_SECURITY_PRIVACY.md).
/// A implementação real usa Keychain (Ciclo 3). Nunca UserDefaults.
public protocol SecureCredentialsStoreProtocol: Sendable {
    func save(account: SIPAccount) throws
    func loadAccount() throws -> SIPAccount?
    func clear() throws
}
