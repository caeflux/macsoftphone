import Testing
import Foundation
import FluxDomain
@testable import FluxInfrastructure

@Suite("UserDefaultsMediaPreferencesStore")
struct MediaPreferencesStoreTests {
    /// Suite exclusiva por teste — sem interferência entre execuções.
    private func makeStore() -> (UserDefaultsMediaPreferencesStore, suite: String) {
        let suite = "media-prefs-tests-\(UUID().uuidString)"
        return (UserDefaultsMediaPreferencesStore(suiteName: suite), suite)
    }

    private func cleanup(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @Test("sem nada persistido, carrega o padrão comercial")
    func loadsStandardWhenEmpty() {
        let (store, suite) = makeStore()
        defer { cleanup(suite) }

        #expect(store.load() == .standard)
        // Padrão = V1 validada em campo: PCMU primeiro na oferta e VP
        // desligado (incidentes de chamada muda em 2026-07-03).
        #expect(store.load().preferredCodec == .pcmu)
        #expect(!store.load().voiceProcessingEnabled)
        #expect(store.load().autoGainControlEnabled)
    }

    @Test("save/load faz round-trip completo")
    func saveLoadRoundTrip() {
        let (store, suite) = makeStore()
        defer { cleanup(suite) }

        let custom = MediaPreferences(
            preferredCodec: .pcmu,
            voiceProcessingEnabled: false,
            autoGainControlEnabled: false
        )
        store.save(custom)

        #expect(store.load() == custom)
    }

    @Test("valor de codec desconhecido no defaults cai no padrão")
    func unknownCodecFallsBackToStandard() {
        let (store, suite) = makeStore()
        defer { cleanup(suite) }

        UserDefaults(suiteName: suite)?.set("g729", forKey: "media.preferredCodec")
        #expect(store.load().preferredCodec == MediaPreferences.standard.preferredCodec)
    }
}
