import Foundation

/// Direção da chamada.
public enum CallDirection: String, Codable, Equatable, Sendable {
    case incoming
    case outgoing
}

/// Estado de uma chamada (docs/03_SIP_AUDIO_CALL_ENGINE.md).
public enum CallState: Equatable, Sendable {
    case idle
    case incoming
    case dialing
    case ringing
    case active
    case held
    case ending
    case ended(reason: CallEndReason?)
    case failed(error: CallFailureReason)

    /// Indica se a chamada ainda ocupa o usuário (para bloquear nova discagem, etc).
    public var isLive: Bool {
        switch self {
        case .incoming, .dialing, .ringing, .active, .held, .ending:
            return true
        case .idle, .ended, .failed:
            return false
        }
    }
}

/// Por que a chamada terminou.
public enum CallEndReason: String, Codable, Equatable, Sendable {
    case localHangup
    case remoteHangup
    case rejected
    case missed
    case cancelled
}

/// Por que a chamada falhou antes de completar.
public enum CallFailureReason: Equatable, Sendable {
    case notRegistered
    case invalidDestination
    case networkUnavailable
    case serverError
    case unknown
}
