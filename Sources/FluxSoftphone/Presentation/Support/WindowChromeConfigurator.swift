import SwiftUI
import AppKit

/// Ajustes de NSWindow que o SwiftUI não expõe. No modo compacto a janela
/// fica transparente e sem título — só o "aparelho" arredondado aparece,
/// sem moldura quadrada ao redor — e pode ser arrastada por qualquer área.
/// Ao voltar ao modo completo, tudo é restaurado.
///
/// Montado como `.background` invisível da view de cada modo; não desenha
/// nada. A aplicação acontece em `viewDidMoveToWindow` — no primeiro launch
/// (app já abre compacto) a janela ainda não existe durante o `makeNSView`.
struct WindowChromeConfigurator: NSViewRepresentable {
    let isCompact: Bool

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.isCompact = isCompact
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        nsView.isCompact = isCompact
    }

    /// Alça de arrasto para a janela sem título do modo compacto: a área que
    /// a recebe (header do aparelho) move a janela com `performDrag`, sem
    /// roubar cliques do resto da interface.
    struct WindowDragHandle: NSViewRepresentable {
        func makeNSView(context: Context) -> DragView { DragView() }
        func updateNSView(_ nsView: DragView, context: Context) {}

        final class DragView: NSView {
            override func mouseDown(with event: NSEvent) {
                window?.performDrag(with: event)
            }
        }
    }

    /// View invisível que aplica a configuração assim que entra numa janela
    /// (e reaplica quando o modo muda).
    final class WindowObservingView: NSView {
        var isCompact = false {
            didSet { applyToWindow() }
        }

        // nonisolated(unsafe): o deinit (nonisolated no Swift 6) só REMOVE o
        // observer; nenhum acesso concorrente real acontece.
        private nonisolated(unsafe) var keyObserver: NSObjectProtocol?

        deinit {
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyToWindow()
            // No primeiro launch o SwiftUI ainda mexe no chrome da janela
            // DEPOIS deste callback — reaplica no próximo turno do runloop e
            // quando a janela vira key, vencendo a última escrita.
            DispatchQueue.main.async { [weak self] in self?.applyToWindow() }
            if let window {
                if let keyObserver {
                    NotificationCenter.default.removeObserver(keyObserver)
                }
                keyObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    // Fila .main garantida acima; o closure só não é
                    // MainActor estaticamente.
                    MainActor.assumeIsolated {
                        self?.applyToWindow()
                    }
                }
            }
        }

        private func applyToWindow() {
            guard let window else { return }
            window.isOpaque = !isCompact
            window.backgroundColor = isCompact ? .clear : .windowBackgroundColor
            window.titleVisibility = isCompact ? .hidden : .visible
            window.titlebarAppearsTransparent = isCompact
            window.titlebarSeparatorStyle = isCompact ? .none : .automatic
            // A sombra da janela desenharia o contorno do retângulo
            // transparente; no modo compacto quem tem sombra é o aparelho.
            window.hasShadow = !isCompact
            // NUNCA isMovableByWindowBackground: com NSHostingView ele engole
            // TODOS os cliques como arrasto (teclado do discador morto). O
            // arrasto no modo compacto é a alça explícita (WindowDragHandle).
            window.isMovableByWindowBackground = false
            // Launch direto no modo compacto pode herdar o NSToolbar
            // restaurado da sessão anterior (modo completo) — a faixa cinza
            // no topo. No modo completo o SwiftUI recria o toolbar sozinho.
            if isCompact {
                window.toolbar = nil
            }
            if isCompact {
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.styleMask.remove(.fullSizeContentView)
            }
        }
    }
}
