# 02 — Sistema White Label

## Objetivo

Permitir que o mesmo código gere versões diferentes do softphone para Flux, revendas e clientes estratégicos, sem criar forks manuais desorganizados.

## Princípios

- Marca deve ser configuração, não lógica espalhada.
- Assets devem ser substituíveis por brand.
- Cores e textos devem vir de tema.
- Domínios e endpoints devem ser configuráveis.
- O app deve suportar build padrão Flux mesmo sem configuração customizada.

## Estrutura sugerida

```text
WhiteLabel/
├── BrandConfig.swift
├── BrandTheme.swift
├── BrandLoader.swift
├── brand-config.json
└── BrandAssets/
    ├── logo-primary.pdf
    ├── logo-symbol.pdf
    ├── app-icon.icns
    └── splash-background.pdf
```

## Exemplo de `brand-config.json`

```json
{
  "brandId": "flux",
  "appName": "Flux Softphone",
  "companyName": "Flux Tecnologia",
  "supportEmail": "suporte@flux.net.br",
  "supportUrl": "https://flux.net.br",
  "privacyUrl": "https://flux.net.br/politica-de-privacidade",
  "apiBaseUrl": "https://api.flux.net.br",
  "provisioningBaseUrl": "https://provisioning.flux.net.br",
  "defaultSipDomain": "sip.flux.net.br",
  "theme": {
    "primaryColor": "#111827",
    "accentColor": "#2563EB",
    "successColor": "#16A34A",
    "warningColor": "#F59E0B",
    "dangerColor": "#DC2626",
    "backgroundColor": "#F8FAFC",
    "surfaceColor": "#FFFFFF",
    "textPrimaryColor": "#0F172A",
    "textSecondaryColor": "#475569"
  },
  "features": {
    "manualSipLogin": true,
    "provisioningLogin": true,
    "callHistory": true,
    "contacts": false,
    "crmIntegration": false,
    "autoUpdate": false
  }
}
```

O campo opcional `theme.onPrimaryColor` define a cor de texto/ícone sobre `primaryColor`; quando ausente, é calculada automaticamente por luminância (preto ou branco).

## Níveis de white label

### Nível 1 — Visual simples

- Nome do app.
- Logo.
- Ícone.
- Cor principal.
- Link de suporte.

### Nível 2 — Comercial/revenda

- Domínio SIP padrão.
- Endpoint de provisionamento.
- Textos de onboarding.
- Nome da empresa.
- Política de privacidade própria.

### Nível 3 — Produto customizado

- Feature flags.
- Integração específica.
- Regras de login próprias.
- Distribuição independente.

## Regras obrigatórias

- Nenhuma tela deve escrever “Flux” hardcoded, exceto quando puxado da configuração padrão.
- Nenhuma cor deve ser usada diretamente se representar identidade visual.
- Nenhum endpoint deve ficar solto em view model ou view.
- White label não pode exigir duplicar o projeto.

## Feature flags

As features devem ser lidas de configuração:

- `manualSipLogin`
- `provisioningLogin`
- `callHistory`
- `contacts`
- `crmIntegration`
- `autoUpdate`
- `diagnostics`

## Critério de aceite

É possível alterar nome, logo, cor primária e domínio SIP padrão modificando apenas arquivos de configuração/assets, sem mexer em lógica de chamada.
