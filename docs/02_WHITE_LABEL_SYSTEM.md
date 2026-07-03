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

## Tema editável em runtime (etapa white label — 2026-07)

Além do `brand-config.json` embarcado (identidade da marca por build), existe uma
camada de personalização editável em runtime:

- **Modelo**: `WhiteLabelTheme` (`Sources/FluxWhiteLabel/WhiteLabelTheme.swift`) —
  nome da marca, logo, cores (primária/secundária/destaque/texto), fundo
  (sólido/gradiente 2–3 cores/imagem), opacidade do vidro, desfoque do fundo e
  raio dos cantos. Codable tolerante (campo ausente cai no padrão) e validável.
- **Persistência**: `ThemeStore` (`Sources/FluxWhiteLabel/ThemeStore.swift`) —
  JSON legível em `Application Support/<bundle>/<brandId>/theme/white-label-theme.json`;
  logo e imagem de fundo como arquivos ao lado, referenciados por nome relativo.
  Arquivo corrompido/ausente cai no tema padrão derivado do `brand-config.json`.
- **Editor**: seção "Aparência" (`BrandingSettingsView`) com preview em tempo
  real (`ThemePreviewView`) e botão de restaurar padrão.
- **Aplicação**: `WhiteLabelTheme.resolvedBrandTheme(base:)` projeta as cores
  customizadas sobre o `BrandTheme` embarcado — as views continuam consumindo
  `BrandTheme`. Cores semânticas (sucesso/aviso/perigo) NÃO são personalizáveis:
  verde de atender e vermelho de encerrar são convenção de telefonia.
- **Visual**: `GlassPhoneShell`/`GlassCard`/`ThemedBackgroundView`/`BrandLogoView`
  aplicam o glassmorphism; o discador vive dentro do shell em formato smartphone.
- **Export/import**: `ThemeStore.exportThemeJSON()`/`importTheme(from:)` são o
  contrato JSON para distribuir temas por tenant (UI de export/import é etapa
  futura; imagens não vão no export v1).

## Critério de aceite

É possível alterar nome, logo, cor primária e domínio SIP padrão modificando apenas arquivos de configuração/assets, sem mexer em lógica de chamada.
