import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Barra de chamada ativa, visível em qualquer seção da janela (Ciclo 7).
/// Mostra interlocutor, estado, duração, mute e encerrar
/// (docs/04_UI_UX_GUIDELINES.md — tela de chamada ativa).
struct ActiveCallBar: View {
    @EnvironmentObject private var appState: AppState
    let call: CallSession

    private var theme: BrandTheme { appState.brand.theme }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.callout)
                .foregroundStyle(theme.onPrimary)
                .frame(width: 34, height: 34)
                .background(theme.success, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(call.remoteDisplayName ?? call.remoteNumber)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                statusLine
            }

            Spacer()

            // Atalho para o discador — que, em chamada ativa, é o teclado
            // DTMF (mesmo teclado, modo contextual; nada de teclado extra).
            Button {
                appState.selectedSection = .dialer
            } label: {
                Image(systemName: "circle.grid.3x3")
                    .frame(width: 36, height: 30)
            }
            .help("Abrir o discador para enviar DTMF")
            .disabled(call.state != .active)
            .accessibilityLabel("Abrir discador para DTMF")

            Button {
                appState.toggleMute()
            } label: {
                Image(systemName: appState.isMuted ? "mic.slash.fill" : "mic.fill")
                    .frame(width: 36, height: 30)
            }
            .help(appState.isMuted ? "Reativar microfone" : "Silenciar microfone")
            .disabled(call.state != .active)
            .accessibilityLabel(appState.isMuted ? "Reativar microfone" : "Silenciar microfone")

            Button(role: .destructive) {
                appState.hangupActiveCall()
            } label: {
                Label("Encerrar", systemImage: "phone.down.fill")
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.danger)
            .accessibilityLabel("Encerrar chamada")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }

    /// Estado textual; quando conectada, mostra a duração correndo.
    @ViewBuilder
    private var statusLine: some View {
        if let connectedAt = call.connectedAt, call.state == .active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(DurationFormatter.format(context.date.timeIntervalSince(connectedAt)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
            }
        } else {
            Text(CallStatePresentation.label(for: call.state))
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }
}

/// Formata duração como mm:ss (ou h:mm:ss a partir de uma hora).
enum DurationFormatter {
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
