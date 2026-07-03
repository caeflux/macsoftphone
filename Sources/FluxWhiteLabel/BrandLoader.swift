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
        guard let url = brandResourceBundle()?.url(forResource: "brand-config", withExtension: "json") else {
            throw BrandConfigError.resourceNotFound
        }
        return try load(from: url)
    }

    /// Localiza o bundle de recursos SEM usar `Bundle.module`: o accessor
    /// gerado pelo SwiftPM só olha a raiz do executável e o caminho ABSOLUTO
    /// de `.build` da máquina de desenvolvimento — num `.app` empacotado em
    /// outra máquina ele nunca acha o bundle e dá `fatalError`. Aqui a busca
    /// cobre os três contextos reais e falha graciosamente (fallback neutro):
    /// 1. `Contents/Resources` do `.app` (layout padrão de release, docs/08).
    /// 2. Diretório do executável (`swift run` coloca o bundle ao lado).
    /// 3. Ao lado do bundle de testes (`swift test`).
    private static func brandResourceBundle() -> Bundle? {
        let bundleName = "FluxSoftphone_FluxWhiteLabel.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleToken.self).resourceURL,
            Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        ]
        for candidate in candidates {
            guard let url = candidate?.appendingPathComponent(bundleName),
                  let bundle = Bundle(url: url),
                  bundle.url(forResource: "brand-config", withExtension: "json") != nil
            else { continue }
            return bundle
        }
        return nil
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

    /// Âncora de classe para `Bundle(for:)` — resolve o bundle que contém
    /// este código (o executável no app, o `.xctest` nos testes).
    private final class BundleToken {}

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
