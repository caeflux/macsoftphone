import Foundation
import AVFoundation
import FluxDomain

/// Permissão de microfone via AVFoundation/TCC.
///
/// Consultar o status é sempre seguro. SOLICITAR exige
/// `NSMicrophoneUsageDescription` no Info.plist — sem ele (executável de
/// desenvolvimento via `swift run`) o TCC mataria o processo, então o
/// serviço responde `.unsupported` em vez de pedir.
public struct AVFMicrophonePermissionService: MicrophonePermissionServiceProtocol {
    public init() {}

    public func currentStatus() async -> MicrophonePermissionStatus {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func requestAccess() async -> MicrophonePermissionStatus {
        guard canPrompt else { return .unsupported }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    private var canPrompt: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    private func map(_ status: AVAuthorizationStatus) -> MicrophonePermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return canPrompt ? .undetermined : .unsupported
        @unknown default: return .undetermined
        }
    }
}
