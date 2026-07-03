import SwiftUI
import FluxWhiteLabel

/// Seções da janela principal (docs/04_UI_UX_GUIDELINES.md).
enum MainSection: String, CaseIterable, Identifiable {
    case overview
    case dialer
    case history
    case settings
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Visão geral"
        case .dialer: return "Discador"
        case .history: return "Histórico"
        case .settings: return "Ajustes"
        case .diagnostics: return "Diagnóstico"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.needle"
        case .dialer: return "circle.grid.3x3.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    /// Seções visíveis respeitam as feature flags da marca.
    private var visibleSections: [MainSection] {
        MainSection.allCases.filter { section in
            switch section {
            case .history: return appState.brand.features.callHistory
            case .diagnostics: return appState.brand.features.diagnostics
            case .overview, .dialer, .settings: return true
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Barra de chamada ativa acompanha o usuário em
                    // qualquer seção — a chamada nunca fica "escondida".
                    if let call = appState.activeCall, call.state.isLive {
                        ActiveCallBar(call: call)
                    }
                }
        }
        .navigationTitle(appState.brand.appName)
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RegistrationStatusBadge(
                    state: appState.registrationState,
                    theme: appState.brand.theme
                )
            }
        }
        .overlay {
            if let call = appState.activeCall, call.state == .incoming {
                IncomingCallOverlay(call: call)
            }
        }
    }

    private var sidebar: some View {
        List(visibleSections, selection: $appState.selectedSection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    /// Identificação discreta da marca no rodapé da sidebar.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appState.brand.appName)
                .font(.caption.weight(.semibold))
            if !appState.brand.companyName.isEmpty {
                Text(appState.brand.companyName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedSection ?? .overview {
        case .overview:
            OverviewView()
        case .dialer:
            DialerView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
}
