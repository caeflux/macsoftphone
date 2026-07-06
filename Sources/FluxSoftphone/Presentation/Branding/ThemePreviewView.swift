import SwiftUI
import FluxWhiteLabel

/// Preview em tempo real do softphone para o editor white label: um
/// smartphone em miniatura, estático (sem interação), lendo o MESMO
/// `ThemeStore` que a UI real — toda edição reflete aqui na hora.
struct ThemePreviewView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore

    private var theme: WhiteLabelTheme { themeStore.theme }

    private var resolvedTheme: BrandTheme {
        theme.resolvedBrandTheme(base: appState.brand.theme)
    }

    var body: some View {
        ZStack {
            ThemedBackgroundView()

            VStack(spacing: 12) {
                Text("Pré-visualização")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(previewLabelColor)

                GlassPhoneShell(width: 250) {
                    phoneContent
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                }
            }
            .padding(24)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Pré-visualização do tema do softphone")
    }

    /// Rótulo "Pré-visualização" fica sobre o fundo, não sobre vidro —
    /// claro em fundo escuro e vice-versa.
    private var previewLabelColor: Color {
        theme.backgroundLuminance > 0.5 ? .black.opacity(0.55) : .white.opacity(0.75)
    }

    private var phoneContent: some View {
        VStack(spacing: 14) {
            // Header: logo + marca + status de registro.
            VStack(spacing: 6) {
                BrandLogoView(fallbackName: appState.brand.appName, size: 108)
                Text(theme.displayBrandName(fallback: appState.brand.appName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                HStack(spacing: 5) {
                    Circle()
                        .fill(resolvedTheme.success)
                        .frame(width: 6, height: 6)
                    Text("Registrado")
                        .font(.caption2)
                        .foregroundStyle(theme.text.opacity(0.65))
                }
            }

            // Campo de número fictício.
            Text("0800 555 0100")
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.text)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.text.opacity(0.2))
                        .frame(height: 1)
                }

            // Teclado em miniatura.
            VStack(spacing: 7) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]], id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(row, id: \.self) { key in
                            Text(key)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(theme.text)
                                .frame(width: 44, height: 32)
                                .background(
                                    theme.text.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: keypadRadius, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: keypadRadius, style: .continuous)
                                        .strokeBorder(theme.text.opacity(0.1))
                                }
                        }
                    }
                }
            }

            // Botão de ligar (verde semântico) + destaque do tema.
            HStack(spacing: 8) {
                Label("Ligar", systemImage: "phone.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 30)
                    .background(resolvedTheme.success, in: Capsule())
                Image(systemName: "gearshape.fill")
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .background(theme.accent.opacity(0.14), in: Circle())
            }
        }
    }

    private var keypadRadius: CGFloat {
        min(theme.cornerRadius * 0.35, 14)
    }
}
