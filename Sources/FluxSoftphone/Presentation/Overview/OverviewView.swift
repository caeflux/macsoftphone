import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Tela inicial: identidade da marca, estado do registro SIP e ações rápidas.
/// Etapa white label: cards de vidro sobre o fundo do tema; logo customizada
/// com fallback na inicial da marca.
struct OverviewView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore

    private var theme: BrandTheme {
        themeStore.theme.resolvedBrandTheme(base: appState.brand.theme)
    }

    var body: some View {
        ZStack {
            ThemedBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    brandHeader
                    statusCard
                    if let message = appState.userMessage {
                        userMessageBanner(message)
                    }
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Marca

    private var brandHeader: some View {
        GlassCard {
            HStack(spacing: 14) {
                BrandLogoView(fallbackName: appState.brand.appName, size: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text(themeStore.theme.displayBrandName(fallback: appState.brand.appName))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    if !appState.brand.companyName.isEmpty {
                        Text(appState.brand.companyName)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Conta SIP")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(RegistrationStatePresentation.color(for: appState.registrationState, theme: theme))
                        .frame(width: 10, height: 10)
                    Text(RegistrationStatePresentation.label(for: appState.registrationState))
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textPrimary)
                }

                if let account = appState.savedAccount {
                    LabeledContent("Conta") {
                        Text(account.uri)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .font(.callout)
                    .foregroundStyle(theme.textPrimary)

                    HStack(spacing: 10) {
                        if appState.registrationState != .registered {
                            Button("Registrar") { appState.registerSavedAccount() }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accent)
                                .disabled(appState.registrationState == .registering)
                        } else {
                            Button("Desregistrar") { appState.unregister() }
                        }
                        Button("Gerenciar conta") {
                            appState.selectedSection = .settings
                        }
                    }
                } else {
                    Text("Nenhuma conta SIP configurada.")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)

                    Button("Configurar conta SIP") {
                        appState.selectedSection = .settings
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func userMessageBanner(_ message: String) -> some View {
        GlassCard(padding: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
