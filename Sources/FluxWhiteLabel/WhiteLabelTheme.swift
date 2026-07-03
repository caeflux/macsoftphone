import Foundation

/// Tema white label editável em runtime — camada de personalização POR CIMA
/// do `BrandTheme` embarcado no `brand-config.json` (que segue sendo a
/// identidade padrão da marca e o fallback de todo campo).
///
/// Persistido em JSON pelo `ThemeStore`; o formato é o contrato futuro de
/// exportação/importação de temas entre instalações (docs/02_WHITE_LABEL_SYSTEM.md).
/// Imagens (logo, fundo) são referenciadas por nome de arquivo relativo ao
/// diretório do tema — nunca por caminho absoluto frágil.
public struct WhiteLabelTheme: Codable, Equatable, Sendable {
    public enum BackgroundStyle: String, Codable, CaseIterable, Sendable {
        case solid
        case gradient
        case image
    }

    /// Nome exibido no topo do softphone. Vazio → UI usa o appName da marca.
    public var brandName: String
    /// Arquivo de logo dentro do diretório do tema (gerido pelo `ThemeStore`).
    public var logoFileName: String?
    /// Cor principal da marca (superfícies de destaque, base do gradiente).
    public var primaryColor: String
    /// Cor de apoio (paradas intermediárias de gradiente, detalhes).
    public var secondaryColor: String
    /// Cor de interação (botões, links, estados ativos).
    public var accentColor: String
    /// Cor do texto principal sobre os painéis de vidro.
    public var textColor: String
    public var backgroundStyle: BackgroundStyle
    /// Fundo sólido (usado quando `backgroundStyle == .solid`).
    public var backgroundColor: String
    /// 2 ou 3 cores do gradiente (usadas quando `backgroundStyle == .gradient`).
    public var gradientColors: [String]
    /// Arquivo da imagem de fundo (usado quando `backgroundStyle == .image`).
    public var backgroundImageFileName: String?
    /// Opacidade da camada de vidro dos painéis (0.15–0.95).
    public var glassOpacity: Double
    /// Desfoque aplicado ao fundo, em pontos (0–40).
    public var backgroundBlur: Double
    /// Raio dos cantos do shell do softphone (12–48); os componentes internos
    /// derivam raios proporcionais.
    public var cornerRadius: Double
    public var updatedAt: Date

    public static let glassOpacityRange: ClosedRange<Double> = 0.15...0.95
    public static let backgroundBlurRange: ClosedRange<Double> = 0...40
    public static let cornerRadiusRange: ClosedRange<Double> = 12...48

    public init(
        brandName: String,
        logoFileName: String? = nil,
        primaryColor: String,
        secondaryColor: String,
        accentColor: String,
        textColor: String,
        backgroundStyle: BackgroundStyle,
        backgroundColor: String,
        gradientColors: [String],
        backgroundImageFileName: String? = nil,
        glassOpacity: Double,
        backgroundBlur: Double,
        cornerRadius: Double,
        updatedAt: Date
    ) {
        self.brandName = brandName
        self.logoFileName = logoFileName
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.accentColor = accentColor
        self.textColor = textColor
        self.backgroundStyle = backgroundStyle
        self.backgroundColor = backgroundColor
        self.gradientColors = gradientColors
        self.backgroundImageFileName = backgroundImageFileName
        self.glassOpacity = glassOpacity
        self.backgroundBlur = backgroundBlur
        self.cornerRadius = cornerRadius
        self.updatedAt = updatedAt
    }

    /// Tema padrão derivado da marca embarcada — é o "Restaurar padrão".
    /// `updatedAt` fixo em `.distantPast` para a comparação de customização
    /// ser determinística.
    public static func defaultTheme(for brand: BrandConfig) -> WhiteLabelTheme {
        let theme = brand.theme
        return WhiteLabelTheme(
            brandName: brand.appName,
            primaryColor: theme.primaryColor,
            secondaryColor: theme.textSecondaryColor,
            accentColor: theme.accentColor,
            textColor: theme.textPrimaryColor,
            backgroundStyle: .gradient,
            backgroundColor: theme.backgroundColor,
            gradientColors: [theme.primaryColor, theme.accentColor],
            glassOpacity: 0.7,
            backgroundBlur: 0,
            cornerRadius: 32,
            updatedAt: .distantPast
        )
    }

    // MARK: - Codable tolerante

    /// Decodificação tolerante: campo ausente/estranho cai no padrão neutro em
    /// vez de rejeitar o arquivo inteiro — um tema exportado por versão futura
    /// (com campos novos) continua importável aqui.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WhiteLabelTheme.defaultTheme(for: .neutralFallback)
        brandName = try container.decodeIfPresent(String.self, forKey: .brandName) ?? fallback.brandName
        logoFileName = try container.decodeIfPresent(String.self, forKey: .logoFileName)
        primaryColor = try container.decodeIfPresent(String.self, forKey: .primaryColor) ?? fallback.primaryColor
        secondaryColor = try container.decodeIfPresent(String.self, forKey: .secondaryColor) ?? fallback.secondaryColor
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? fallback.accentColor
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor) ?? fallback.textColor
        backgroundStyle = try container.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? fallback.backgroundStyle
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor) ?? fallback.backgroundColor
        gradientColors = try container.decodeIfPresent([String].self, forKey: .gradientColors) ?? fallback.gradientColors
        backgroundImageFileName = try container.decodeIfPresent(String.self, forKey: .backgroundImageFileName)
        glassOpacity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .glassOpacity) ?? fallback.glassOpacity,
            to: Self.glassOpacityRange
        )
        backgroundBlur = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? fallback.backgroundBlur,
            to: Self.backgroundBlurRange
        )
        cornerRadius = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? fallback.cornerRadius,
            to: Self.cornerRadiusRange
        )
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Validação

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidColor(String)
        case invalidGradientCount(Int)
    }

    /// Todas as cores declaradas, para validação em lote (mesmo padrão do
    /// `BrandTheme.allColors`).
    public var allColors: [String] {
        [primaryColor, secondaryColor, accentColor, textColor, backgroundColor] + gradientColors
    }

    /// Falha alto em cor inválida ou gradiente fora de 2–3 paradas — usado na
    /// importação de tema, para arquivo malformado não virar tela cinza.
    public func validate() throws {
        for hex in allColors where HexColorParser.parse(hex) == nil {
            throw ValidationError.invalidColor(hex)
        }
        guard (2...3).contains(gradientColors.count) else {
            throw ValidationError.invalidGradientCount(gradientColors.count)
        }
    }

    // MARK: - Resolução para o tema da marca

    /// Projeta as cores customizadas sobre o `BrandTheme` embarcado. Cores
    /// semânticas (sucesso/aviso/perigo) NÃO são personalizáveis — verde de
    /// "atender" e vermelho de "encerrar" são convenção de telefonia, não marca.
    public func resolvedBrandTheme(base: BrandTheme) -> BrandTheme {
        BrandTheme(
            primaryColor: primaryColor,
            accentColor: accentColor,
            successColor: base.successColor,
            warningColor: base.warningColor,
            dangerColor: base.dangerColor,
            backgroundColor: backgroundStyle == .solid ? backgroundColor : base.backgroundColor,
            surfaceColor: base.surfaceColor,
            textPrimaryColor: textColor,
            textSecondaryColor: secondaryTextColor,
            onPrimaryColor: nil
        )
    }

    /// Texto secundário derivado do principal com alpha reduzido — mantém a
    /// hierarquia tipográfica coerente com qualquer cor de texto escolhida.
    public var secondaryTextColor: String {
        guard let rgba = HexColorParser.parse(textColor) else { return textColor }
        return HexColorParser.hexString(
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: 0.65
        )
    }

    /// Compara ignorando `updatedAt` — decide se "Restaurar padrão" tem o que
    /// restaurar.
    public func isEquivalent(to other: WhiteLabelTheme) -> Bool {
        var lhs = self
        var rhs = other
        lhs.updatedAt = .distantPast
        rhs.updatedAt = .distantPast
        return lhs == rhs
    }
}

public extension HexColorParser {
    /// Formata componentes (0–1) como `#RRGGBB`, ou `#RRGGBBAA` se alpha < 1.
    /// Inverso de `parse` — usado pelo editor para gravar cor escolhida no tema.
    static func hexString(red: Double, green: Double, blue: Double, alpha: Double = 1) -> String {
        func byte(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        if alpha >= 1 {
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }
        return String(format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }
}
