import SwiftUI
import FluxWhiteLabel

/// "Corpo de smartphone" flutuante (docs/04_UI_UX_GUIDELINES.md, etapa white
/// label): contêiner vertical de cantos bem arredondados, superfície de vidro
/// translúcida, borda suave e sombra discreta. Encapsula a interface principal
/// do softphone sem saber nada de SIP — só visual.
struct GlassPhoneShell<Content: View>: View {
    @EnvironmentObject private var themeStore: ThemeStore
    /// Largura do corpo do "aparelho"; o padrão aproxima um celular em pé.
    var width: CGFloat = 350
    /// No modo compacto (janela transparente, sem fundo ao redor), o fundo do
    /// tema vive DENTRO do corpo do aparelho, recortado pelos cantos.
    var embedsThemedBackdrop = false
    @ViewBuilder let content: Content

    private var theme: WhiteLabelTheme { themeStore.theme }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: width)
            .background {
                ZStack {
                    if embedsThemedBackdrop {
                        ThemedBackgroundView()
                            .clipShape(shape)
                    }
                    // Material = blur real do que está atrás (glassmorphism);
                    // a camada branca controla a opacidade percebida do painel.
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(theme.glassOpacity))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 28, y: 16)
    }
}

/// Cartão de vidro para conteúdos fora do shell (cards da visão geral etc.).
/// Mesma linguagem visual do shell, raio proporcional ao do tema.
struct GlassCard<Content: View>: View {
    @EnvironmentObject private var themeStore: ThemeStore
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    private var theme: WhiteLabelTheme { themeStore.theme }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: min(theme.cornerRadius * 0.55, 20), style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(theme.glassOpacity))
                }
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }
}
