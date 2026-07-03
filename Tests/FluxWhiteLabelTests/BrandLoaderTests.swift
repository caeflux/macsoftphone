import Testing
import Foundation
@testable import FluxWhiteLabel

@Suite("BrandLoader")
struct BrandLoaderTests {
    @Test("config embarcado carrega e valida")
    func bundledConfigLoads() throws {
        let config = try BrandLoader.loadBundled()

        #expect(!config.brandId.isEmpty)
        #expect(!config.appName.isEmpty)
        #expect(!config.defaultSipDomain.isEmpty)
        #expect(config.features.manualSipLogin)
    }

    @Test("JSON malformado falha com invalidFormat")
    func malformedJSONFails() {
        let data = Data("{ not json".utf8)
        #expect(throws: BrandLoader.BrandConfigError.self) {
            try BrandLoader.decode(data)
        }
    }

    @Test("cor de tema inválida falha na validação")
    func invalidThemeColorFails() throws {
        let bundled = try BrandLoader.loadBundled()
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(bundled)
        ) as! [String: Any]
        var theme = json["theme"] as! [String: Any]
        theme["primaryColor"] = "azul"
        json["theme"] = theme
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: BrandLoader.BrandConfigError.invalidThemeColor("azul")) {
            try BrandLoader.decode(data)
        }
    }

    @Test("feature flags ausentes assumem false")
    func missingFlagsDefaultToFalse() throws {
        let json = """
        {
          "brandId": "revenda-x",
          "appName": "Fone X",
          "companyName": "Revenda X",
          "supportEmail": "s@x.com",
          "supportUrl": "https://x.com",
          "privacyUrl": "https://x.com/privacidade",
          "apiBaseUrl": "https://api.x.com",
          "provisioningBaseUrl": "https://prov.x.com",
          "defaultSipDomain": "sip.x.com",
          "theme": {
            "primaryColor": "#000000",
            "accentColor": "#0000FF",
            "successColor": "#00FF00",
            "warningColor": "#FFAA00",
            "dangerColor": "#FF0000",
            "backgroundColor": "#FFFFFF",
            "surfaceColor": "#FFFFFF",
            "textPrimaryColor": "#000000",
            "textSecondaryColor": "#555555"
          },
          "features": { "manualSipLogin": true }
        }
        """
        let config = try BrandLoader.decode(Data(json.utf8))

        #expect(config.features.manualSipLogin)
        #expect(!config.features.crmIntegration)
        #expect(!config.features.autoUpdate)
        #expect(!config.features.diagnostics)
    }
}
