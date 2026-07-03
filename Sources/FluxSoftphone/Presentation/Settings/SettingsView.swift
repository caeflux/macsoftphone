import SwiftUI
import FluxDomain
import FluxWhiteLabel

/// Ajustes agrupados (docs/04_UI_UX_GUIDELINES.md): Conta SIP, Áudio e Sobre.
/// Áudio e Diagnóstico ganham conteúdo real nos Ciclos 9 e 11.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var isEditingAccount = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            // Erros de persistência/registro precisam aparecer AQUI, onde as
            // ações acontecem — não só na Visão geral.
            if let message = appState.userMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            if appState.brand.features.manualSipLogin {
                accountSection
            }
            audioSection
            aboutSection
        }
        .formStyle(.grouped)
        .task { appState.refreshAudioState() }
    }

    // MARK: - Áudio

    private var audioSection: some View {
        Section("Áudio") {
            microphonePermissionRow

            devicePicker(
                title: "Microfone",
                devices: appState.inputDevices,
                selection: appState.preferredInputDeviceId,
                onSelect: { appState.selectInputDevice($0) }
            )
            devicePicker(
                title: "Saída de áudio",
                devices: appState.outputDevices,
                selection: appState.preferredOutputDeviceId,
                onSelect: { appState.selectOutputDevice($0) }
            )

            Text("A preferência de dispositivo é aplicada às chamadas quando a engine SIP real estiver ativa.")
                .font(.caption)
                .foregroundStyle(.secondary)

            mediaPreferencesRows
        }
    }

    /// Codec e processamento de voz (Voice Processing I/O do macOS).
    @ViewBuilder
    private var mediaPreferencesRows: some View {
        Picker(
            "Codec preferido",
            selection: mediaBinding(\.preferredCodec)
        ) {
            ForEach(AudioCodecPreference.allCases) { codec in
                Text(codec.displayName).tag(codec)
            }
        }

        Toggle(
            "Cancelamento de eco",
            isOn: mediaBinding(\.echoCancellationEnabled)
        )

        Toggle(
            "Supressão de silêncio (VAD)",
            isOn: mediaBinding(\.silenceSuppressionEnabled)
        )

        Toggle(
            "Ganho automático do microfone",
            isOn: mediaBinding(\.autoGainControlEnabled)
        )
        // AGC faz parte do processamento de voz do sistema (eco) —
        // sem ele, não há o que ligar.
        .disabled(!appState.mediaPreferences.echoCancellationEnabled)

        Text("O codec preferido é anunciado primeiro ao PABX (a central decide) — alguns PABX não aceitam PCMA em primeiro; em caso de mudez, volte para PCMU. O cancelamento de eco usa o processamento de voz do macOS e embute a redução de ruído do sistema (em validação — se o áudio falhar, desligue). A supressão de silêncio corta o ruído de fundo quando você não está falando. Alterações valem a partir da próxima chamada.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func mediaBinding<Value>(
        _ keyPath: WritableKeyPath<MediaPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { appState.mediaPreferences[keyPath: keyPath] },
            set: { value in appState.updateMediaPreferences { $0[keyPath: keyPath] = value } }
        )
    }

    @ViewBuilder
    private var microphonePermissionRow: some View {
        LabeledContent("Permissão de microfone") {
            HStack(spacing: 8) {
                Text(microphonePermissionLabel)
                    .foregroundStyle(.secondary)
                switch appState.microphonePermission {
                case .undetermined:
                    Button("Solicitar acesso") { appState.requestMicrophoneAccess() }
                case .denied:
                    Button("Abrir Ajustes do Sistema") { openMicrophonePrivacySettings() }
                case .granted, .restricted, .unsupported:
                    EmptyView()
                }
            }
        }
    }

    private var microphonePermissionLabel: String {
        switch appState.microphonePermission {
        case .granted: return "Permitida"
        case .denied: return "Negada"
        case .restricted: return "Restrita pelo sistema"
        case .undetermined: return "Não solicitada"
        case .unsupported: return "Disponível no app empacotado"
        }
    }

    private func openMicrophonePrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func devicePicker(
        title: String,
        devices: [AudioDevice],
        selection: String?,
        onSelect: @escaping (String?) -> Void
    ) -> some View {
        Picker(
            title,
            selection: Binding(
                get: { selection ?? "" },
                set: { onSelect($0.isEmpty ? nil : $0) }
            )
        ) {
            Text("Padrão do sistema").tag("")
            ForEach(devices) { device in
                Text(device.isDefault ? "\(device.name) (padrão atual)" : device.name)
                    .tag(device.id)
            }
        }
    }

    // MARK: - Conta SIP

    @ViewBuilder
    private var accountSection: some View {
        if let account = appState.savedAccount, !isEditingAccount {
            Section("Conta SIP") {
                LabeledContent("Usuário", value: account.username)
                LabeledContent("Domínio", value: account.domain)
                LabeledContent("Transporte", value: "\(account.transport.rawValue.uppercased()) · porta \(String(account.port))")
                if let displayName = account.displayName, !displayName.isEmpty {
                    LabeledContent("Nome de exibição", value: displayName)
                }
                LabeledContent("Status") {
                    RegistrationStatusBadge(
                        state: appState.registrationState,
                        theme: themeStore.theme.resolvedBrandTheme(base: appState.brand.theme)
                    )
                }

                HStack {
                    Button("Editar conta") { isEditingAccount = true }
                    Spacer()
                    Button("Remover conta", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                }
            }
            .confirmationDialog(
                "Remover a conta SIP?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remover credenciais", role: .destructive) {
                    appState.removeAccount()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("As credenciais serão apagadas do Keychain e a conta será desregistrada.")
            }
        } else {
            Section("Conta SIP") {
                AccountFormView(
                    existingAccount: appState.savedAccount,
                    defaultDomain: appState.brand.defaultSipDomain,
                    isCancelable: isEditingAccount,
                    onSave: { account in
                        // Só fecha o formulário se o Keychain aceitou — em
                        // falha, o usuário não perde o que digitou.
                        if appState.saveAccount(account) {
                            isEditingAccount = false
                        }
                    },
                    onCancel: { isEditingAccount = false }
                )
            }
        }
    }

    // MARK: - Sobre

    private var aboutSection: some View {
        Section("Sobre") {
            LabeledContent("Aplicativo", value: appState.brand.appName)
            if !appState.brand.companyName.isEmpty {
                LabeledContent("Empresa", value: appState.brand.companyName)
            }
            if !appState.brand.supportEmail.isEmpty {
                LabeledContent("Suporte", value: appState.brand.supportEmail)
            }
            LabeledContent("Versão", value: AppInfo.versionLabel)
        }
    }
}

/// Versão do app: lida do bundle quando empacotado; fallback de dev via SPM.
enum AppInfo {
    static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "1.0.0-dev"
    }
}
