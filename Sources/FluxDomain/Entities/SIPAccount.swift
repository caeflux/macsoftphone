import Foundation

/// Conta SIP configurada pelo usuário ou por provisionamento.
///
/// A senha vive aqui apenas em memória durante o uso. Persistência é
/// responsabilidade exclusiva de `SecureCredentialsStoreProtocol` (Keychain).
public struct SIPAccount: Equatable, Sendable {
    public let username: String
    public let password: String
    public let domain: String
    public let displayName: String?
    /// Usuário de autenticação quando difere do usuário SIP.
    public let authUsername: String?
    public let outboundProxy: String?
    public let transport: SIPTransport
    public let port: Int

    public init(
        username: String,
        password: String,
        domain: String,
        displayName: String? = nil,
        authUsername: String? = nil,
        outboundProxy: String? = nil,
        transport: SIPTransport = .udp,
        port: Int? = nil
    ) {
        self.username = username
        self.password = password
        self.domain = domain
        self.displayName = displayName
        self.authUsername = authUsername
        self.outboundProxy = outboundProxy
        self.transport = transport
        self.port = port ?? transport.defaultPort
    }

    /// URI SIP da conta, sem credenciais.
    public var uri: String {
        "sip:\(username)@\(domain)"
    }
}

extension SIPAccount: CustomStringConvertible, CustomDebugStringConvertible {
    /// A descrição nunca inclui a senha — proteção contra `print(account)`
    /// ou interpolação acidental em log (docs/05_SECURITY_PRIVACY.md).
    public var description: String {
        "SIPAccount(username: \(Self.masked(username)), domain: \(domain), transport: \(transport.rawValue), port: \(port))"
    }

    public var debugDescription: String { description }

    static func masked(_ value: String) -> String {
        guard value.count > 2 else { return "***" }
        return "\(value.prefix(2))***"
    }
}
