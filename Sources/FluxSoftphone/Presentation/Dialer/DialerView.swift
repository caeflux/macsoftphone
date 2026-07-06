import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Discador (Ciclo 6): campo de destino com suporte a colar, teclado
/// numérico, apagar e ligar respeitando o estado de registro.
/// Com chamada ativa, o mesmo teclado vira o teclado DTMF (Ciclo 11).
///
/// Etapa white label: a interface vive dentro de um `GlassPhoneShell` — um
/// "smartphone" de vidro flutuando sobre o fundo do tema. Apenas a moldura
/// visual mudou; toda a lógica de discagem/DTMF/foco é a validada em campo.
struct DialerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore
    @FocusState private var numberFieldFocused: Bool

    /// Definido pelo modo compacto: o fundo do tema passa a viver dentro do
    /// corpo do aparelho (janela transparente, nada de "moldura quadrada")
    /// e o botão de expandir aparece no canto do shell chamando este closure.
    var onExpandRequest: (() -> Void)? = nil

    private var isCompactPresentation: Bool { onExpandRequest != nil }

    /// O número vive no AppState — sobrevive à troca de seção e recebe
    /// pré-preenchimento do redial no histórico.
    private var number: String { appState.dialerNumber }

    /// Cores brand-aware (texto, sucesso, destaque) já com o tema white
    /// label projetado por cima da marca embarcada.
    private var theme: BrandTheme {
        themeStore.theme.resolvedBrandTheme(base: appState.brand.theme)
    }

    /// Tema white label bruto, para os traços de vidro (opacidade, raio).
    private var wlTheme: WhiteLabelTheme { themeStore.theme }

    private var isRegistered: Bool {
        appState.registrationState == .registered
    }

    private var hasLiveCall: Bool {
        appState.activeCall?.state.isLive == true
    }

    /// Com chamada ATIVA, o mesmo teclado vira o teclado DTMF —
    /// dígitos (tela ou teclado físico) são enviados para a URA/destino.
    private var isDTMFMode: Bool {
        appState.activeCall?.state == .active
    }

    private var canCall: Bool {
        isRegistered && !hasLiveCall
            && PhoneNumberNormalizer.isDiallable(PhoneNumberNormalizer.normalize(number))
    }

    var body: some View {
        ZStack {
            // No modo compacto a janela é transparente — o fundo do tema é
            // embutido no shell, e nada é pintado ao redor do aparelho.
            if !isCompactPresentation {
                ThemedBackgroundView()
            }

            // Centraliza o "aparelho" quando há espaço; rola quando a janela
            // está baixa (ex.: com a barra de chamada ativa aberta).
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack {
                        GlassPhoneShell(embedsThemedBackdrop: isCompactPresentation) {
                            phoneBody
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        // Teclado físico disca direto: o campo fica focado ao entrar na
        // seção (digitou → aparece; Enter → liga, via onSubmit).
        .onAppear { numberFieldFocused = true }
        .onChange(of: hasLiveCall) {
            if !hasLiveCall { numberFieldFocused = true }
        }
        .onChange(of: appState.dialerNumber) { oldValue, newValue in
            guard newValue.count == oldValue.count + 1, let last = newValue.last else { return }
            if isDTMFMode {
                // Teclado físico em chamada: o dígito vira DTMF e o número
                // discado fica intacto.
                appState.dialerNumber = oldValue
                appState.sendDTMF(last)
            } else {
                // Tom local por dígito acrescentado (teclado físico OU botão).
                appState.playKeyTone(last)
            }
        }
    }

    /// Conteúdo do "aparelho": header de marca, campo, avisos, teclado, ações.
    private var phoneBody: some View {
        VStack(spacing: 14) {
            brandHeader

            numberField

            statusArea

            keypad

            controls
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .overlay(alignment: .topTrailing) {
            if let onExpandRequest {
                expandButton(onExpandRequest)
                    .padding(12)
            }
        }
    }

    /// Volta ao modo completo — só existe na apresentação compacta.
    private func expandButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(wlTheme.text.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(wlTheme.text.opacity(0.07), in: Circle())
                .overlay {
                    Circle().strokeBorder(wlTheme.text.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .help("Voltar ao modo completo (⇧⌘M)")
        .accessibilityLabel("Voltar ao modo completo")
    }

    // MARK: - Header de marca (logo configurado no topo do softphone)

    private var brandHeader: some View {
        VStack(spacing: 6) {
            BrandLogoView(fallbackName: appState.brand.appName, size: 46)
            Text(wlTheme.displayBrandName(fallback: appState.brand.appName))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(RegistrationStatePresentation.color(for: appState.registrationState, theme: theme))
                    .frame(width: 7, height: 7)
                Text(RegistrationStatePresentation.label(for: appState.registrationState))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status SIP: \(RegistrationStatePresentation.label(for: appState.registrationState))")
        }
        .frame(maxWidth: .infinity)
        .background {
            // Janela compacta não tem barra de título: o header do aparelho
            // é a alça de arrasto (margem lateral preserva o botão expandir).
            if isCompactPresentation {
                WindowChromeConfigurator.WindowDragHandle()
                    .padding(.horizontal, 44)
            }
        }
    }

    // MARK: - Campo de destino

    private var numberField: some View {
        TextField("Número ou ramal", text: $appState.dialerNumber)
            .textFieldStyle(.plain)
            .font(.system(size: 27, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.textPrimary)
            .multilineTextAlignment(.center)
            .focused($numberFieldFocused)
            .onSubmit { call() }
            .frame(maxWidth: 280)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(wlTheme.text.opacity(0.18))
                    .frame(height: 1)
            }
            .accessibilityLabel("Número ou ramal de destino")

    }

    /// Área de avisos com altura mínima estável — o shell não "pula" quando
    /// uma mensagem aparece ou some.
    @ViewBuilder
    private var statusArea: some View {
        Group {
            if isDTMFMode {
                VStack(spacing: 3) {
                    hint("Em chamada — o teclado envia dígitos DTMF.")
                    if !appState.dtmfDigitsSent.isEmpty {
                        Text(appState.dtmfDigitsSent)
                            .font(.callout.monospaced())
                            .foregroundStyle(theme.textPrimary)
                    }
                }
            } else if hasLiveCall {
                hint("Chamada em andamento — use a barra inferior para controlá-la.")
            } else if !isRegistered {
                hint("Registre a conta para fazer chamadas.")
            } else if let message = appState.userMessage {
                hint(message)
            }
        }
        .frame(minHeight: 30)
    }

    // MARK: - Teclado

    private static let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    /// Raio das teclas proporcional ao raio do shell configurado no tema.
    private var keyCornerRadius: CGFloat {
        min(wlTheme.cornerRadius * 0.4, 16)
    }

    private var keypad: some View {
        VStack(spacing: 9) {
            ForEach(Self.keys, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(row, id: \.self) { key in
                        keypadButton(key)
                    }
                }
            }
        }
    }

    private func keypadButton(_ key: String) -> some View {
        Button {
            if isDTMFMode, let digit = key.first {
                appState.sendDTMF(digit)
            } else {
                appState.dialerNumber.append(key)
            }
            // Clique no botão rouba o foco do campo; devolve para o
            // teclado físico continuar funcionando.
            numberFieldFocused = true
        } label: {
            Text(key)
                .font(.title3.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 62, height: 48)
                // Preenchimento derivado da cor de texto: adapta-se a tema
                // claro ou escuro mantendo as teclas visíveis sobre o vidro.
                .background(
                    wlTheme.text.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
                        .strokeBorder(wlTheme.text.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tecla \(key)")
    }

    // MARK: - Ações

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if !number.isEmpty { appState.dialerNumber.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.title3)
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 62, height: 42)
                    .background(
                        wlTheme.text.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
                            .strokeBorder(wlTheme.text.opacity(0.12))
                    }
            }
            .buttonStyle(.plain)
            // Em modo DTMF não há o que apagar — dígito enviado é enviado.
            .disabled(number.isEmpty || isDTMFMode)
            .opacity(number.isEmpty || isDTMFMode ? 0.4 : 1)
            .accessibilityLabel("Apagar último dígito")

            Button {
                call()
            } label: {
                Label("Ligar", systemImage: "phone.fill")
                    .font(.headline)
                    .frame(width: 140, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.success)
            .disabled(!canCall)
            .accessibilityLabel("Ligar para o número digitado")
        }
    }

    private func call() {
        guard canCall else { return }
        appState.startOutgoingCall(to: number)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(theme.textSecondary)
            .multilineTextAlignment(.center)
    }
}
