import Foundation
import FluxDomain

/// Rótulos pt-BR para estados de chamada (docs/04_UI_UX_GUIDELINES.md).
enum CallStatePresentation {
    static func label(for state: CallState) -> String {
        switch state {
        case .idle: return ""
        case .incoming: return "Recebendo chamada"
        case .dialing: return "Discando…"
        case .ringing: return "Chamando…"
        case .active: return "Em chamada"
        case .held: return "Em espera"
        case .ending: return "Encerrando…"
        case .ended: return "Chamada encerrada"
        case .failed: return "Falha na chamada"
        }
    }
}
