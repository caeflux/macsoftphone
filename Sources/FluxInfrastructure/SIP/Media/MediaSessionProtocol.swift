import Foundation

/// Sessão de mídia de uma chamada (RTP + áudio). Criada por chamada e
/// descartada no encerramento. Abstraída para os testes do cliente SIP
/// rodarem sem hardware de áudio.
public protocol MediaSessionProtocol: Sendable {
    /// Porta RTP local, conhecida na criação (entra no SDP antes do start).
    var localRTPPort: Int { get }

    /// Inicia captura, envio e reprodução contra o destino negociado.
    func start(remoteHost: String, remotePort: Int, codec: G711Codec) async throws

    /// Redireciona o fluxo RTP para um novo destino/codec sem parar o áudio —
    /// re-INVITE de renegociação (ex.: PABX movendo a mídia) é rotina.
    func retarget(remoteHost: String, remotePort: Int, codec: G711Codec) async throws

    /// Payload type negociado do telephone-event (DTMF RFC 2833/4733);
    /// `nil` quando o remoto não o ofereceu.
    func setTelephoneEventPayloadType(_ payloadType: Int?) async

    /// Envia um dígito DTMF fora de banda. Lança se o telephone-event não
    /// foi negociado nesta chamada.
    func sendDTMF(digit: Character) async throws

    func setMuted(_ muted: Bool) async

    func stop() async
}

public enum MediaSessionError: Error, Equatable, Sendable {
    case socketUnavailable
    case invalidRemoteAddress(String)
    case audioEngineFailure(String)
    case dtmfNotNegotiated
    case invalidDTMFDigit(Character)
}
