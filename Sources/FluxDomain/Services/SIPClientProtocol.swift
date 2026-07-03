import Foundation

/// Evento publicado pela engine SIP para a camada de aplicação
/// (docs/03_SIP_AUDIO_CALL_ENGINE.md). A UI nunca consome isso diretamente —
/// apenas view models/AppState.
public enum SIPEvent: Equatable, Sendable {
    case registrationChanged(RegistrationState)
    case incomingCall(CallSession)
    case callStateChanged(CallSession)
    case audioRouteChanged
    case error(SIPClientError)
}

/// Erros da engine SIP. Semânticos, sem texto de UI.
public enum SIPClientError: Error, Equatable, Sendable {
    case notConfigured
    case notRegistered
    case alreadyInCall
    case authenticationFailed
    case networkUnavailable
    case serverUnreachable
    case invalidDestination
    case callNotFound(id: String)
    /// A engine atual ainda não implementa esta operação (ex.: DTMF).
    case notSupported
    /// O servidor recusou com um motivo próprio (ex.: rota bloqueada no
    /// PABX). O texto vem do servidor e deve chegar ao usuário — "falha"
    /// genérica esconde problemas que são de configuração, não do app.
    case serverRejected(code: Int, reason: String)
    case engineFailure(code: Int)
}

/// Contrato da engine SIP (docs/01_ARCHITECTURE.md).
///
/// Qualquer implementação — mock ou biblioteca real — fica atrás deste
/// protocolo. Trocar a engine não pode exigir mudança em UI ou domínio.
public protocol SIPClientProtocol: Sendable {
    /// Fluxo de eventos da engine. Consumidor único (AppState/coordinator).
    var events: AsyncStream<SIPEvent> { get }

    func configure(account: SIPAccount) async throws
    func register() async throws
    func unregister() async
    @discardableResult
    func makeCall(to destination: String) async throws -> CallSession
    func answer(callId: String) async throws
    func reject(callId: String) async throws
    func hangup(callId: String) async throws
    func sendDTMF(callId: String, digit: Character) async throws
    func setMuted(_ muted: Bool) async
}
