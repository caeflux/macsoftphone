import Foundation

/// Codec de áudio preferido para as chamadas. Só G.711 por enquanto —
/// PCMA (A-law) é o padrão em PABX brasileiros/europeus, PCMU (µ-law) o
/// norte-americano. Codecs futuros (G.722, Opus) entram aqui.
public enum AudioCodecPreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case pcma
    case pcmu

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pcma: return "G.711 A-law (PCMA)"
        case .pcmu: return "G.711 µ-law (PCMU)"
        }
    }
}

/// Preferências de mídia do usuário: ordem de codec na negociação SDP,
/// cancelamento de eco, supressão de silêncio (VAD) e ganho automático.
/// Aplicadas na PRÓXIMA chamada — nunca mexem numa chamada em andamento.
public struct MediaPreferences: Equatable, Sendable {
    /// Codec anunciado primeiro na oferta SDP (o PABX decide respeitando a
    /// ordem). Na resposta, é o escolhido quando o remoto o oferece.
    public var preferredCodec: AudioCodecPreference
    /// Cancelamento de eco acústico via Voice Processing I/O da Apple.
    /// O sistema embute redução de ruído junto — é um recurso único do macOS.
    public var echoCancellationEnabled: Bool
    /// Supressão de silêncio (VAD) no ENVIO: quando o usuário não está
    /// falando, o ruído de fundo não é transmitido (gate de energia local,
    /// independente do processamento de voz do sistema).
    public var silenceSuppressionEnabled: Bool
    /// Controle automático de ganho do microfone (parte do Voice Processing;
    /// sem efeito quando `echoCancellationEnabled == false`).
    public var autoGainControlEnabled: Bool

    public init(
        preferredCodec: AudioCodecPreference,
        echoCancellationEnabled: Bool,
        silenceSuppressionEnabled: Bool,
        autoGainControlEnabled: Bool
    ) {
        self.preferredCodec = preferredCodec
        self.echoCancellationEnabled = echoCancellationEnabled
        self.silenceSuppressionEnabled = silenceSuppressionEnabled
        self.autoGainControlEnabled = autoGainControlEnabled
    }

    /// Padrão = comportamento validado em campo da V1: oferta PCMU primeiro,
    /// eco e VAD DESLIGADOS. Qualquer desvio do caminho validado é opt-in
    /// nos Ajustes até provar-se em campo (incidentes de 2026-07-03).
    public static let standard = MediaPreferences(
        preferredCodec: .pcmu,
        echoCancellationEnabled: false,
        silenceSuppressionEnabled: false,
        autoGainControlEnabled: true
    )
}

/// Persistência das preferências de mídia (UserDefaults na implementação
/// real — valores simples, sem segredo; docs/05).
public protocol MediaPreferencesStoreProtocol: Sendable {
    func load() -> MediaPreferences
    func save(_ preferences: MediaPreferences)
}
