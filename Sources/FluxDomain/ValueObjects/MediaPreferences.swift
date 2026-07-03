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

/// Preferências de mídia do usuário: ordem de codec na negociação SDP e
/// processamento de voz (cancelamento de eco, supressão de ruído, ganho).
/// Aplicadas na PRÓXIMA chamada — nunca mexem numa chamada em andamento.
public struct MediaPreferences: Equatable, Sendable {
    /// Codec anunciado primeiro na oferta SDP (o PABX decide respeitando a
    /// ordem). Na resposta, é o escolhido quando o remoto o oferece.
    public var preferredCodec: AudioCodecPreference
    /// Processamento de voz da Apple (Voice Processing I/O): cancelamento de
    /// eco acústico + supressão de ruído — um recurso único do sistema.
    public var voiceProcessingEnabled: Bool
    /// Controle automático de ganho do microfone (parte do Voice Processing;
    /// sem efeito quando `voiceProcessingEnabled == false`).
    public var autoGainControlEnabled: Bool

    public init(
        preferredCodec: AudioCodecPreference,
        voiceProcessingEnabled: Bool,
        autoGainControlEnabled: Bool
    ) {
        self.preferredCodec = preferredCodec
        self.voiceProcessingEnabled = voiceProcessingEnabled
        self.autoGainControlEnabled = autoGainControlEnabled
    }

    /// Padrão: PCMA primeiro (padrão nos PABX do mercado) e processamento de
    /// voz DESLIGADO — teste de campo (2026-07-03) teve chamada muda com o
    /// VPIO ligado por padrão; até validar em campo, o caminho de áudio
    /// padrão é o da V1 e o AEC/NS é opt-in nos Ajustes.
    public static let standard = MediaPreferences(
        preferredCodec: .pcma,
        voiceProcessingEnabled: false,
        autoGainControlEnabled: true
    )
}

/// Persistência das preferências de mídia (UserDefaults na implementação
/// real — valores simples, sem segredo; docs/05).
public protocol MediaPreferencesStoreProtocol: Sendable {
    func load() -> MediaPreferences
    func save(_ preferences: MediaPreferences)
}
