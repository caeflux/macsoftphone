import Foundation

/// Erros do serviço de dispositivos de áudio.
public enum AudioDeviceServiceError: Error, Equatable, Sendable {
    case deviceNotFound(id: String)
}

/// Contrato do serviço de dispositivos de áudio (docs/01_ARCHITECTURE.md,
/// evoluído no Ciclo 9: async + preferência consultável; `nil` = padrão do
/// sistema). Com a engine simulada a preferência é apenas persistida; a
/// engine real (Ciclo 5) passa a aplicá-la no fluxo de mídia.
public protocol AudioDeviceServiceProtocol: Sendable {
    func listInputDevices() async -> [AudioDevice]
    func listOutputDevices() async -> [AudioDevice]
    /// Define o dispositivo preferido; `nil` volta ao padrão do sistema.
    func setInputDevice(_ id: String?) async throws
    func setOutputDevice(_ id: String?) async throws
    func preferredInputDeviceId() async -> String?
    func preferredOutputDeviceId() async -> String?
}
