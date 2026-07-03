import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Apresentação do estado de registro: rótulo e cor do tema.
/// O estado visual não depende só de cor — o texto sempre acompanha
/// (acessibilidade, docs/04_UI_UX_GUIDELINES.md).
enum RegistrationStatePresentation {
    static func label(for state: RegistrationState) -> String {
        switch state {
        case .idle: return "Sem conta"
        case .registering: return "Registrando…"
        case .registered: return "Registrado"
        case .disconnected: return "Desconectado"
        case .expired: return "Registro expirado"
        case .failed(let reason):
            switch reason {
            case .authenticationFailed: return "Falha de autenticação"
            case .networkUnavailable: return "Sem conexão"
            case .serverUnreachable: return "Servidor indisponível"
            case .timeout: return "Tempo esgotado"
            case .unknown: return "Erro de registro"
            }
        }
    }

    static func color(for state: RegistrationState, theme: BrandTheme) -> Color {
        switch state {
        case .registered: return theme.success
        case .registering: return theme.warning
        case .failed: return theme.danger
        case .idle, .disconnected, .expired: return theme.textSecondary
        }
    }
}

/// Selo de status SIP exibido no header da janela.
struct RegistrationStatusBadge: View {
    let state: RegistrationState
    let theme: BrandTheme

    private var label: String {
        RegistrationStatePresentation.label(for: state)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(RegistrationStatePresentation.color(for: state, theme: theme))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status SIP: \(label)")
    }
}
