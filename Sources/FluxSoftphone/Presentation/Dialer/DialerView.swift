import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Discador (Ciclo 6): campo de destino com suporte a colar, teclado
/// numérico, apagar e ligar respeitando o estado de registro.
/// A tela de chamada completa (duração, mute, DTMF) chega no Ciclo 7 —
/// aqui só um indicador mínimo com Encerrar, para nenhuma chamada do mock
/// ficar presa sem controle.
struct DialerView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var numberFieldFocused: Bool

    /// O número vive no AppState — sobrevive à troca de seção e recebe
    /// pré-preenchimento do redial no histórico.
    private var number: String { appState.dialerNumber }

    private var theme: BrandTheme { appState.brand.theme }

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
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            numberField

            if isDTMFMode {
                VStack(spacing: 3) {
                    hint("Em chamada — o teclado envia dígitos DTMF.")
                    if !appState.dtmfDigitsSent.isEmpty {
                        Text(appState.dtmfDigitsSent)
                            .font(.title3.monospaced())
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

            keypad

            controls

            Spacer(minLength: 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
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

    // MARK: - Campo de destino

    private var numberField: some View {
        TextField("Número ou ramal", text: $appState.dialerNumber)
            .textFieldStyle(.plain)
            .font(.system(size: 30, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.textPrimary)
            .multilineTextAlignment(.center)
            .focused($numberFieldFocused)
            .onSubmit { call() }
            .frame(maxWidth: 320)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .accessibilityLabel("Número ou ramal de destino")
    }

    // MARK: - Teclado

    private static let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach(Self.keys, id: \.self) { row in
                HStack(spacing: 10) {
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
                .font(.title2.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 64, height: 52)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tecla \(key)")
    }

    // MARK: - Ações

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                if !number.isEmpty { appState.dialerNumber.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.title3)
                    .frame(width: 64, height: 44)
            }
            // Em modo DTMF não há o que apagar — dígito enviado é enviado.
            .disabled(number.isEmpty || isDTMFMode)
            .accessibilityLabel("Apagar último dígito")

            Button {
                call()
            } label: {
                Label("Ligar", systemImage: "phone.fill")
                    .font(.headline)
                    .frame(width: 148, height: 44)
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
    }
}
