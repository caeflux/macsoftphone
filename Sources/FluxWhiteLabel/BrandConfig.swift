import Foundation

/// Configuração de marca carregada de `brand-config.json`
/// (docs/02_WHITE_LABEL_SYSTEM.md). Marca é configuração, não lógica.
public struct BrandConfig: Codable, Equatable, Sendable {
    public let brandId: String
    public let appName: String
    public let companyName: String
    public let supportEmail: String
    public let supportUrl: String
    public let privacyUrl: String
    public let apiBaseUrl: String
    public let provisioningBaseUrl: String
    public let defaultSipDomain: String
    public let theme: BrandTheme
    public let features: FeatureFlags

    public init(
        brandId: String,
        appName: String,
        companyName: String,
        supportEmail: String,
        supportUrl: String,
        privacyUrl: String,
        apiBaseUrl: String,
        provisioningBaseUrl: String,
        defaultSipDomain: String,
        theme: BrandTheme,
        features: FeatureFlags
    ) {
        self.brandId = brandId
        self.appName = appName
        self.companyName = companyName
        self.supportEmail = supportEmail
        self.supportUrl = supportUrl
        self.privacyUrl = privacyUrl
        self.apiBaseUrl = apiBaseUrl
        self.provisioningBaseUrl = provisioningBaseUrl
        self.defaultSipDomain = defaultSipDomain
        self.theme = theme
        self.features = features
    }

    /// Fallback neutro usado apenas se o `brand-config.json` embarcado estiver
    /// ausente ou corrompido. Sem marca de cliente: mantém o app utilizável
    /// para diagnóstico sem exibir identidade errada.
    public static let neutralFallback = BrandConfig(
        brandId: "neutral",
        appName: "Softphone",
        companyName: "",
        supportEmail: "",
        supportUrl: "",
        privacyUrl: "",
        apiBaseUrl: "",
        provisioningBaseUrl: "",
        defaultSipDomain: "",
        theme: .neutral,
        features: FeatureFlags()
    )
}

/// Feature flags por marca (docs/02_WHITE_LABEL_SYSTEM.md).
/// Chaves ausentes no JSON assumem `false` — um config parcial de revenda
/// nunca liga recurso por acidente.
public struct FeatureFlags: Codable, Equatable, Sendable {
    public var manualSipLogin: Bool
    public var provisioningLogin: Bool
    public var callHistory: Bool
    public var contacts: Bool
    public var crmIntegration: Bool
    public var autoUpdate: Bool
    public var diagnostics: Bool

    public init(
        manualSipLogin: Bool = false,
        provisioningLogin: Bool = false,
        callHistory: Bool = false,
        contacts: Bool = false,
        crmIntegration: Bool = false,
        autoUpdate: Bool = false,
        diagnostics: Bool = false
    ) {
        self.manualSipLogin = manualSipLogin
        self.provisioningLogin = provisioningLogin
        self.callHistory = callHistory
        self.contacts = contacts
        self.crmIntegration = crmIntegration
        self.autoUpdate = autoUpdate
        self.diagnostics = diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manualSipLogin = try container.decodeIfPresent(Bool.self, forKey: .manualSipLogin) ?? false
        provisioningLogin = try container.decodeIfPresent(Bool.self, forKey: .provisioningLogin) ?? false
        callHistory = try container.decodeIfPresent(Bool.self, forKey: .callHistory) ?? false
        contacts = try container.decodeIfPresent(Bool.self, forKey: .contacts) ?? false
        crmIntegration = try container.decodeIfPresent(Bool.self, forKey: .crmIntegration) ?? false
        autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? false
        diagnostics = try container.decodeIfPresent(Bool.self, forKey: .diagnostics) ?? false
    }
}
