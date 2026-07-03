import Foundation

/// Registro de histórico de chamada (docs/03_SIP_AUDIO_CALL_ENGINE.md).
/// Guarda apenas o necessário — nunca payload SIP, senha ou áudio.
public struct CallHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let number: String
    public let displayName: String?
    public let direction: CallDirection
    public let outcome: CallOutcome
    public let startedAt: Date
    /// Duração de conversa em segundos; 0 para perdidas/não atendidas.
    public let duration: TimeInterval
    /// Conta usada, no formato `usuario@dominio` sem senha.
    public let accountURI: String

    public init(
        id: UUID = UUID(),
        number: String,
        displayName: String? = nil,
        direction: CallDirection,
        outcome: CallOutcome,
        startedAt: Date,
        duration: TimeInterval,
        accountURI: String
    ) {
        self.id = id
        self.number = number
        self.displayName = displayName
        self.direction = direction
        self.outcome = outcome
        self.startedAt = startedAt
        self.duration = duration
        self.accountURI = accountURI
    }
}

/// Resultado final da chamada para exibição no histórico.
public enum CallOutcome: String, Codable, Equatable, Sendable {
    case completed
    case missed
    case rejected
    case cancelled
    case failed
}
