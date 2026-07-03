import Foundation

/// Carrega a configuração de marca. O build padrão embarca o
/// `brand-config.json` da Flux como recurso; builds white label substituem
/// esse arquivo (e futuramente assets) sem tocar em código.
public enum BrandLoader {
    public enum BrandConfigError: Error, Equatable, Sendable {
        case resourceNotFound
        case invalidFormat(String)
        case invalidThemeColor(String)
    }

    /// Config embarcada no bundle (build padrão da marca).
    public static func loadBundled() throws -> BrandConfig {
        guard let url = Bundle.module.url(forResource: "brand-config", withExtension: "json") else {
            throw BrandConfigError.resourceNotFound
        }
        return try load(from: url)
    }

    /// Config a partir de arquivo externo (override por tenant, futuro
    /// provisionamento — docs/06_INTEGRATIONS_FLUX.md).
    public static func load(from url: URL) throws -> BrandConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BrandConfigError.resourceNotFound
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> BrandConfig {
        let config: BrandConfig
        do {
            config = try JSONDecoder().decode(BrandConfig.self, from: data)
        } catch {
            throw BrandConfigError.invalidFormat(String(describing: error))
        }
        try validate(config)
        return config
    }

    /// Garante que um config de marca malformado falhe alto no carregamento,
    /// não silenciosamente numa tela cinza.
    static func validate(_ config: BrandConfig) throws {
        for hex in config.theme.allColors where HexColorParser.parse(hex) == nil {
            throw BrandConfigError.invalidThemeColor(hex)
        }
    }
}
