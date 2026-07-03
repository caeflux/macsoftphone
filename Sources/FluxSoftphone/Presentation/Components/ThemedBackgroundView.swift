import SwiftUI
import FluxWhiteLabel

/// Fundo da área temática: sólido, gradiente ou imagem, conforme o tema
/// white label. O desfoque configurável é aplicado AQUI (camada de fundo);
/// o vidro dos painéis usa Material do sistema por cima — juntos formam o
/// glassmorphism sem custo de renderização por painel.
struct ThemedBackgroundView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    private var theme: WhiteLabelTheme { themeStore.theme }

    var body: some View {
        GeometryReader { proxy in
            backgroundLayer(size: proxy.size)
                .blur(radius: theme.backgroundBlur)
                // O blur esvazia as bordas; a leve escala re-preenche o quadro.
                .scaleEffect(theme.backgroundBlur > 0 ? 1 + theme.backgroundBlur / 100 : 1)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func backgroundLayer(size: CGSize) -> some View {
        switch theme.backgroundStyle {
        case .solid:
            theme.background
        case .gradient:
            gradient
        case .image:
            if let data = themeStore.backgroundImageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    // Véu escuro discreto: painéis de vidro e texto leem bem
                    // mesmo sobre fotos claras ou ruidosas.
                    .overlay(Color.black.opacity(0.18))
            } else {
                // Imagem configurada mas indisponível → gradiente do tema.
                gradient
            }
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: theme.gradientStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
