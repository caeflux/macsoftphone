import SwiftUI
import FluxWhiteLabel

/// Logo da marca no topo do softphone: imagem customizada do tema quando
/// existe; senão, placeholder neutro com a inicial do nome sobre a cor
/// primária (mesmo fallback usado desde o Ciclo 1).
struct BrandLogoView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    /// Nome de fallback quando o tema não define `brandName` (appName da marca).
    let fallbackName: String
    var size: CGFloat = 44

    private var displayName: String {
        themeStore.theme.displayBrandName(fallback: fallbackName)
    }

    var body: some View {
        if let data = themeStore.logoData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: size * 3)
                .frame(height: size)
                .accessibilityLabel("Logo de \(displayName)")
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(themeStore.theme.primary)
                .frame(width: size, height: size)
                .overlay {
                    Text(displayName.prefix(1).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(themeStore.theme.onPrimary)
                }
                .accessibilityLabel("Logo de \(displayName)")
        }
    }
}

extension WhiteLabelTheme {
    /// Nome exibível da marca: o do tema, ou o fallback se vazio/em branco.
    func displayBrandName(fallback: String) -> String {
        let trimmed = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
