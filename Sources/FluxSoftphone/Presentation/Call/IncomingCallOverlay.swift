import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Overlay modal de chamada recebida (Ciclo 8). Não é dispensável por Esc —
/// só sai atendendo, recusando ou quando o chamador desiste (perdida).
struct IncomingCallOverlay: View {
    @EnvironmentObject private var appState: AppState
    let call: CallSession

    private var theme: BrandTheme { appState.brand.theme }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "phone.arrow.down.left.fill")
                    .font(.title2)
                    .foregroundStyle(theme.onPrimary)
                    .frame(width: 56, height: 56)
                    .background(theme.accent, in: Circle())

                VStack(spacing: 3) {
                    Text(call.remoteDisplayName ?? call.remoteNumber)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    if call.remoteDisplayName != nil {
                        Text(call.remoteNumber)
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Text("Recebendo chamada…")
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, 2)
                }

                HStack(spacing: 14) {
                    Button {
                        appState.rejectIncomingCall()
                    } label: {
                        Label("Recusar", systemImage: "phone.down.fill")
                            .frame(width: 118, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.danger)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("Recusar chamada")

                    Button {
                        appState.answerIncomingCall()
                    } label: {
                        Label("Atender", systemImage: "phone.fill")
                            .frame(width: 118, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.success)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Atender chamada")
                }
            }
            .padding(30)
            .frame(minWidth: 320)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chamada recebida de \(call.remoteDisplayName ?? call.remoteNumber)")
    }
}
