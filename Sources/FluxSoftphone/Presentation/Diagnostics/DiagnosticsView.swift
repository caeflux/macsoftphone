import SwiftUI
import AppKit
import FluxDomain
import FluxInfrastructure

/// Tela de diagnóstico para suporte/implantação (Ciclo 11,
/// docs/04_UI_UX_GUIDELINES.md). Tudo aqui é seguro de compartilhar:
/// usuário mascarado, nunca senha/token.
struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var copiedAt: Date?

    var body: some View {
        Form {
            Section("Conta e registro") {
                LabeledContent("Status do registro", value: RegistrationStatePresentation.label(for: appState.registrationState))
                if let account = appState.savedAccount {
                    LabeledContent("Usuário (mascarado)", value: LogSanitizer.maskUsername(account.username))
                    LabeledContent("Domínio SIP", value: account.domain)
                    LabeledContent("Transporte", value: "\(account.transport.rawValue.uppercased()) · porta \(String(account.port))")
                } else {
                    LabeledContent("Conta", value: "Não configurada")
                }
                LabeledContent("Último erro") {
                    if let error = appState.lastError, let at = appState.lastErrorAt {
                        Text("\(error) (\(at.formatted(date: .omitted, time: .shortened)))")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text("Nenhum").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Áudio") {
                LabeledContent("Permissão de microfone", value: microphonePermissionLabel)
                LabeledContent("Microfone", value: deviceLabel(appState.preferredInputDeviceId, in: appState.inputDevices))
                LabeledContent("Saída", value: deviceLabel(appState.preferredOutputDeviceId, in: appState.outputDevices))
            }

            Section("Aplicativo") {
                LabeledContent("Versão", value: AppInfo.versionLabel)
                LabeledContent("Engine SIP", value: appState.engineName)
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            }

            Section {
                if appState.diagnosticEntries.isEmpty {
                    Text("Nenhum evento ainda. Registre a conta ou faça uma chamada.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(appState.diagnosticEntries) { entry in
                                    Text("\(entry.timestamp.formatted(date: .omitted, time: .standard))  \(entry.message)")
                                        .font(.caption.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(entry.id)
                                }
                            }
                        }
                        .frame(height: 220)
                        .onChange(of: appState.diagnosticEntries.count) {
                            if let last = appState.diagnosticEntries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onAppear {
                            if let last = appState.diagnosticEntries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            } header: {
                Text("Eventos SIP e mídia")
            } footer: {
                Text("Evidência do que a engine fez de verdade: linhas \"SIP real\" mostram o tráfego com o servidor; linhas \"SIMULAÇÃO\" indicam a engine de desenvolvimento (nada é enviado à rede).")
            }

            Section {
                HStack {
                    Button("Copiar diagnóstico") { copyReport() }
                    if copiedAt != nil {
                        Text("Copiado ✓")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("O diagnóstico copiado é sanitizado: não contém senha, token ou número completo.")
            }
        }
        .formStyle(.grouped)
        .task { appState.refreshAudioState() }
    }

    private var microphonePermissionLabel: String {
        switch appState.microphonePermission {
        case .granted: return "Permitida"
        case .denied: return "Negada"
        case .restricted: return "Restrita pelo sistema"
        case .undetermined: return "Não solicitada"
        case .unsupported: return "Indisponível neste build"
        }
    }

    private func deviceLabel(_ preferredId: String?, in devices: [AudioDevice]) -> String {
        if let preferredId, let device = devices.first(where: { $0.id == preferredId }) {
            return device.name
        }
        if let systemDefault = devices.first(where: { $0.isDefault }) {
            return "Padrão do sistema (\(systemDefault.name))"
        }
        return "Padrão do sistema"
    }

    private func copyReport() {
        let report = buildReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copiedAt = Date()
    }

    /// Relatório em texto — passa pelo LogSanitizer como última defesa,
    /// mesmo que nenhum campo aqui devesse conter segredo.
    private func buildReport() -> String {
        var lines: [String] = []
        lines.append("=== Diagnóstico — \(appState.brand.appName) ===")
        lines.append("Data: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("Versão: \(AppInfo.versionLabel)")
        lines.append("Engine SIP: \(appState.engineName)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Registro: \(RegistrationStatePresentation.label(for: appState.registrationState))")
        if let account = appState.savedAccount {
            lines.append("Usuário: \(LogSanitizer.maskUsername(account.username))")
            lines.append("Domínio: \(account.domain)")
            lines.append("Transporte: \(account.transport.rawValue.uppercased()) porta \(account.port)")
        } else {
            lines.append("Conta: não configurada")
        }
        if let error = appState.lastError, let at = appState.lastErrorAt {
            lines.append("Último erro: \(error) em \(at.formatted(date: .omitted, time: .standard))")
        } else {
            lines.append("Último erro: nenhum")
        }
        lines.append("Permissão microfone: \(microphonePermissionLabel)")
        lines.append("Microfone: \(deviceLabel(appState.preferredInputDeviceId, in: appState.inputDevices))")
        lines.append("Saída: \(deviceLabel(appState.preferredOutputDeviceId, in: appState.outputDevices))")
        lines.append("")
        lines.append("--- Eventos SIP e mídia (últimos \(min(80, appState.diagnosticEntries.count))) ---")
        for entry in appState.diagnosticEntries.suffix(80) {
            lines.append("\(entry.timestamp.formatted(date: .omitted, time: .standard))  \(entry.message)")
        }
        return LogSanitizer.redactSecrets(in: lines.joined(separator: "\n"))
    }
}
