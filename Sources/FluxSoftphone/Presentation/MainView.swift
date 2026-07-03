import SwiftUI
import FluxWhiteLabel

/// Seções da janela principal (docs/04_UI_UX_GUIDELINES.md).
enum MainSection: String, CaseIterable, Identifiable {
    case overview
    case dialer
    case history
    case settings
    case branding
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Visão geral"
        case .dialer: return "Discador"
        case .history: return "Histórico"
        case .settings: return "Ajustes"
        case .branding: return "Aparência"
        case .diagnostics: return "Diagnóstico"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.needle"
        case .dialer: return "circle.grid.3x3.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .branding: return "paintbrush"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore
    /// Modo compacto: a janela vira só o discador personalizado. Persistido —
    /// quem usa o app como "aparelho" reabre direto no aparelho.
    @AppStorage("ui.compact-mode") private var isCompactMode = false

    /// Seções visíveis respeitam as feature flags da marca.
    private var visibleSections: [MainSection] {
        MainSection.allCases.filter { section in
            switch section {
            case .history: return appState.brand.features.callHistory
            case .diagnostics: return appState.brand.features.diagnostics
            case .overview, .dialer, .settings, .branding: return true
            }
        }
    }

    /// Nome exibido: o do tema white label, com fallback no da marca.
    private var displayName: String {
        themeStore.theme.displayBrandName(fallback: appState.brand.appName)
    }

    var body: some View {
        if isCompactMode {
            CompactModeView(isCompactMode: $isCompactMode)
                .navigationTitle(displayName)
                // Janela transparente: só o aparelho aparece, sem moldura.
                .background(WindowChromeConfigurator(isCompact: true))
        } else {
            fullModeBody
                .background(WindowChromeConfigurator(isCompact: false))
        }
    }

    private var fullModeBody: some View {
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
        .navigationTitle(displayName)
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RegistrationStatusBadge(
                    state: appState.registrationState,
                    theme: themeStore.theme.resolvedBrandTheme(base: appState.brand.theme)
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCompactMode = true
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Modo compacto — só o discador (⇧⌘M)")
                .accessibilityLabel("Entrar no modo compacto")
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
            Text(displayName)
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
        case .branding:
            BrandingSettingsView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
}
