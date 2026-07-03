import Foundation

/// Transporte SIP suportado pela arquitetura (docs/03_SIP_AUDIO_CALL_ENGINE.md).
/// O MVP pode operar com UDP, mas a modelagem já contempla TLS.
public enum SIPTransport: String, Codable, Sendable, CaseIterable, Equatable {
    case udp
    case tcp
    case tls

    /// Porta padrão do transporte quando o usuário não informa uma.
    public var defaultPort: Int {
        switch self {
        case .udp, .tcp: return 5060
        case .tls: return 5061
        }
    }
}
