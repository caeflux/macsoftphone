import SwiftUI

@main
struct FluxSoftphoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppComposition.makeAppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .task { appState.start() }
                // O tema white label define apenas paleta clara; sem forçar
                // a aparência, o dark mode do sistema pinta textos padrão de
                // branco sobre as superfícies claras do tema (texto invisível).
                // Remover quando BrandTheme ganhar variante escura.
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 980, height: 660)
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
