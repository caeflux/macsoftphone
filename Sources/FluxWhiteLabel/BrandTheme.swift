import Foundation

/// Cores da marca em hex (`#RRGGBB` ou `#RRGGBBAA`), como declaradas no JSON.
/// A conversão para `SwiftUI.Color` fica em `BrandTheme+SwiftUI.swift`;
/// aqui só dados, para o tema ser testável sem UI.
public struct BrandTheme: Codable, Equatable, Sendable {
    public let primaryColor: String
    public let accentColor: String
    public let successColor: String
    public let warningColor: String
    public let dangerColor: String
    public let backgroundColor: String
    public let surfaceColor: String
    public let textPrimaryColor: String
    public let textSecondaryColor: String
    /// Cor de texto/ícone sobre `primaryColor`. Opcional no JSON: quando
    /// ausente, é calculada por luminância — marca com primária clara não
    /// pode render texto invisível.
    public let onPrimaryColor: String?

    public init(
        primaryColor: String,
        accentColor: String,
        successColor: String,
        warningColor: String,
        dangerColor: String,
        backgroundColor: String,
        surfaceColor: String,
        textPrimaryColor: String,
        textSecondaryColor: String,
        onPrimaryColor: String? = nil
    ) {
        self.primaryColor = primaryColor
        self.accentColor = accentColor
        self.successColor = successColor
        self.warningColor = warningColor
        self.dangerColor = dangerColor
        self.backgroundColor = backgroundColor
        self.surfaceColor = surfaceColor
        self.textPrimaryColor = textPrimaryColor
        self.textSecondaryColor = textSecondaryColor
        self.onPrimaryColor = onPrimaryColor
    }

    /// Tema neutro do fallback — tons de cinza corporativos, sem identidade.
    public static let neutral = BrandTheme(
        primaryColor: "#1F2937",
        accentColor: "#374151",
        successColor: "#16A34A",
        warningColor: "#D97706",
        dangerColor: "#DC2626",
        backgroundColor: "#F9FAFB",
        surfaceColor: "#FFFFFF",
        textPrimaryColor: "#111827",
        textSecondaryColor: "#6B7280"
    )

    /// Todas as cores declaradas, para validação em lote.
    public var allColors: [String] {
        var colors = [
            primaryColor, accentColor, successColor, warningColor, dangerColor,
            backgroundColor, surfaceColor, textPrimaryColor, textSecondaryColor
        ]
        if let onPrimaryColor {
            colors.append(onPrimaryColor)
        }
        return colors
    }
}

/// Parser de cor hex — função pura, testável sem SwiftUI.
public enum HexColorParser {
    public struct RGBA: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double
    }

    /// Luminância relativa aproximada (0 = preto, 1 = branco), para decidir
    /// se texto sobre a cor deve ser claro ou escuro.
    public static func luminance(of rgba: RGBA) -> Double {
        0.2126 * rgba.red + 0.7152 * rgba.green + 0.0722 * rgba.blue
    }

    /// Aceita `#RRGGBB` e `#RRGGBBAA` (com ou sem `#`). Retorna `nil` se inválido.
    public static func parse(_ hex: String) -> RGBA? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              value.allSatisfy(\.isHexDigit),
              let number = UInt64(value, radix: 16)
        else { return nil }

        if value.count == 6 {
            return RGBA(
                red: Double((number >> 16) & 0xFF) / 255,
                green: Double((number >> 8) & 0xFF) / 255,
                blue: Double(number & 0xFF) / 255,
                alpha: 1
            )
        }
        return RGBA(
            red: Double((number >> 24) & 0xFF) / 255,
            green: Double((number >> 16) & 0xFF) / 255,
            blue: Double((number >> 8) & 0xFF) / 255,
            alpha: Double(number & 0xFF) / 255
        )
    }
}
