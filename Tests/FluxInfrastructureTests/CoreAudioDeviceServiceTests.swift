import Testing
import Foundation
import FluxDomain
@testable import FluxInfrastructure

/// Testes contra o CoreAudio real da máquina (um Mac sempre tem ao menos
/// microfone e alto-falantes embutidos). Preferências usam uma suite de
/// UserDefaults exclusiva por teste.
@Suite("CoreAudioDeviceService")
struct CoreAudioDeviceServiceTests {
    private func makeService() -> CoreAudioDeviceService {
        CoreAudioDeviceService(suiteName: "dev.fluxsoftphone.tests.audio.\(UUID().uuidString)")
    }

    @Test("lista dispositivos de entrada e saída reais")
    func listsRealDevices() async {
        let service = makeService()
        let inputs = await service.listInputDevices()
        let outputs = await service.listOutputDevices()

        #expect(!inputs.isEmpty)
        #expect(!outputs.isEmpty)
        #expect(inputs.allSatisfy { $0.kind == .input && !$0.name.isEmpty && !$0.id.isEmpty })
        #expect(outputs.allSatisfy { $0.kind == .output && !$0.name.isEmpty && !$0.id.isEmpty })
        // O sistema sempre tem um dispositivo padrão de cada tipo.
        #expect(inputs.contains { $0.isDefault })
        #expect(outputs.contains { $0.isDefault })
    }

    @Test("preferência persiste e é consultável")
    func preferenceRoundtrip() async throws {
        let service = makeService()
        let inputs = await service.listInputDevices()
        let chosen = try #require(inputs.first)

        try await service.setInputDevice(chosen.id)
        #expect(await service.preferredInputDeviceId() == chosen.id)

        // `nil` volta ao padrão do sistema.
        try await service.setInputDevice(nil)
        #expect(await service.preferredInputDeviceId() == nil)
    }

    @Test("dispositivo inexistente é rejeitado sem alterar a preferência")
    func rejectsUnknownDevice() async throws {
        let service = makeService()

        await #expect(throws: AudioDeviceServiceError.deviceNotFound(id: "uid-inexistente")) {
            try await service.setOutputDevice("uid-inexistente")
        }
        #expect(await service.preferredOutputDeviceId() == nil)
    }
}
