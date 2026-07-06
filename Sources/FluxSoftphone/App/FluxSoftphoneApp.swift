import SwiftUI

@main
struct FluxSoftphoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppComposition.makeAppState()
    @StateObject private var themeStore = AppComposition.makeThemeStore()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .environmentObject(themeStore)
                .task { appState.start() }
                // Ícone do Dock acompanha o logo/cor do tema, ao vivo.
                .task { DockIconApplier.apply(theme: themeStore.theme, logoData: themeStore.logoData) }
                .onChange(of: themeStore.logoData) {
                    DockIconApplier.apply(theme: themeStore.theme, logoData: themeStore.logoData)
                }
                .onChange(of: themeStore.theme.primaryColor) {
                    DockIconApplier.apply(theme: themeStore.theme, logoData: themeStore.logoData)
                }
                // O tema white label define apenas paleta clara; sem forçar
                // a aparência, o dark mode do sistema pinta textos padrão de
                // branco sobre as superfícies claras do tema (texto invisível).
                // Remover quando BrandTheme ganhar variante escura.
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 980, height: 660)
        // A janela segue as restrições do conteúdo: no modo compacto trava
        // no tamanho do "aparelho"; no completo, respeita os mínimos e cresce.
        .windowResizability(.contentSize)
        // Sem barra de título: no modo compacto a janela é transparente e só
        // o "aparelho" aparece (a faixa de título pintaria um retângulo no
        // topo); no completo, a toolbar unificada segue normal, sem o texto.
        .windowStyle(.hiddenTitleBar)
    }
}

/// Necessário para a janela aparecer em primeiro plano quando o app roda
/// via `swift run` (sem bundle .app). Com bundle assinado isso é inócuo.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Força aparência clara no nível do AppKt — mais confiável que o
        // modificador SwiftUI para garantir que o tema white label (só claro)
        // não seja pintado sobre o dark mode do sistema (texto invisível).
        // Remover quando BrandTheme ganhar variante escura por marca.
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}
