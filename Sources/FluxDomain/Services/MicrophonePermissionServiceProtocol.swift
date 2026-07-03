import Foundation

/// Estado da permissão de microfone (docs/05_SECURITY_PRIVACY.md).
public enum MicrophonePermissionStatus: Equatable, Sendable {
    case granted
    case denied
    /// Bloqueado por política do sistema (MDM, controles parentais).
    case restricted
    case undetermined
    /// O build atual não pode solicitar permissão (ex.: executável de
    /// desenvolvimento sem bundle/Info.plist — pedir crasharia o processo).
    case unsupported
}

/// Contrato de permissão de microfone. Implementação real usa AVFoundation;
/// a UI nunca fala com TCC diretamente.
public protocol MicrophonePermissionServiceProtocol: Sendable {
    func currentStatus() async -> MicrophonePermissionStatus
    /// Solicita a permissão ao usuário quando possível; retorna o novo estado.
    func requestAccess() async -> MicrophonePermissionStatus
}
