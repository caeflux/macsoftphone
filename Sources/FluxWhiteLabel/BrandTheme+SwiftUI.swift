import SwiftUI

/// Ponte do tema declarativo para SwiftUI. Cor inválida no JSON cai em cinza —
/// visível o bastante para ser notada em QA, sem quebrar o app.
public extension BrandTheme {
    var primary: Color { color(primaryColor) }
    var accent: Color { color(accentColor) }
    var success: Color { color(successColor) }
    var warning: Color { color(warningColor) }
    var danger: Color { color(dangerColor) }
    var background: Color { color(backgroundColor) }
    var surface: Color { color(surfaceColor) }
    var textPrimary: Color { color(textPrimaryColor) }
    var textSecondary: Color { color(textSecondaryColor) }

    /// Cor legível sobre `primary`: a declarada no JSON ou, na ausência,
    /// preto/branco decidido pela luminância da primária.
    var onPrimary: Color {
        if let onPrimaryColor {
            return color(onPrimaryColor)
        }
        guard let rgba = HexColorParser.parse(primaryColor) else { return .white }
        return HexColorParser.luminance(of: rgba) > 0.5 ? .black : .white
    }

    private func color(_ hex: String) -> Color {
        guard let rgba = HexColorParser.parse(hex) else { return Color.gray }
        return Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}
