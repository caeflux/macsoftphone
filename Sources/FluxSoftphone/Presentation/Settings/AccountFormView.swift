import SwiftUI
import FluxDomain

/// Formulário de cadastro/edição manual de conta SIP (Ciclo 3).
/// Valida com `SIPAccountValidator` e entrega um `SIPAccount` pronto —
/// persistência e registro são responsabilidade do chamador (AppState).
struct AccountFormView: View {
    let existingAccount: SIPAccount?
    let defaultDomain: String
    let isCancelable: Bool
    let onSave: (SIPAccount) -> Void
    let onCancel: () -> Void

    @State private var username: String
    @State private var password: String
    @State private var domain: String
    @State private var displayName: String
    @State private var authUsername: String
    @State private var outboundProxy: String
    @State private var transport: SIPTransport
    @State private var portText: String
    @State private var validationMessages: [String] = []
    @State private var showAdvanced: Bool

    init(
        existingAccount: SIPAccount?,
        defaultDomain: String,
        isCancelable: Bool,
        onSave: @escaping (SIPAccount) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingAccount = existingAccount
        self.defaultDomain = defaultDomain
        self.isCancelable = isCancelable
        self.onSave = onSave
        self.onCancel = onCancel

        _username = State(initialValue: existingAccount?.username ?? "")
        _password = State(initialValue: existingAccount?.password ?? "")
        _domain = State(initialValue: existingAccount?.domain ?? defaultDomain)
        _displayName = State(initialValue: existingAccount?.displayName ?? "")
        _authUsername = State(initialValue: existingAccount?.authUsername ?? "")
        _outboundProxy = State(initialValue: existingAccount?.outboundProxy ?? "")
        _transport = State(initialValue: existingAccount?.transport ?? .udp)
        // Porta explícita só aparece preenchida se difere do padrão do transporte.
        let existingPort = existingAccount.map { account in
            account.port == account.transport.defaultPort ? "" : String(account.port)
        }
        _portText = State(initialValue: existingPort ?? "")
        let hasAdvanced = existingAccount.map {
            $0.authUsername != nil || $0.outboundProxy != nil || $0.transport != .udp
                || $0.port != $0.transport.defaultPort
        } ?? false
        _showAdvanced = State(initialValue: hasAdvanced)
    }

    var body: some View {
        TextField("Usuário SIP", text: $username, prompt: Text("ex.: 1001"))
        SecureField("Senha", text: $password)
        TextField("Domínio SIP", text: $domain, prompt: Text(defaultDomain.isEmpty ? "sip.exemplo.com" : defaultDomain))
        TextField("Nome de exibição (opcional)", text: $displayName)

        DisclosureGroup("Avançado", isExpanded: $showAdvanced) {
            TextField("Usuário de autenticação (opcional)", text: $authUsername)
            TextField("Proxy de saída (opcional)", text: $outboundProxy)
            Picker("Transporte", selection: $transport) {
                ForEach(SIPTransport.allCases, id: \.self) { option in
                    Text(option.rawValue.uppercased()).tag(option)
                }
            }
            TextField("Porta", text: $portText, prompt: Text(String(transport.defaultPort)))
        }

        if !validationMessages.isEmpty {
            ForEach(validationMessages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }

        HStack {
            Button("Salvar e registrar") { submit() }
                .buttonStyle(.borderedProminent)
            if isCancelable {
                Button("Cancelar") { onCancel() }
            }
        }
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = portText.trimmingCharacters(in: .whitespaces)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthUsername = authUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProxy = outboundProxy.trimmingCharacters(in: .whitespacesAndNewlines)

        var port: Int?
        var portInvalid = false
        if !trimmedPort.isEmpty {
            if let parsed = Int(trimmedPort) {
                port = parsed
            } else {
                portInvalid = true
            }
        }

        var errors = SIPAccountValidator.validate(
            username: trimmedUsername,
            password: password,
            domain: trimmedDomain,
            port: port
        )
        if portInvalid, !errors.contains(.invalidPort) {
            errors.append(.invalidPort)
        }

        validationMessages = errors.map(UserMessages.message(for:))
        guard errors.isEmpty else { return }

        let account = SIPAccount(
            username: trimmedUsername,
            password: password,
            domain: trimmedDomain,
            displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName,
            authUsername: trimmedAuthUsername.isEmpty ? nil : trimmedAuthUsername,
            outboundProxy: trimmedProxy.isEmpty ? nil : trimmedProxy,
            transport: transport,
            port: port
        )
        onSave(account)
    }
}
