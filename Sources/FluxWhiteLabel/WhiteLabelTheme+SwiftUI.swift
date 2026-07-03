import SwiftUI

/// Ponte do tema white label para SwiftUI — mesmo contrato do
/// `BrandTheme+SwiftUI`: cor inválida cai em cinza visível, nunca quebra.
public extension WhiteLabelTheme {
    var primary: Color { Self.color(primaryColor) }
    var secondary: Color { Self.color(secondaryColor) }
    var accent: Color { Self.color(accentColor) }
    var text: Color { Self.color(textColor) }
    var background: Color { Self.color(backgroundColor) }

    /// Paradas do gradiente de fundo, na ordem declarada.
    var gradientStops: [Color] {
        gradientColors.map { Self.color($0) }
    }

    /// Cor legível sobre `primary`, decidida por luminância.
    var onPrimary: Color {
        guard let rgba = HexColorParser.parse(primaryColor) else { return .white }
        return HexColorParser.luminance(of: rgba) > 0.5 ? .black : .white
    }

    /// Luminância média do fundo efetivo (sólido ou gradiente) — usada pelo
    /// editor para avisar quando o contraste com o texto ficou baixo.
    var backgroundLuminance: Double {
        let hexes: [String]
        switch backgroundStyle {
        case .solid: hexes = [backgroundColor]
        case .gradient, .image: hexes = gradientColors
        }
        let values = hexes.compactMap(HexColorParser.parse).map(HexColorParser.luminance)
        guard !values.isEmpty else { return 0.5 }
        return values.reduce(0, +) / Double(values.count)
    }

    static func color(_ hex: String) -> Color {
        guard let rgba = HexColorParser.parse(hex) else { return .gray }
        return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
