import SwiftUI
import UniformTypeIdentifiers
import FluxWhiteLabel

/// Editor do tema white label (docs/02_WHITE_LABEL_SYSTEM.md, nível 1 em
/// runtime): marca, cores, fundo e efeito de vidro, com preview em tempo
/// real ao lado. Toda mutação passa pelo `ThemeStore` — esta view não
/// persiste nada por conta própria.
struct BrandingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var isImportingLogo = false
    @State private var isImportingBackground = false
    @State private var isConfirmingReset = false
    /// Falhas de arquivo/imagem exibidas no topo do formulário.
    @State private var errorMessage: String?

    private var theme: WhiteLabelTheme { themeStore.theme }

    var body: some View {
        HStack(spacing: 0) {
            editorForm
                .frame(minWidth: 380, idealWidth: 430, maxWidth: 480)

            Divider()

            ThemePreviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Formulário

    private var editorForm: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            brandSection
            colorsSection
            backgroundSection
            glassSection
            resetSection
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImportingLogo,
            allowedContentTypes: [.image]
        ) { result in
            importImage(result) { data, ext in
                try themeStore.setLogo(data, fileExtension: ext)
            }
        }
        .fileImporter(
            isPresented: $isImportingBackground,
            allowedContentTypes: [.image]
        ) { result in
            importImage(result) { data, ext in
                try themeStore.setBackgroundImage(data, fileExtension: ext)
            }
        }
        .confirmationDialog(
            "Restaurar o tema padrão?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restaurar padrão", role: .destructive) {
                themeStore.resetToDefault()
                errorMessage = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Logo, cores, fundo e ajustes de vidro voltam ao padrão de \(appState.brand.appName). As personalizações atuais serão perdidas.")
        }
    }

    // MARK: - Marca

    private var brandSection: some View {
        Section("Marca") {
            TextField("Nome da marca", text: brandNameBinding, prompt: Text(appState.brand.appName))

            LabeledContent("Logo") {
                HStack(spacing: 10) {
                    BrandLogoView(fallbackName: appState.brand.appName, size: 28)
                    Button("Escolher…") { isImportingLogo = true }
                    if themeStore.logoData != nil {
                        Button("Remover") { themeStore.removeLogo() }
                    }
                }
            }

            Text("Sem logo customizado, o softphone usa a inicial da marca sobre a cor primária.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cores

    private var colorsSection: some View {
        Section("Cores") {
            ColorPicker("Cor primária", selection: colorBinding(\.primaryColor), supportsOpacity: false)
            ColorPicker("Cor secundária", selection: colorBinding(\.secondaryColor), supportsOpacity: false)
            ColorPicker("Cor de destaque", selection: colorBinding(\.accentColor), supportsOpacity: false)
            ColorPicker("Cor de texto", selection: colorBinding(\.textColor), supportsOpacity: false)

            if hasLowContrast {
                Label(
                    "Contraste baixo entre o texto e os painéis — ajuste a cor de texto ou a opacidade do vidro.",
                    systemImage: "eye.trianglebadge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Text("Verde, amarelo e vermelho de estados de chamada são fixos — convenção de telefonia, não identidade de marca.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Fundo

    private var backgroundSection: some View {
        Section("Fundo") {
            Picker("Estilo", selection: backgroundStyleBinding) {
                Text("Sólido").tag(WhiteLabelTheme.BackgroundStyle.solid)
                Text("Gradiente").tag(WhiteLabelTheme.BackgroundStyle.gradient)
                Text("Imagem").tag(WhiteLabelTheme.BackgroundStyle.image)
            }
            .pickerStyle(.segmented)

            switch theme.backgroundStyle {
            case .solid:
                ColorPicker("Cor do fundo", selection: colorBinding(\.backgroundColor), supportsOpacity: false)

            case .gradient:
                ColorPicker("Cor inicial", selection: gradientColorBinding(at: 0), supportsOpacity: false)
                if theme.gradientColors.count == 3 {
                    ColorPicker("Cor intermediária", selection: gradientColorBinding(at: 1), supportsOpacity: false)
                }
                ColorPicker(
                    "Cor final",
                    selection: gradientColorBinding(at: theme.gradientColors.count - 1),
                    supportsOpacity: false
                )
                Toggle("Usar terceira cor", isOn: thirdGradientColorBinding)

            case .image:
                LabeledContent("Imagem") {
                    HStack(spacing: 10) {
                        if let data = themeStore.backgroundImageData, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 46, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        Button(themeStore.backgroundImageData == nil ? "Escolher…" : "Trocar…") {
                            isImportingBackground = true
                        }
                        if themeStore.backgroundImageData != nil {
                            Button("Remover") { themeStore.removeBackgroundImage() }
                        }
                    }
                }
                if themeStore.backgroundImageData == nil {
                    Text("Sem imagem selecionada, o fundo usa o gradiente do tema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Vidro

    private var glassSection: some View {
        Section("Efeito de vidro") {
            labeledSlider(
                "Opacidade dos painéis",
                value: doubleBinding(\.glassOpacity),
                range: WhiteLabelTheme.glassOpacityRange,
                display: "\(Int((theme.glassOpacity * 100).rounded()))%"
            )
            labeledSlider(
                "Desfoque do fundo",
                value: doubleBinding(\.backgroundBlur),
                range: WhiteLabelTheme.backgroundBlurRange,
                display: "\(Int(theme.backgroundBlur.rounded())) pt"
            )
            labeledSlider(
                "Raio dos cantos",
                value: doubleBinding(\.cornerRadius),
                range: WhiteLabelTheme.cornerRadiusRange,
                display: "\(Int(theme.cornerRadius.rounded())) pt"
            )
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Restaurar

    private var resetSection: some View {
        Section {
            Button("Restaurar tema padrão", role: .destructive) {
                isConfirmingReset = true
            }
            .disabled(!themeStore.isCustomized)
        } footer: {
            Text("As alterações são salvas automaticamente e aplicadas em todo o softphone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var brandNameBinding: Binding<String> {
        Binding(
            get: { themeStore.theme.brandName },
            set: { value in themeStore.apply { $0.brandName = value } }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<WhiteLabelTheme, Double>) -> Binding<Double> {
        Binding(
            get: { themeStore.theme[keyPath: keyPath] },
            set: { value in themeStore.apply { $0[keyPath: keyPath] = value } }
        )
    }

    private var backgroundStyleBinding: Binding<WhiteLabelTheme.BackgroundStyle> {
        Binding(
            get: { themeStore.theme.backgroundStyle },
            set: { value in themeStore.apply { $0.backgroundStyle = value } }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<WhiteLabelTheme, String>) -> Binding<Color> {
        Binding(
            get: { WhiteLabelTheme.color(themeStore.theme[keyPath: keyPath]) },
            set: { color in
                guard let hex = Self.hexString(from: color) else { return }
                themeStore.apply { $0[keyPath: keyPath] = hex }
            }
        )
    }

    private func gradientColorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                let colors = themeStore.theme.gradientColors
                guard colors.indices.contains(index) else { return .gray }
                return WhiteLabelTheme.color(colors[index])
            },
            set: { color in
                guard let hex = Self.hexString(from: color) else { return }
                themeStore.apply {
                    guard $0.gradientColors.indices.contains(index) else { return }
                    $0.gradientColors[index] = hex
                }
            }
        )
    }

    /// Liga/desliga a parada intermediária do gradiente (2 ⇄ 3 cores).
    private var thirdGradientColorBinding: Binding<Bool> {
        Binding(
            get: { themeStore.theme.gradientColors.count >= 3 },
            set: { wantsThird in
                themeStore.apply {
                    if wantsThird, $0.gradientColors.count == 2 {
                        $0.gradientColors.insert($0.secondaryColor, at: 1)
                    } else if !wantsThird, $0.gradientColors.count == 3 {
                        $0.gradientColors.remove(at: 1)
                    }
                }
            }
        )
    }

    // MARK: - Contraste

    /// Aviso (não bloqueio) quando texto e painel de vidro ficam próximos em
    /// luminância — preserva a decisão do usuário sem deixar passar batido.
    private var hasLowContrast: Bool {
        guard let text = HexColorParser.parse(theme.textColor) else { return false }
        let textLuminance = HexColorParser.luminance(of: text)
        // Painel ≈ camada branca (opacidade do vidro) sobre o fundo.
        let panelLuminance = theme.glassOpacity + (1 - theme.glassOpacity) * theme.backgroundLuminance
        return abs(textLuminance - panelLuminance) < 0.35
    }

    // MARK: - Importação de imagem

    /// Lê a imagem escolhida (com escopo de segurança para sandbox), valida
    /// que é decodificável e delega a gravação ao store.
    private func importImage(
        _ result: Result<URL, Error>,
        store: (Data, String) throws -> Void
    ) {
        errorMessage = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard NSImage(data: data) != nil else {
                errorMessage = "O arquivo selecionado não é uma imagem válida."
                return
            }
            try store(data, url.pathExtension)
        } catch ThemeStore.StoreError.imageTooLarge {
            errorMessage = "Imagem muito grande — o limite é \(ThemeStore.maxImageBytes / (1024 * 1024)) MB."
        } catch {
            errorMessage = "Não foi possível carregar a imagem selecionada."
        }
    }

    /// Converte a cor escolhida no ColorPicker para hex sRGB (`#RRGGBB`).
    private static func hexString(from color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return HexColorParser.hexString(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent
        )
    }
}
