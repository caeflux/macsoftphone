# 06 — Integrações com Ecossistema Flux

## Objetivo

Preparar o softphone para integração progressiva com produtos Flux, sem tornar o MVP dependente de APIs ainda não finalizadas.

## Integrações futuras previstas

- Provisionamento por usuário/tenant.
- PABX multi-tenant.
- SBC Flux.
- CRM Flux.
- Omnichannel.
- Histórico centralizado.
- Click-to-call.
- Contatos empresariais.
- Gravações de chamadas.
- Relatórios de uso.
- Diagnóstico técnico para suporte.

## Estratégia correta

Criar interfaces desde o início, mesmo que a implementação inicial seja mock/local.

Exemplo:

```swift
protocol ProvisioningServiceProtocol {
    func fetchProvisioningConfig(code: String) async throws -> ProvisioningConfig
}

protocol FluxAccountServiceProtocol {
    func login(email: String, password: String) async throws -> FluxSession
    func fetchSipAccounts(session: FluxSession) async throws -> [SIPAccount]
}

protocol ContactDirectoryProtocol {
    func searchContacts(query: String) async throws -> [Contact]
}
```

## Provisionamento

Fluxo desejado:

1. Usuário recebe link, código ou QR code.
2. App valida o provisionamento.
3. App baixa configuração SIP e white label.
4. App salva credenciais com segurança.
5. App registra automaticamente.

## Click-to-call

Preparar suporte a deep link:

```text
fluxphone://call/51999999999
fluxphone://call?number=51999999999
```

O app deve:

- Validar número.
- Abrir discador com número preenchido.
- Não chamar automaticamente sem confirmação, a menos que exista configuração explícita.

## CRM

Futura integração com CRM deve permitir:

- Iniciar chamada a partir de contato/deal.
- Exibir dados básicos do contato em chamada recebida.
- Registrar chamada no histórico do CRM.
- Associar chamada a lead/cliente.

## PABX multi-tenant

O app deve suportar conceitos como:

- Tenant.
- Ramal.
- Usuário.
- Permissões.
- Plano/restrição de chamadas.
- Domínio SIP por tenant.

## Diagnóstico para suporte Flux

Futuro endpoint poderá receber diagnóstico sanitizado:

- Versão do app.
- Marca.
- Domínio SIP.
- Estado de registro.
- Último erro.
- Sistema operacional.
- Dispositivos de áudio.

Não enviar senha, token, áudio ou payload SIP completo.

## Regra obrigatória

Nenhuma integração Flux deve ser implementada diretamente na UI. Sempre usar service/protocol.
