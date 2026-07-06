import SwiftUI
import FluxWhiteLabel

/// Modo compacto: o app se transforma só no "aparelho" — o discador
/// personalizado flutuando direto no desktop. A janela é transparente
/// (WindowChromeConfigurator): nada de moldura quadrada em volta dos cantos
/// arredondados; o fundo do tema vive dentro do corpo do aparelho.
///
/// Reusa as views validadas em campo (DialerView, IncomingCallOverlay) —
/// nenhuma lógica de chamada duplicada: uma chamada continua 100%
/// controlável (atender, recusar, mute, DTMF, encerrar) dentro do próprio
/// `DialerView` (status discreto no header + botão Ligar/Encerrar
/// unificado + mute no lugar do backspace durante a chamada). A
/// `ActiveCallBar` NÃO aparece aqui — no modo completo ela cobre qualquer
/// seção da janela (feedback pedido em campo: 2026-07-06 — no compacto,
/// onde a única tela É o discador, ela só duplicava o que o aparelho já
/// mostra).
/// Volta ao modo completo pelo botão no canto do aparelho ou ⇧⌘M.
struct CompactModeView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCompactMode: Bool

    /// Tamanho fixo da janela compacta — o shell (350 pt) + respiro para a
    /// sombra na área transparente.
    private static let windowSize = CGSize(width: 410, height: 640)

    var body: some View {
        DialerView(onExpandRequest: { isCompactMode = false })
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
