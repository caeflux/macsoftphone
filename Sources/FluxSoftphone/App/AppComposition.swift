import Foundation
import FluxDomain
import FluxInfrastructure
import FluxWhiteLabel

/// Raiz de composição: monta as dependências concretas e entrega o AppState.
/// Único lugar do app que INSTANCIA implementações de infraestrutura
/// (engines, stores). Exceção transversal: logging (`AppLog`) pode ser
/// importado por qualquer camada do app — nunca engines ou stores.
@MainActor
enum AppComposition {
    static func makeAppState() -> AppState {
        let brand = loadBrand()
        let credentialsStore = KeychainCredentialsStore(service: keychainService(for: brand))
        let callHistoryRepository = FileCallHistoryRepository(directory: dataDirectory(for: brand))
        let diagnosticLog = DiagnosticLog()
        return AppState(
            brand: brand,
            sipClient: makeSIPClient(brand: brand, diagnosticLog: diagnosticLog),
            diagnosticLog: diagnosticLog,
            credentialsStore: credentialsStore,
            callHistoryRepository: callHistoryRepository,
            audioDeviceService: CoreAudioDeviceService(),
            microphonePermissionService: AVFMicrophonePermissionService()
        )
    }

    /// Store do tema white label editável, persistido dentro do container
    /// da marca (`…/<brandId>/theme/`). Injetado como EnvironmentObject —
    /// a UI reage a edições em tempo real (docs/02_WHITE_LABEL_SYSTEM.md).
    static func makeThemeStore() -> ThemeStore {
        let brand = loadBrand()
        return ThemeStore(
            directory: dataDirectory(for: brand).appendingPathComponent("theme", isDirectory: true),
            defaultTheme: .defaultTheme(for: brand)
        )
    }

    /// `Application Support/<bundle>/<brandId>/` — dados locais separados
    /// por marca, como as credenciais (docs/05_SECURITY_PRIVACY.md).
    private static func dataDirectory(for brand: BrandConfig) -> URL {
        let base = Bundle.main.bundleIdentifier ?? "dev.softphone.local"
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent(base, isDirectory: true)
            .appendingPathComponent(brand.brandId, isDirectory: true)
    }

    /// O app usa exclusivamente a engine SIP real. A engine simulada
    /// (MockSIPClient) existe apenas na suíte de testes — decisão de
    /// produto após confusão em campo: "Registrado (simulação)" parecia
    /// funcionalidade quebrada, não recurso de desenvolvimento.
    private static func makeSIPClient(
        brand: BrandConfig,
        diagnosticLog: DiagnosticLog
    ) -> any SIPClientProtocol {
        // User-Agent vem da marca — nada hardcoded.
        let product = brand.appName.replacingOccurrences(of: " ", with: "")
        return NativeSIPClient(
            userAgent: "\(product)/\(AppInfo.versionLabel)",
            diagnostics: { diagnosticLog.append($0) }
        )
    }

    /// Serviço Keychain único por marca — uma marca nunca enxerga
    /// credenciais de outra (docs/05_SECURITY_PRIVACY.md).
    private static func keychainService(for brand: BrandConfig) -> String {
        let base = Bundle.main.bundleIdentifier ?? "dev.softphone.local"
        return "\(base).\(brand.brandId).sip-account"
    }

    /// Cache da marca: `makeAppState` e `makeThemeStore` precisam da MESMA
    /// configuração — carregar duas vezes poderia divergir em erro parcial.
    private static var cachedBrand: BrandConfig?

    private static func loadBrand() -> BrandConfig {
        if let cachedBrand { return cachedBrand }
        let brand: BrandConfig
        do {
            brand = try BrandLoader.loadBundled()
            AppLog.whiteLabel.info("Marca carregada: \(brand.brandId, privacy: .public)")
        } catch {
            AppLog.whiteLabel.error(
                "Falha ao carregar brand-config embarcado; usando fallback neutro: \(String(describing: error), privacy: .public)"
            )
            brand = .neutralFallback
        }
        cachedBrand = brand
        return brand
    }
}
