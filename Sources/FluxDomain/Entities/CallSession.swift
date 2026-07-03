import Foundation

/// Uma chamada em andamento ou recém-encerrada.
/// Valor imutável: a engine SIP publica novas cópias a cada mudança de estado.
public struct CallSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let direction: CallDirection
    /// Número ou destino discado/recebido, como conhecido pela engine.
    public let remoteNumber: String
    /// Nome de exibição do interlocutor quando disponível (caller ID).
    public let remoteDisplayName: String?
    public let state: CallState
    public let createdAt: Date
    /// Momento em que a mídia foi estabelecida (estado `active`).
    public let connectedAt: Date?
    public let endedAt: Date?

    public init(
        id: String,
        direction: CallDirection,
        remoteNumber: String,
        remoteDisplayName: String? = nil,
        state: CallState,
        createdAt: Date,
        connectedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.direction = direction
        self.remoteNumber = remoteNumber
        self.remoteDisplayName = remoteDisplayName
        self.state = state
        self.createdAt = createdAt
        self.connectedAt = connectedAt
        self.endedAt = endedAt
    }

    /// Duração de conversa efetiva (do atendimento ao encerramento).
    public var talkDuration: TimeInterval {
        guard let connectedAt else { return 0 }
        return (endedAt ?? Date()).timeIntervalSince(connectedAt)
    }

    /// Cópia com estado atualizado, preservando os demais campos.
    public func with(
        state: CallState,
        connectedAt: Date? = nil,
        endedAt: Date? = nil
    ) -> CallSession {
        CallSession(
            id: id,
            direction: direction,
            remoteNumber: remoteNumber,
            remoteDisplayName: remoteDisplayName,
            state: state,
            createdAt: createdAt,
            connectedAt: connectedAt ?? self.connectedAt,
            endedAt: endedAt ?? self.endedAt
        )
    }
}
