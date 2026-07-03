import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Tela inicial do Ciclo 1: identidade da marca, estado do registro SIP e
/// controles da engine simulada para validar o fluxo de estados de ponta a ponta.
struct OverviewView: View {
    @EnvironmentObject private var appState: AppState

    private var theme: BrandTheme { appState.brand.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        .background(theme.background)
    }

    // MARK: - Marca

    private var brandHeader: some View {
        HStack(spacing: 14) {
            // Logo simbólica derivada da marca até o BrandAssets chegar (Ciclo 2).
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.primary)
                .frame(width: 52, height: 52)
                .overlay {
                    Text(appState.brand.appName.prefix(1))
                        .font(.title.weight(.bold))
                        .foregroundStyle(theme.onPrimary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.brand.appName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                if !appState.brand.companyName.isEmpty {
                    Text(appState.brand.companyName)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
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
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }

    private func userMessageBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(theme.danger)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

}
