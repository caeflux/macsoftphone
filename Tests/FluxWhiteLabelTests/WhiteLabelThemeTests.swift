import Testing
import Foundation
@testable import FluxWhiteLabel

@Suite("WhiteLabelTheme")
struct WhiteLabelThemeTests {
    private var brand: BrandConfig {
        BrandConfig(
            brandId: "flux",
            appName: "Flux Softphone",
            companyName: "Flux",
            supportEmail: "s@flux.net.br",
            supportUrl: "https://flux.net.br",
            privacyUrl: "https://flux.net.br/privacidade",
            apiBaseUrl: "https://api.flux.net.br",
            provisioningBaseUrl: "https://prov.flux.net.br",
            defaultSipDomain: "sip.flux.net.br",
            theme: .neutral,
            features: FeatureFlags()
        )
    }

    @Test("tema padrão deriva da marca embarcada")
    func defaultThemeDerivesFromBrand() {
        let theme = WhiteLabelTheme.defaultTheme(for: brand)

        #expect(theme.brandName == brand.appName)
        #expect(theme.primaryColor == brand.theme.primaryColor)
        #expect(theme.accentColor == brand.theme.accentColor)
        #expect(theme.textColor == brand.theme.textPrimaryColor)
        #expect(theme.backgroundStyle == .gradient)
        #expect(theme.gradientColors == [brand.theme.primaryColor, brand.theme.accentColor])
        #expect(theme.logoFileName == nil)
        #expect(theme.backgroundImageFileName == nil)
    }

    @Test("resolução projeta cores customizadas e preserva as semânticas")
    func resolutionMapsCustomColors() {
        var theme = WhiteLabelTheme.defaultTheme(for: brand)
        theme.primaryColor = "#123456"
        theme.accentColor = "#654321"
        theme.textColor = "#222222"

        let resolved = theme.resolvedBrandTheme(base: brand.theme)

        #expect(resolved.primaryColor == "#123456")
        #expect(resolved.accentColor == "#654321")
        #expect(resolved.textPrimaryColor == "#222222")
        // Verde/amarelo/vermelho são convenção de telefonia, não marca.
        #expect(resolved.successColor == brand.theme.successColor)
        #expect(resolved.warningColor == brand.theme.warningColor)
        #expect(resolved.dangerColor == brand.theme.dangerColor)
        // Texto secundário derivado do principal com alpha.
        #expect(resolved.textSecondaryColor == "#222222A6")
    }

    @Test("fundo sólido projeta backgroundColor; gradiente mantém o da base")
    func resolutionBackgroundDependsOnStyle() {
        var theme = WhiteLabelTheme.defaultTheme(for: brand)
        theme.backgroundColor = "#ABCDEF"

        theme.backgroundStyle = .solid
        #expect(theme.resolvedBrandTheme(base: brand.theme).backgroundColor == "#ABCDEF")

        theme.backgroundStyle = .gradient
        #expect(theme.resolvedBrandTheme(base: brand.theme).backgroundColor == brand.theme.backgroundColor)
    }

    @Test("codable round-trip preserva o tema")
    func codableRoundTrip() throws {
        var theme = WhiteLabelTheme.defaultTheme(for: brand)
        theme.brandName = "Revenda X"
        theme.backgroundStyle = .image
        theme.backgroundImageFileName = "background-image.jpg"
        theme.gradientColors = ["#111111", "#222222", "#333333"]
        theme.glassOpacity = 0.5
        theme.backgroundBlur = 12
        theme.cornerRadius = 24
        theme.updatedAt = Date(timeIntervalSince1970: 1_750_000_000)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WhiteLabelTheme.self, from: encoder.encode(theme))

        #expect(decoded == theme)
    }

    @Test("JSON parcial decodifica com padrões neutros")
    func partialJSONDecodesWithDefaults() throws {
        let json = ##"{ "brandName": "Fone X", "primaryColor": "#101010" }"##
        let decoded = try JSONDecoder().decode(WhiteLabelTheme.self, from: Data(json.utf8))

        #expect(decoded.brandName == "Fone X")
        #expect(decoded.primaryColor == "#101010")
        #expect(decoded.backgroundStyle == .gradient)
        #expect(WhiteLabelTheme.glassOpacityRange.contains(decoded.glassOpacity))
        #expect(WhiteLabelTheme.cornerRadiusRange.contains(decoded.cornerRadius))
    }

    @Test("valores fora da faixa são grampeados na decodificação")
    func outOfRangeValuesAreClamped() throws {
        let json = #"{ "glassOpacity": 7, "backgroundBlur": -3, "cornerRadius": 500 }"#
        let decoded = try JSONDecoder().decode(WhiteLabelTheme.self, from: Data(json.utf8))

        #expect(decoded.glassOpacity == WhiteLabelTheme.glassOpacityRange.upperBound)
        #expect(decoded.backgroundBlur == WhiteLabelTheme.backgroundBlurRange.lowerBound)
        #expect(decoded.cornerRadius == WhiteLabelTheme.cornerRadiusRange.upperBound)
    }

    @Test("validação rejeita cor inválida e gradiente fora de 2–3 paradas")
    func validationRejectsBadValues() {
        var theme = WhiteLabelTheme.defaultTheme(for: brand)
        theme.primaryColor = "azul"
        #expect(throws: WhiteLabelTheme.ValidationError.invalidColor("azul")) {
            try theme.validate()
        }

        theme.primaryColor = "#101010"
        theme.gradientColors = ["#101010"]
        #expect(throws: WhiteLabelTheme.ValidationError.invalidGradientCount(1)) {
            try theme.validate()
        }
    }

    @Test("isEquivalent ignora updatedAt")
    func equivalenceIgnoresTimestamp() {
        let base = WhiteLabelTheme.defaultTheme(for: brand)
        var touched = base
        touched.updatedAt = Date(timeIntervalSince1970: 1_750_000_000)

        #expect(touched.isEquivalent(to: base))

        touched.brandName = "Outra"
        #expect(!touched.isEquivalent(to: base))
    }

    @Test("hexString é inverso de parse")
    func hexStringRoundTrip() {
        #expect(HexColorParser.hexString(red: 1, green: 0, blue: 0) == "#FF0000")
        #expect(HexColorParser.hexString(red: 0, green: 0, blue: 0, alpha: 0.5) == "#00000080")

        let rgba = HexColorParser.parse("#3C6EF5")!
        let formatted = HexColorParser.hexString(
            red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha
        )
        #expect(formatted == "#3C6EF5")
    }
}
