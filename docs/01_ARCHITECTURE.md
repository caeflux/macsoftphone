# 01 — Arquitetura Técnica

## Direção arquitetural

A aplicação deve ser dividida em camadas claras:

1. Presentation
2. Application
3. Domain
4. Infrastructure
5. WhiteLabel
6. Shared/Core

A UI nunca deve chamar diretamente bibliotecas SIP, APIs externas ou armazenamento sensível. Tudo deve passar por serviços, protocolos ou view models.

## Estrutura sugerida

```text
FluxSoftphoneMac/
├── App/
│   ├── FluxSoftphoneApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
├── Presentation/
│   ├── Onboarding/
│   ├── Dialer/
│   ├── Call/
│   ├── History/
│   ├── Contacts/
│   ├── Settings/
│   └── Components/
├── Application/
│   ├── UseCases/
│   ├── Coordinators/
│   └── ViewModels/
├── Domain/
│   ├── Entities/
│   ├── ValueObjects/
│   ├── Repositories/
│   └── Services/
├── Infrastructure/
│   ├── SIP/
│   ├── Audio/
│   ├── Persistence/
│   ├── Keychain/
│   ├── Networking/
│   └── Logging/
├── WhiteLabel/
│   ├── BrandConfig.swift
│   ├── BrandTheme.swift
│   ├── BrandAssets/
│   └── brand-config.json
├── Resources/
├── Tests/
└── UITests/
```

## Camadas

### Presentation

Responsável por telas, componentes e interação visual.

Não deve conter:

- Senhas SIP.
- Manipulação direta de registro SIP.
- Chamadas diretas para engine de áudio.
- Decisões de transporte/protocolo.

### Application

Coordena fluxos de uso:

- Login/provisionamento.
- Registrar conta.
- Fazer chamada.
- Receber chamada.
- Atualizar histórico.
- Trocar dispositivo de áudio.

### Domain

Contém conceitos centrais:

- SIPAccount.
- CallSession.
- CallDirection.
- CallState.
- RegistrationState.
- AudioDevice.
- Contact.
- CallHistoryEntry.
- TenantBrand — implementado como `BrandConfig` no módulo WhiteLabel (ver `docs/02_WHITE_LABEL_SYSTEM.md`), fora do Domain, para o domínio não depender de marca.

### Infrastructure

Implementa detalhes técnicos:

- SIP engine.
- Áudio.
- Keychain.
- Persistência local.
- APIs Flux.
- Logs.
- Monitoramento de rede.

### WhiteLabel

Centraliza personalização:

- Nome do app.
- Bundle/display name.
- Logo.
- Cores.
- Domínio/API base.
- Textos institucionais.
- Links de suporte.
- Política de privacidade.

## Protocolos obrigatórios

Crie interfaces/protocolos para evitar acoplamento:

```swift
protocol SIPClientProtocol {
    func configure(account: SIPAccount) async throws
    func register() async throws
    func unregister() async
    func makeCall(to destination: String) async throws -> CallSession
    func answer(callId: String) async throws
    func reject(callId: String) async throws
    func hangup(callId: String) async throws
}

protocol AudioDeviceServiceProtocol {
    func listInputDevices() -> [AudioDevice]
    func listOutputDevices() -> [AudioDevice]
    func setInputDevice(_ id: String) throws
    func setOutputDevice(_ id: String) throws
}

protocol SecureCredentialsStoreProtocol {
    func save(account: SIPAccount) throws
    func loadAccount() throws -> SIPAccount?
    func clear() throws
}
```

## Estados críticos

### RegistrationState

- idle
- registering
- registered
- failed
- disconnected
- expired

### CallState

- idle
- incoming
- dialing
- ringing
- active
- held
- ending
- ended
- failed

## Regra de ouro

Toda alteração deve preservar a capacidade de testar o core sem abrir a UI.
