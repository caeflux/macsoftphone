import Foundation

/// Estado do registro SIP exibido para o usuário (docs/01_ARCHITECTURE.md).
public enum RegistrationState: Equatable, Sendable {
    case idle
    case registering
    case registered
    case failed(RegistrationFailureReason)
    case disconnected
    case expired
}

/// Motivo semântico de falha de registro. A tradução para mensagem
/// amigável acontece na camada de apresentação, nunca aqui.
public enum RegistrationFailureReason: Equatable, Sendable {
    case authenticationFailed
    case networkUnavailable
    case serverUnreachable
    case timeout
    case unknown
}
