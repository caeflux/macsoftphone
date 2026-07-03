import SwiftUI
import AppKit
import FluxDomain
import FluxWhiteLabel

/// Histórico completo (Ciclo 10): lista com filtro, ligar novamente,
/// copiar número e limpar.
struct HistoryView: View {
    private enum HistoryFilter: String, CaseIterable, Identifiable {
        case all
        case missed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Todas"
            case .missed: return "Perdidas"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var filter: HistoryFilter = .all
    @State private var isConfirmingClear = false

    private var filteredEntries: [CallHistoryEntry] {
        switch filter {
        case .all: return appState.callHistory
        case .missed: return appState.callHistory.filter { $0.outcome == .missed }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let message = appState.userMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if filteredEntries.isEmpty {
                emptyState
            } else {
                List(filteredEntries) { entry in
                    HistoryRow(entry: entry, theme: appState.brand.theme) {
                        appState.redial(entry)
                    }
                }
            }
        }
        .task { appState.refreshCallHistory() }
        .confirmationDialog(
            "Limpar todo o histórico?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Limpar histórico", role: .destructive) {
                appState.clearCallHistory()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Todos os registros de chamadas serão apagados deste computador.")
        }
    }

    private var header: some View {
        HStack {
            Picker("Filtro", selection: $filter) {
                ForEach(HistoryFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            Spacer()

            Button("Limpar", role: .destructive) {
                isConfirmingClear = true
            }
            .disabled(appState.callHistory.isEmpty)
            .help("Apagar todo o histórico de chamadas")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                filter == .missed ? "Sem chamadas perdidas" : "Sem chamadas",
                systemImage: "clock.arrow.circlepath"
            )
        } description: {
            Text(
                filter == .missed
                    ? "As chamadas não atendidas aparecerão aqui."
                    : "As chamadas realizadas e recebidas aparecerão aqui."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let entry: CallHistoryEntry
    let theme: BrandTheme
    let onRedial: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directionIcon)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName ?? entry.number)
                    .font(.body.weight(.medium))
                Text(outcomeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.startedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.outcome == .completed {
                    Text(DurationFormatter.format(entry.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onRedial()
            } label: {
                Image(systemName: "phone.fill")
                    .foregroundStyle(theme.success)
            }
            .buttonStyle(.borderless)
            .help("Ligar novamente para \(entry.number)")
            .accessibilityLabel("Ligar novamente para \(entry.number)")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Ligar novamente") { onRedial() }
            Button("Copiar número") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.number, forType: .string)
            }
        }
    }

    private var directionIcon: String {
        switch entry.direction {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        }
    }

    private var iconColor: Color {
        switch entry.outcome {
        case .missed, .failed: return theme.danger
        case .completed, .rejected, .cancelled: return theme.textSecondary
        }
    }

    private var outcomeLabel: String {
        switch entry.outcome {
        case .completed: return entry.direction == .outgoing ? "Realizada" : "Recebida"
        case .missed: return "Perdida"
        case .rejected: return "Recusada"
        case .cancelled: return "Cancelada"
        case .failed: return "Falhou"
        }
    }
}
