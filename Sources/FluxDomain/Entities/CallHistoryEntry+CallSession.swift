import Foundation

public extension CallHistoryEntry {
    /// Cria o registro de histórico a partir de uma sessão terminada.
    /// Retorna `nil` para sessões ainda vivas — gravar cedo demais geraria
    /// duração errada e duplicatas.
    init?(session: CallSession, accountURI: String) {
        let outcome: CallOutcome
        switch session.state {
        case .failed:
            outcome = .failed
        case .ended(let reason):
            switch reason {
            case .rejected:
                outcome = .rejected
            case .missed:
                outcome = .missed
            case .cancelled:
                outcome = .cancelled
            case .localHangup, .remoteHangup, .none:
                if session.connectedAt != nil {
                    outcome = .completed
                } else {
                    // Encerrada antes de atender: perdida (entrada) ou
                    // cancelada pelo próprio usuário (saída).
                    outcome = session.direction == .incoming ? .missed : .cancelled
                }
            }
        case .idle, .incoming, .dialing, .ringing, .active, .held, .ending:
            return nil
        }

        let duration: TimeInterval
        if let connectedAt = session.connectedAt {
            duration = max(0, (session.endedAt ?? Date()).timeIntervalSince(connectedAt))
        } else {
            duration = 0
        }

        self.init(
            number: session.remoteNumber,
            displayName: session.remoteDisplayName,
            direction: session.direction,
            outcome: outcome,
            startedAt: session.createdAt,
            duration: duration,
            accountURI: accountURI
        )
    }
}
