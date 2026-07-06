import SwiftUI
import AppKit
import FluxWhiteLabel

/// Aplica o logo do tema como ícone do app no Dock, em runtime.
///
/// O logo é composto num "squircle" preenchido com a cor primária do tema —
/// assim um logo de qualquer proporção (largo, redondo, transparente) vira
/// um ícone com cara de app macOS. Sem logo customizado, volta ao ícone do
/// bundle. O ícone ESTÁTICO do .app (Finder/Launchpad) é por marca no
/// pipeline de release — Ciclo 12; aqui é só o Dock do app em execução.
enum DockIconApplier {
    @MainActor
    static func apply(theme: WhiteLabelTheme, logoData: Data?) {
        guard let logoData, let logo = NSImage(data: logoData) else {
            // nil restaura o ícone padrão do bundle.
            NSApp.applicationIconImage = nil
            return
        }
        NSApp.applicationIconImage = iconImage(logo: logo, background: NSColor(theme.primary))
    }

    private static func iconImage(logo: NSImage, background: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Proporções do ícone macOS: margem de ~5% (ícones do sistema não
        // sangram até a borda) e cantos a ~22,5% do lado.
        let canvas = NSRect(origin: .zero, size: size)
        let iconRect = canvas.insetBy(dx: size.width * 0.05, dy: size.height * 0.05)
        let path = NSBezierPath(
            roundedRect: iconRect,
            xRadius: iconRect.width * 0.225,
            yRadius: iconRect.width * 0.225
        )
        background.setFill()
        path.fill()

        // Logo centrado em até 96% do quadro (pedido de campo: +48% sobre os
        // 65% originais), proporção preservada — quase full-bleed no squircle.
        let logoSize = logo.size
        guard logoSize.width > 0, logoSize.height > 0 else { return image }
        let maxSide = iconRect.width * 0.96
        let scale = min(maxSide / logoSize.width, maxSide / logoSize.height)
        let drawSize = NSSize(width: logoSize.width * scale, height: logoSize.height * scale)
        let origin = NSPoint(
            x: canvas.midX - drawSize.width / 2,
            y: canvas.midY - drawSize.height / 2
        )
        logo.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        return image
    }
}
