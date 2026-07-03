import SwiftUI
import FluxWhiteLabel

/// Modo compacto: o app se transforma só no "aparelho" — o discador
/// personalizado flutuando direto no desktop. A janela é transparente
/// (WindowChromeConfigurator): nada de moldura quadrada em volta dos cantos
/// arredondados; o fundo do tema vive dentro do corpo do aparelho.
///
/// Reusa as views validadas em campo (DialerView, ActiveCallBar,
/// IncomingCallOverlay) — nenhuma lógica de chamada duplicada: uma chamada
/// continua 100% controlável (atender, recusar, mute, DTMF, encerrar).
/// Volta ao modo completo pelo botão no canto do aparelho ou ⇧⌘M.
struct CompactModeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore
    @Binding var isCompactMode: Bool

    /// Tamanho fixo da janela compacta — o shell (350 pt) + respiro para a
    /// sombra na área transparente.
    private static let windowSize = CGSize(width: 410, height: 640)

    var body: some View {
        DialerView(onExpandRequest: { isCompactMode = false })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Mesma barra de chamada do modo completo, como pílula
                // flutuante — a chamada nunca fica sem controle.
                if let call = appState.activeCall, call.state.isLive {
                    ActiveCallBar(call: call)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 10)
                }
            }
            .overlay {
                if let call = appState.activeCall, call.state == .incoming {
                    // Sem véu escuro: em janela transparente ele viraria um
                    // quadrado sobre o desktop.
                    IncomingCallOverlay(call: call, showsBackdrop: false)
                }
            }
            .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }
}
